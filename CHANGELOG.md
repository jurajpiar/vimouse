# Changelog

Settings that were renamed or removed are listed here so a commented-out line in
`config.toml` can be traced to its replacement.

## Unreleased

Initial settings: `[hotkey] activate`; `[keys]` quadrant and action bindings;
`[scroll]` step and bindings; `[ruler]` height, move, fine, height_step, dim and
bindings; `[nudge]` step and bindings; `[keys] top`; `[drag] restart_search`, `[drag] ramp`; `[keys] help`; `[snap] enabled`.

Superseded: `[ruler] step` (pixels per press) by `[ruler] move`, where `0` means
the band moves by its own height and any other value is pixels.
