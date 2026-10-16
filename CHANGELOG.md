# Changelog

Settings that were renamed or removed are listed here so a commented-out line in
`config.toml` can be traced to its replacement.

## Unreleased

Initial settings: `[hotkey] activate`; `[keys]` quadrant and action bindings;
`[scroll]` step and bindings; `[ruler]` height, move, fine, height_step, dim and
bindings; `[nudge]` step and bindings; `[keys] top`; `[drag] restart_search`, `[drag] ramp`; `[keys] help`; `[snap] enabled`.

Moved: the former `[keys]` section is split. Quadrant keys, `up`, `top` and
`snap_toggle` are now in `[pointer]`; the click keys and `drag` in `[actions]`;
`exit`, `help`, `next_screen`, `previous_screen` in `[global]`; `scroll_toggle` is
`[scroll] toggle`; `ruler_toggle` and `ruler_remove` are `[ruler] toggle` and
`remove`. Values move with their keys on the next start.

Superseded: `[ruler] step` (pixels per press) by `[ruler] move`, where `0` means
the band moves by its own height and any other value is pixels.
