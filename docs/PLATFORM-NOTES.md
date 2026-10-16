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
