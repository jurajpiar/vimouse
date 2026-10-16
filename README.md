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

Press ⌘⇧Space to enter Pointer mode. The status strip at the screen edge lists the
keys valid at any moment. Defaults:

Pointer: i/o/j/k pick a quadrant, Backspace or u goes up a level. Return or m
left-clicks and exits, Space clicks and stays, x double-clicks, . right-clicks,
, middle-clicks. Hold Shift, Cmd or Option with any click key to pass the modifier
into the click. v presses the left button (drag or select); navigate, then v again
releases. s enters Scroll mode. Escape exits (releasing any drag).

Scroll: j/k/h/l scroll at the pointer, d/u half a page, s back to Pointer.

Counts work as in vi: digits before a command repeat or scale it. 45j scrolls 45
steps, 3⌫ goes up three levels, 3⏎ triple-clicks, and with several displays 2⇥
jumps to screen 2 (bare Tab / Shift+Tab cycle). Escape with a count pending cancels
the count.

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
