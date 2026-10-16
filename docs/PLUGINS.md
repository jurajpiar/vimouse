# Modes as plugins

Every way of driving the pointer is a mode, and every mode is a plugin: a Swift
package target that depends only on `VimouseCore` and conforms to the `Mode`
protocol (`Sources/VimouseCore/Mode.swift`). The app ships four: Pointer, Nudge,
Scroll and Ruler, under `Sources/Modes/`.

## What a mode is

A mode owns its bindings and settings (one `[<id>]` section of `config.toml`),
handles the keys the engine passes it, and describes what to draw. It never
touches the platform: keys come in, `Effect`s (warp, click, scroll, ...) and
`Drawable`s (rectangles, rings, labels, a dim) go out. That keeps a mode
compilable and testable on Linux, and keeps the interface narrow enough to
survive a later port of the core.

The engine keeps what is shared: activation and the hotkey, the vi-style count
prefix, exit, clicks, the drag toggle, display switching, mode toggles, the
status strip and the help panel. A mode sees the shared state through a
`ModeContext` (screens, the pointer target, the drag state, services such as the
accessibility snapper and line finder, colours).

## Adding a mode

1. Create `Sources/Modes/<Name>/<Name>Mode.swift` with a `final class
   <Name>Mode: Mode`. Give it an `id` (the config section and the name used in
   `[modes] enabled` and `[hotkey] activate_mode`), a `name` for the strip, a
   `summary`, a `defaultColour`, a `schema` (only keys of its own section), a
   `Settings` struct and `parseSettings`/`apply`, a `toggle` key, and `handle`.
   Optional hooks: `handleRelease`, `handleAnywhere` (a binding that works in
   every mode), `activate`/`deactivate(exiting:)`, `screenChanged`,
   `dragStarted`, `hints`, `help`, `draw`, `manual`.
2. Add the name to the `modes` list in `Package.swift`.
3. Register it in `Sources/VimouseMac/main.swift` (import and one line in the
   `modes` array) and in `standardModes()` in the tests.

Removing a mode is the reverse. At run time `[modes] enabled` in `config.toml`
picks which registered modes can be entered, in order; the first is the default
mode that toggles return to.

## Cursor styles

The marker drawn at the pointer is the second plugin kind: a `CursorStyle`
(`Sources/VimouseCore/Cursor.swift`) has an `id`, a `summary` and
`draw(at:size:colour:)` returning `Drawable`s. Ring, crosshair and dot ship in
the core; register yours in the `cursors` array in `main.swift`. `[cursor] style`
picks one by id, `""` draws nothing; `size` and `colour` (`""` = the active
mode's colour) tune it.

## Limits

Effects are the platform's vocabulary: a mode can only ask for what `Effect`
lists. A mode that needs a new kind of platform action (a new event type) needs
the effect added to the core and implemented in `Sources/VimouseMac`. The scroll
and nudge drivers read their tunables from any mode whose settings conform to
`ScrollTunables` / `NudgeTunables`.

Modes are compiled in. Loading them at run time from bundles would need a stable
binary interface, signing, and crash isolation; see the plan for the trade-offs.
