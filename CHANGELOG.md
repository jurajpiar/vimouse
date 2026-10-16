# Changelog

Settings that were renamed or removed are listed here so a commented-out line in
`config.toml` can be traced to its replacement.

## Unreleased

Initial settings: `[config] update`; `[hotkey] hold`, `activate_mode`, `hold_mode`; `[hotkey] activate`; `[keys]` quadrant and action bindings;
`[scroll]` step, speed, acceleration, flick, flick_double_tap, flick_with, friction, momentum, smooth and bindings; `[ruler]` height, move, fine, height_step, dim and
bindings; `[nudge]` step, speed, acceleration and bindings; `[ruler]` snap, pad, snap_toggle, width; `[modes] enabled`; `[half]` bindings; `[cursor]` style, size, colour; `[pointer] snap` (was `[snap] enabled`) and `[pointer] drag_restart` (was `[drag] restart_search`), both migrated automatically; `[colours.modes]`, `[colours.markers]`; `[keys] top`; `[drag] restart_search`, `[drag] ramp`; `[keys] help`; `[snap] enabled`.

Moved: the former `[keys]` section is split. Quadrant keys, `up`, `top` and
`snap_toggle` are now in `[pointer]`; the click keys and `drag` in `[actions]`;
`exit`, `help`, `next_screen`, `previous_screen` in `[global]`; `scroll_toggle` is
`[scroll] toggle`; `ruler_toggle` and `ruler_remove` are `[ruler] toggle` and
`remove`. Values move with their keys on the next start.

Superseded: `[ruler] step` (pixels per press) by `[ruler] move`, where `0` means
the band moves by its own height and any other value is pixels.
