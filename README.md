# vimouse

Keyboard-driven mouse for macOS. Divide the screen into quadrants, pick one with
i/o/j/k, repeat until the pointer is where you want it, then click. See
`docs/PLAN.md` for the design and roadmap, `docs/PLUGINS.md` for how modes are
built as plugins, and `docs/PLATFORM-NOTES.md` for what the macOS APIs turned out
to do.

Status: pre-release. Expect rough edges.

## Build and run (macOS 14+, Xcode 15+ command line tools)

```
swift build
swift test            # VimouseCore unit tests
swift run vimouse     # menu bar item "vm" appears
```

Press ⌘⇧Space to enter Pointer mode, or set `[hotkey] hold` to a modifier
chord (`"cmd+ctrl+alt+shift"`, a Karabiner hyper key) or one key (`"right_cmd"`)
to be in Pointer mode only while it is held; its modifiers are ignored on what you
type, but the same modifier on the other side still counts (hyper on the left plus
right Shift gives ⇧r). The hotkey pressed meanwhile pins the mode so it survives
the release. The status strip at the screen edge lists the
keys valid at any moment. Defaults:

Modes are plugins (`docs/PLUGINS.md`); `[modes] enabled` in the config picks which
are available and which is the default. The standard four:

Pointer: i/o/j/k pick a quadrant, Backspace or u goes up a level, Shift+u or
Shift+Backspace back to the whole screen. Return or m
left-clicks and exits, Space clicks and stays, x double-clicks, . right-clicks,
, middle-clicks. Hold Shift, Cmd or Option with any click key to pass the modifier
into the click. v presses the left button (drag or select) and, unless
`[pointer] drag_restart = false`, restarts the quadrant search from the whole
screen; navigate (any mode, any display), then v or Return releases. Escape during a drag cancels it and returns the pointer to
where the button went down. s enters Scroll mode. a toggles snapping: when on (`[pointer] snap`, the default), each
step sends the pointer to the nearest clickable element inside the chosen rectangle
(read from the frontmost app's accessibility tree) instead of its centre; a pink
ring marks the snap target. Escape exits (releasing any drag).

Half (work in progress; add `"half"` to `[modes] enabled` to try it): b enters a
second way of narrowing down, starting from the whole screen:
h/j/k/l or the arrows keep the left/bottom/top/right half of the current rectangle,
Backspace or u go up a level, Shift+u back to the whole screen, b back to Pointer
(whose descent is kept).

Hints: f labels every clickable element the frontmost app exposes through
accessibility with a letter or two; type the label to click it (or only move there
with `[hints] click = false`). Backspace deletes a letter, f or Escape leaves.

Expand (work in progress; add `"expand"` to `[modes] enabled`): E enters it;
h/j/k/l or the arrows move 8 px, each further press the same way doubles the step,
the opposite direction halves it, so you overshoot and home in.

Nudge: n from Pointer mode, then h/j/k/l or the arrows move the pointer (a tap is
one step, a hold accelerates, release stops, a horizontal and a vertical key held
together move diagonally; Shift: one pixel per repeat; counts multiply), n back to
the quadrants.

Scroll: j/k/h/l scroll at the pointer (a tap is one step, a hold accelerates,
release coasts, a double tap flicks the page at speed, a tap during a coast
stops it),
d/u half a page, s back to Pointer.

Hold ? in any mode for the full key map; release to hide. System shortcuts listed
in `[global] passthrough` (Cmd-Tab, Spotlight, Spaces, Mission Control and
screenshots by default) keep working while a mode is active. The strip shows actions
as words, with keys as symbols (⇧ ⌘ ↓); `[global] legend = "symbols"` turns the
action words into glyphs too (● click, ⤒ drag, ⇅ scroll, ✕ exit).

A marker is drawn at the pointer while a mode is active: `[cursor] style` picks
`ring` (default), `crosshair`, `dot` or `""` for none; `size` and `colour` tune it.

Ruler (reading band): r creates a band at the pointer's height, dimming the rest
of the screen, and enters Ruler mode: j/k move it by its own height (or a fixed number of pixels
via `[ruler] move`), [ ] change its height (the top edge stays put, so the band grows or shrinks in the
direction of reading), Shift with any of those moves or
resizes by one pixel, s goes to
Scroll mode (scroll the text under a fixed band) and keeps the band; r again or
Escape removes it; Shift+r removes a kept band from any mode. With `[ruler] snap = true` (off by default) the band
reads the lines of text under the pointer's column through the accessibility API: it
is created on the line under the pointer, sized to it (plus `[ruler] pad`), and j/k
move it a line at a time, falling back to height steps where no text is found; a
toggles this in Ruler mode, and the legend greys "lines" while no text is under the
band. Only apps that report their lines are followed (AppKit text views, WebKit);
`[ruler] snap_tricks = true` adds Chromium browsers and Electron apps, where lines are
reconstructed from character rectangles and can be picked wrongly. e extends the band over the next line below (reading
in blocks), c collapses it back to the last line taken in; moving an extended band
collapses it first. The band and the dimming span the window holding the
text (`[ruler] width = "window"`), the whole display (`"screen"`) or the line
itself (`"line"`), and the pointer rides on the band.

Counts work as in vi: digits before a command repeat or scale it. 45j scrolls 45
steps, 3⌫ goes up three levels, 3⏎ triple-clicks, and with several displays 2⇥
jumps to screen 2 (bare Tab / Shift+Tab cycle). Escape with a count pending cancels
the count.

## Configuration

On first run vimouse writes `~/.config/vimouse/config.toml` with every binding and
tunable, each with a one-line comment and example values. Edit and save; the app
reloads within a second. A parse error keeps the previous settings and turns the
menu bar item into "vm!"; "Show config error" in the menu says why.

On every start the file is brought up to date (unless `[config] update = false`):
settings added in a newer version are appended with their defaults and comments,
renamed settings move with their values, and unknown or superseded settings are
gathered into a short "Retired settings" block at the end. Your values and
comments are kept. Next to it, `config.example.toml` (the current defaults) and
`vimouse.1` (the manual, `man ~/.config/vimouse/vimouse.1`, or "Open manual" in
the menu) are rewritten on every start. Arrow keys, page up/down, home and end can be bound like any other key
(`down = ["j", "down"]`), and the legend and in-rectangle labels show whatever is
bound.

## Installing

With Homebrew:

```
brew install --cask jurajpiar/vimouse/vimouse
```

Then grant Accessibility access when asked (System Settings > Privacy & Security >
Accessibility) and start vimouse from /Applications.

## Installing from source

`swift run` is fine for development, but macOS then attributes the Accessibility
permission to your terminal. For daily use build the bundle:

```
./scripts/install.sh            # builds, signs, installs ~/Applications/vimouse.app, launches it
```

On first launch macOS asks for Accessibility access for vimouse itself; grant it
under System Settings > Privacy & Security > Accessibility. "Launch at login" in
the menu bar menu registers the app with the system (it is greyed out when running
from a terminal).

The grant is tied to the code signature. To keep it across rebuilds the script
signs with a stable identity: `SIGN_IDENTITY` if set, else a certificate named
`vimouse-dev`, else a valid Developer ID Application or Apple Development
certificate from your keychain. Without any of those, create a self-signed
code-signing certificate once, in Keychain Access > Certificate
Assistant > Create a Certificate, with name `vimouse-dev`, identity type
"Self Signed Root", certificate type "Code Signing". `scripts/bundle.sh` picks it up
by name. Without either, the build is signed ad-hoc and the permission has to be
re-granted after every rebuild.

## Status in the menu bar

`vm` means all is well. `vm⚠︎`: Accessibility access is missing or was revoked; the
event tap is stopped so the system keeps working, and it restarts by itself once
access is granted again. `vm🔒`: an app has secure input on (a password field, or a
terminal with Secure Keyboard Entry), which blocks every event tap system-wide until
it ends. `vm!`: the config file did not parse. Hover for details.

## Accessibility permission

The event tap needs Accessibility access. When run from a terminal with
`swift run`, macOS attributes the permission to the terminal app (the
"responsible process"), so grant it to Terminal or iTerm under System Settings >
Privacy & Security > Accessibility. For the installed app, grant it to vimouse.

If the pointer stops responding after revoking the permission while vimouse is
running, quit vimouse. That is a known macOS behaviour with active event taps
and is handled in Phase 2.

## Releasing

Two scripts, both run on a Mac with a "Developer ID Application" certificate and
`gh` logged in:

```
scripts/release.sh 0.1.0    # stamps the version, builds, signs (hardened runtime),
                            # notarises, staples, zips, fills in Casks/vimouse.rb
scripts/publish.sh 0.1.0    # commits the stamp, tags v0.1.0, pushes, creates the
                            # GitHub release with the zip, pushes the cask to the
                            # homebrew-vimouse tap (created on first run)
```

One-time: `xcrun notarytool store-credentials vimouse-notary --apple-id <id> --team-id <team>`.
After publishing, `brew audit --cask --online jurajpiar/vimouse/vimouse` checks the cask.

## Licence

GPL-3.0-or-later. See `LICENSE`.
