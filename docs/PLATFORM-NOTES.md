# Platform notes

What the macOS accessibility and event APIs actually do, as found while building
vimouse. Each entry says what was tried, what came back, and what the code does
about it, so the next person does not have to rediscover it. Dates are when it was
observed; behaviour can change with OS and app versions.

## Text lines through the accessibility API (ruler line snapping)

Goal: the bounds of the line of text under a point, and its neighbours, for any app.

AppKit text views (NSTextView and friends, 2026-10-16). The element at the point
answers the index-based parameterised attributes `AXRangeForPosition` (point to
character index), `AXLineForIndex`, `AXRangeForLine` and `AXBoundsForRange`, all in
top-left screen coordinates (the accessibility server flips them). Two calls per
line step. Used first by `AXLineProvider.lineFromTextElement`.

Chromium and Electron (Claude desktop, 2026-10-17). The element under a paragraph
is an `AXStaticText` holding the whole paragraph. It advertises both the index-based
and the text-marker attributes, but most are hollow without a screen reader:

- `AXLineForIndex` returns `Int.max`; `AXNumberOfCharacters` returns 0; the text is
  in `AXValue` and indices are UTF-16 offsets into it.
- `AXTextMarkerForPosition` returns nothing (its hit test is asynchronous and the
  cache is empty for a one-shot caller), with the point given in either coordinate
  system.
- `AXStartTextMarker` exists, and `AXLineTextMarkerRangeForTextMarker` answers, but
  the "line" range covers the whole document and `AXBoundsForTextMarkerRange` on it
  returns the web area's frame: there are no inline text boxes unless Chromium has
  decided an assistive technology is attached (setting `AXEnhancedUserInterface` and
  `AXManualAccessibility` on the application element exposes the tree but does not
  switch that on).
- `AXIndexForChildUIElement` on the web area returns nothing for the text node.
- `AXBoundsForRange` with a single-character index range works and returns real
  geometry in top-left coordinates (the first character sits at the element's
  `AXPosition`). Whitespace characters may return an empty rectangle. Character y
  is monotonic through the text.

What the code does (`lineFromCharBounds`): binary search over character indices for
the character whose row contains y, two more binary searches for the first and
last characters on that row, one `AXBoundsForRange` over that span for the line.
About thirty calls per line, a few milliseconds each. Stepping asks for the row
just past the current one; at the node's edge the screen is probed just below the
node's frame for the next text node. A row shared by several nodes (a link inside a
sentence) is merged by hit-testing left and right of the found segment at the same
height.

More Chromium findings (2026-10-17, unattended run with `vimouse --probe`, see
`scripts/autotest.sh`):

- Index ranges can have holes: characters that belong to inline children (links,
  code) return no rectangle from the parent node. A binary search that treats "no
  rectangle" as "move forward" slides to the last row. Sampling every twelfth
  character and then galloping outwards from a sample on the wanted row is robust
  to holes and costs a few dozen calls.
- Reported frames (`AXPosition`/`AXSize`) of text nodes and lists do not always
  match where their text is drawn: a paragraph's frame extended 150 px below its
  last row over the list that followed, and the list's frame started 140 px below
  its first row. Hit-testing by point in that region returns the wrong node. At the
  end of a node's text the provider therefore continues with the next text node in
  document order (next sibling, descending to its first text, climbing when
  siblings run out), which is also the order a reader wants.
- A row with inline code is exposed twice: the containing text node and a second
  node for the code span, a few pixels offset. Document order then yields the same
  row twice; a step skips a candidate on the row it is leaving, and rows of
  document-order neighbours on the same row are merged.
- Per step, once a node is known: about 1 to 5 ms.

Findings from a screen recording of real use (2026-10-17; the probe had passed
while the band still skipped lines), now covered by the probe walking a whole
column of the screen and comparing with plain hit tests:

- A node that starts on the row being left (text after an inline code span, in
  Claude desktop) was skipped whole, losing its further rows. The step now looks
  for that node's next row before moving on in document order.
- Brave's hit test returns the article container for some regions (a heading and
  the first rows of the paragraph after it), whose children carry one-pixel or
  misplaced frames. The container is now searched: its children are binary-searched
  by the y of their first character (document order runs down the page), and a
  node's rows are tried without trusting its frame.
- Text scrolled out of the window still has bounds. Lines outside the element's
  window (or the screen) are rejected and document-order stepping stops at the
  window's edge.
- The pointer's column can lie past the end of a short line; the cached line is
  matched by y alone and the probe also looks near the line's left edge.

WebKit findings (Markdown Preview, 2026-10-17):

- The index-based `AXBoundsForRange` answers with one glyph's geometry whatever
  the range (a 20-character span 50 px wide; every index on the first row). The
  provider detects this (a span narrower than seven glyphs, or a whole text on one
  row of a tall element) and uses the marker route instead.
- The marker route works: `AXStartTextMarker` on the text node, then
  `AXLineTextMarkerRangeForTextMarker` and `AXBoundsForTextMarkerRange` per line,
  `AXNextLineEndTextMarkerForTextMarker` then `AXNextTextMarkerForTextMarker` to
  step down. Bounds come in top-left coordinates here (the earlier assumption that
  marker values are Cocoa-flipped was wrong for WebKit; the code checks which
  reading lands inside the element and prefers unflipped when it fits).
- Going up: `AXPreviousLineStartTextMarkerForTextMarker` from a line's start is
  the line above; from the end of a block it is the block's first line, so the
  former is tried first and the result must be above the current line.
- A text node's start marker can precede the node (the walk from it began at the
  heading above); the walk simply continues until the row under the point.

Web area climb. In Electron apps the `AXWebArea` can be twenty-plus parents above
the hit element and each parent lookup takes a millisecond or more, so the climb
must be bounded, cached and done once; the first attempt timed out at 120 ms with
nothing to show. Budget is now 250 ms with the web area cached per lookup.

WebKit (Safari): untested as of 2026-10-17. The marker route
(`lineFromStartMarker`, `lineFromMarkers`) is kept for it; WebKit is the origin of
those attributes and does expose inline text boxes.

Text-marker coordinates. Values of the text-marker attributes are passed through
by the accessibility server unflipped, in Cocoa screen coordinates (origin bottom
left of the primary display), unlike the standard attributes. The code decides per
element which reading lands inside the element's own frame.

## Event tap and permissions

Active (filtering) `CGEventTap` needs Accessibility access. If the grant is revoked
while the tap is live, clicks can stop system-wide; `AXIsProcessTrusted()` keeps
returning true. The reliable probe is to attempt `CGEvent.tapCreate` on a timer
(every 3 s) and tear the tap down when it fails; it is recreated when the probe
succeeds again. Verified 2026-10-16: revoking and re-granting while running never
froze clicks.

A tap that takes too long is disabled by the system (`tapDisabledByTimeout`); the
callback re-enables it. Keep the key handler fast: no synchronous accessibility
walks on the tap thread beyond the bounded ones.

Secure input (`IsSecureEventInputEnabled`): system password dialogs enable it and
keys never reach the tap; a plain `sudo` prompt in a terminal does not (that is the
terminal's choice). Polled every second; the active mode is left and a lock badge
shown.

Synthetic events must be marked so the tap ignores them: `eventSourceUserData` is
stamped on everything vimouse posts.

Accessibility grants are tied to the code signature: an ad-hoc or changing
signature loses the grant on every rebuild. A stable Developer ID (or a
self-signed `vimouse-dev` certificate) keeps it. When run with `swift run` from a
terminal, the grant belongs to the terminal (the responsible process), which can
mask a missing grant for the app itself.

## Scrolling

Trackpad-style scrolling is `CGEvent(scrollWheelEvent2Source:)` with
`scrollWheelEventIsContinuous`, the scroll phase (began 1, changed 2, ended 4) and
momentum phase (begin 1, continuous 2, end 3) fields; apps then animate the
momentum themselves. Pixel deltas must be whole; the fractional remainder is
carried to the next frame.

## Drag and drop

A left-button press followed by warps is enough for text selection in native apps
and WebKit. Some apps start a drag-and-drop session only after movement following
the press; posting a few small drag events ("ramp") helps them but breaks text
drags in Chromium-based apps, which treat the ramp as a new selection. Ramp is off
by default (`[drag] ramp`). Escape cancels a drag-and-drop session system-wide; the
button is then released back at the origin.

## Overlay

One borderless, non-activating `NSPanel` per display at `.screenSaver` level with
`canJoinAllSpaces`, `fullScreenAuxiliary`, `stationary` and `ignoresMouseEvents`
draws above full-screen apps. AppKit's global coordinates have the origin at the
bottom left of the primary display with y up; Core Graphics and VimouseCore use
top left with y down; the two agree on x. Conversion happens only in
`Coordinates.swift`.

## Key events

Modifier sides come from device-level flag bits (left/right shift 0x02/0x04,
control 0x01/0x2000, option 0x20/0x40, command 0x08/0x10). A passed-through
shortcut's key-up must be matched to its key-down, not to its key code, or a plain
arrow's release is lost while `ctrl+arrow` is passed through.
