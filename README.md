# vimouse

Keyboard-driven mouse for macOS. Divide the screen into quadrants, pick one with
i/o/j/k, repeat until the pointer is where you want it, then click. See
`docs/PLAN.md` for the design and roadmap.

Status: Phase 0 spike. Expect rough edges.

## Build and run (macOS 14+, Xcode 15+ command line tools)

```
swift build
swift test            # VimouseCore unit tests
swift run vimouse     # menu bar item "vm" appears
```

Press ⌘⇧Space to enter Pointer mode, or set `[hotkey] hold` to a modifier
chord (`"cmd+ctrl+alt"`; avoid Shift, it would hide the shifted bindings) or one
key (`"right_cmd"`) to be in Pointer mode only while it is held; the hotkey
pressed meanwhile pins the mode so it survives the release. The status strip at the screen edge lists the
keys valid at any moment. Defaults:

Pointer: i/o/j/k pick a quadrant, Backspace or u goes up a level, Shift+u or
Shift+Backspace back to the whole screen. Return or m
left-clicks and exits, Space clicks and stays, x double-clicks, . right-clicks,
, middle-clicks. Hold Shift, Cmd or Option with any click key to pass the modifier
into the click. v presses the left button (drag or select) and, unless
`[drag] restart_search = false`, restarts the quadrant search from the whole
screen; navigate (any mode, any display), then v or Return releases. Escape during a drag cancels it and returns the pointer to
where the button went down. s enters Scroll mode. a toggles snapping: when on (the default), each
step sends the pointer to the nearest clickable element inside the chosen rectangle
(read from the frontmost app's accessibility tree) instead of its centre; a pink
ring marks the snap target. Escape exits (releasing any drag).

Nudge: n from Pointer mode, then h/j/k/l or the arrows move the pointer 5 px
(Shift: 1 px, counts multiply), n back to the quadrants.

Scroll: j/k/h/l scroll at the pointer (a tap is one step, a hold accelerates,
release coasts, a double tap flicks the page at speed, a tap during a coast
stops it),
d/u half a page, s back to Pointer.

Hold ? in any mode for the full key map; release to hide.

Ruler (reading band): r creates a band at the pointer's height, dimming the rest
of the screen, and enters Ruler mode: j/k move it by its own height (or a fixed number of pixels
via `[ruler] move`), [ ] change its height, Shift with any of those moves or
resizes by one pixel, s goes to
Scroll mode (scroll the text under a fixed band), r back to Pointer. The band stays
after Escape; Shift+r removes it.

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

## Accessibility permission

The event tap needs Accessibility access. When run from a terminal with
`swift run`, macOS attributes the permission to the terminal app (the
"responsible process"), so grant it to Terminal or iTerm under System Settings >
Privacy & Security > Accessibility. For a standalone build, grant it to the
`vimouse` binary instead; note that an unsigned or re-signed binary loses the
grant on every rebuild. A stable signing identity fixes that (Phase 5).

If the pointer stops responding after revoking the permission while vimouse is
running, quit vimouse. That is a known macOS behaviour with active event taps
and is handled in Phase 2.

## Licence

GPL-3.0-or-later. See `LICENSE`.
