# vimouse: plan v0.1

Status: v0.2, decisions from first review applied. Owner: Shan. Last edited 2026-10-16.

## 1. Goal and scope

vimouse is a macOS menu-bar app that drives the mouse pointer from the keyboard. It must cover what a mouse does (move, left/right/middle click, double click, modifier clicks, drag, text selection, scroll, context menu) and add a few things a mouse does not do (a reading ruler, snapping to on-screen elements). The underlying purpose is to help Shan read on-screen text faster.

Longer term, vimouse becomes one mode of a system-wide "mac vim mode". That goal only shapes the architecture now (a modal engine with pluggable modes and a key-sequence parser that can later take counts and operators). It is not in scope for v1.

## 2. What prior art tells us

Tools in this space, with what each teaches:

warpd (C, cross-platform, open source). Modes: normal (hjkl pointer movement), hint, grid. Grid mode narrows by quadrant with u/i/j/k (top-left, top-right, bottom-left, bottom-right), so four keys pick a quadrant in one press. Drag is "v, then move, then click". macOS problems it documents: hiding the real cursor fails in some apps (iTerm), secure input mode blocks the event tap, upgrades sometimes need `tccutil reset Accessibility`. Hacker News feedback on it: the recursive grid is hard to track because there is no visual indication of where you are in the descent; hint mode was reported as faster than grid; grid is the fallback when the accessibility tree is poor.

Vimac → Homerow (Swift; Vimac is open source, Homerow is a paid US$49.99 app and I could not confirm its source status, the ovim comparison lists it as open source). Hints over clickable elements from the accessibility (AX) tree, hjkl scrolling. Vimac's build notes show that Accessibility permission is lost after a clean build with a new signature, so dev builds must be signed with a stable identity.

Shortcat (closed, free). Fuzzy search over AX element labels. Its author stated the App Store is a poor fit because the AX API does not work in the sandbox. Users reported it misses elements in apps with poor AX support and asked for a grid fallback and an OCR fallback.

Neru (Go + Objective-C, MIT). Hints, grid, scroll. Its maintainer recommends grid over hints because grid needs no per-app workarounds. Text config (TOML), CLI over IPC, runs as a launchd service. Electron apps need special handling for AX.

Scoot (Swift, BSD-3, actively maintained as of 2026). Grid plus element hints in Swift. Worth reading its source before we write the overlay and event code: https://github.com/mjrusso/scoot (not fetched in this session, flagged for you to open).

Mouseless and Mousio: commercial grid-only tools; the complaint is keystroke count versus hints.

Platform findings from Apple developer forums: an active (filtering) CGEventTap needs Accessibility permission; if the user revokes it while the tap is live, clicks can stop working system-wide until reboot. There is no reliable notification for revocation, and `AXIsProcessTrusted()` keeps returning true. The working mitigation is to poll by attempting `CGEventTapCreate` on a timer and tear down the tap when it returns NULL. Apple DTS also notes that posting events is a separate TCC service (PostEvent, shown under Accessibility) from listening (ListenEvent, shown under Input Monitoring). The frequent "screen recording" re-prompts in Sequoia do not apply to us unless we capture screen pixels (which the OCR fallback would need, another reason to defer it).

Takeaways applied below: grid mode is the robust core, hints are the speed layer on top; show descent state visually; sign dev builds stably; handle permission revocation and tap timeouts; do not target the App Store.

## 3. Interaction design

Activation: a global hotkey defined in the config file (default Cmd+Shift+Space) enters Pointer mode; a menu bar editor may come later. Escape always returns to idle. Modes are shown in a small, unobtrusive status badge on the overlay.

Bisect navigation. The screen under the pointer is divided into four equal rectangles with a visible outline. One key picks a rectangle, which then subdivides. Decided: quadrant keys, default i/o/j/k (top-left, top-right, bottom-left, bottom-right), all four configurable. Arrows are not a natural fit for quadrants and are left unbound by default. On a 2560x1440 display about 8 presses get from full screen to a 10 px cell. A 3x3 split keyed to qwe/asd/zxc (about 5 presses) stays as a config option to evaluate after the spike. hjkl nudge the pointer by a configurable step and only in an explicit Nudge sub-mode (n), because j and k mean something else in bisect.

Descent state is drawn: the current rectangle in a strong colour, ancestors as faint outlines, and Backspace (or u) goes up one level. This addresses the warpd complaint directly.

Actions, available at any depth: Enter or m for left click, . for right click (and the context-menu key), , for middle, x for double click, Space for click-and-stay, with Shift/Cmd/Option held for modifier clicks. v starts a drag (mouse down), navigate, v again releases; Escape releases too. Text selection is a drag plus an option to snap the endpoints to AX text positions. s toggles Scroll mode (jk/hl scroll at the pointer by a configurable step, d/u half a page; key repeat is honoured only here).

Snapping: after a bisect step, optionally jump the pointer to the centre of the nearest AX element inside the rectangle instead of the rectangle centre. This gets most of the benefit of hints without a hint overlay.

Ruler mode (r): draws a horizontal translucent band at the pointer's y, optionally dims the rest of the screen, and j/k move it. Phase 2 of the ruler uses the focused app's AX text to snap the band to actual text lines and move line by line. This is the feature that most directly serves faster reading, so it gets its own measurement task (section 7).

Discoverability (must-have). Three layers, drawn from hint tools (key on the target), which-key (contextual keys only, shown after a delay, hydra mode), the iPadOS hold-Command HUD (hold to show, release to hide) and Blender/VS Code status strips (one fixed line): (1) the quadrant key drawn faintly inside each rectangle, so navigation needs no legend; (2) a one-line status strip at the screen edge away from the current rectangle, colour-coded by mode, listing the five or six actions valid now, plus badges for armed modifiers and an active drag; shown fully for the first activations, then only after a configurable idle delay, with always/never options; (3) hold ? for the complete grouped key map of the current mode. Ancestor outlines in bisect are part of this (the warpd complaint about lost state).

Hint mode (f): after v1, possibly as part of the future vim mode rather than vimouse itself. Labels over AX elements, Vimium style.

## 4. Architecture

Language: Swift 5.10+, AppKit for overlays and the menu bar, SwiftUI only for a settings window if one is ever added. No Electron, no Go bridge; the OS APIs we need are all Apple frameworks and Swift keeps one toolchain. Other operating systems are a distant possibility; the Core/Mac split below is the only concession to it, since a port would rewrite the platform layer in any language.

Modules (Swift Package, so most code is testable without Xcode):

VimouseCore (platform-independent, compiles on Linux): geometry (rectangle subdivision, descent stack, multi-display coordinate maths), the modal state machine, the key-sequence parser (keycode-based, layout-independent), configuration model and parser. Unit tested with `swift test`.

VimouseMac (macOS only): InputTap (CGEventTap, keyboard only, active filtering so keys do not leak to the focused app while a mode is on; re-enables itself on `kCGEventTapDisabledByTimeout`; polls permission every few seconds and tears itself down if `CGEventTapCreate` starts returning NULL); Overlay (one borderless non-activating NSPanel per NSScreen, `ignoresMouseEvents`, level above full-screen apps, `canJoinAllSpaces` + `fullScreenAuxiliary`, redraw on display reconfiguration); Pointer (CGWarpMouseCursorPosition plus a synthetic mouseMoved so apps see hover; click/drag/scroll via CGEvent posting with correct click counts and modifier flags); AXBridge (element enumeration, text line bounds via parameterised attributes); Permissions (prompt, status, recovery guidance); Telemetry (a protocol receiving mode changes, ruler line advances and timestamps, with a no-op implementation, so reading instrumentation can plug in later without touching the modes); App (menu bar item, hotkey, launch at login, config file watcher).

Config: a text file at `~/.config/vimouse/config.toml` (versionable, like Neru), hot-reloaded. No GUI editor in v1.

Distribution: Developer ID signed and notarized DMG plus a Homebrew cask. Not the App Store (sandbox blocks the AX API). Minimum macOS: Sonoma 14. Licence: GPL-3.0-or-later (decided 2026-10-16; GPLv2-only would be incompatible with the Apache-2.0 licence most Swift packages use). Cursor: move the real cursor; drawing our own and hiding the real one is a later config flag, with the known caveat that hiding fails in some apps.

## 5. Development workflow and a constraint to accept

This session's cloud environment is Linux, and the linked-computer shell is a Linux VM, so neither can run `xcodebuild` or launch the app. The split above is still deliberate, but as of 2026-10-16 the cloud environment has no Swift toolchain and its proxy refuses download.swift.org, so VimouseCore tests also run on your Mac for now. Allowing download.swift.org in claude.ai Settings > Capabilities would let the cloud run `swift test`. All code is written here and committed into the repo folder on your Mac; you build and run it locally (`swift build`, `swift test`, `swift run vimouse`) and report back. Screenshots or log output pasted into the chat close the loop. Phase 0 exists to find out early how painful that loop is.

Repo layout: `Package.swift`, `Sources/VimouseCore`, `Sources/VimouseMac`, `Tests/VimouseCoreTests`, `docs/` (this plan, decisions log, test checklist), a `Makefile` for build/sign/notarize.

## 6. Phases

Phase 0, spike (small). One screen, one hotkey, overlay drawing one rectangle, event tap capturing hjkl, warp the cursor, click. Goal: validate permissions, tap behaviour, overlay level over full-screen apps, cursor warping, the dev loop. Decide 2x2 vs 3x3 default from measured keystroke counts.

Phase 1, usable pointer. Full bisect with descent stack and visuals, in-place key labels and status strip, multi-display, all click types, drag, Escape, config file, menu bar app. Unit tests for geometry and state machine.

Phase 2, scroll and selection. Scroll mode, visual (selection) mode, AX snapping, permission-revocation and tap-timeout handling, secure-input detection with a visible warning.

Phase 3, ruler. Band overlay, dimming, line snapping via AX text bounds, reading measurement.

Phase 4, hints. AX element labels, Electron/browser quirks, fallback to grid.

Phase 5, release. Signing, notarization, cask, README, launch at login, crash-safe shutdown (tap removed, mouse button released, overlay closed).

Phase 6, vim-mode foundations. Counts, operator-pending state, a command registry, so a future text mode can plug in.

## 7. Measuring the real goal

Deferred. Only the Telemetry stub in section 4 exists for it in v1. Design notes for later: never repeat a passage with the same reader (the second read measures memory); build a passage library ordered by readability (Flesch-Kincaid or Lexile) and compare matched passages before and after; comprehension needs questions, since pupil dilation tracks load rather than understanding; eye-tracking regression counts would be the ideal signal but webcam tracking is too coarse for it today. Evidence that rulers speed up reading for general readers is weak as far as I know, so treat the feature as a hypothesis.

## 8. Risks

Accessibility permission flow and revocation hang (mitigation in section 4). Secure input mode (password fields, some terminals) silently blocks the tap: detect and show a badge. Cursor hiding is unreliable; we do not hide the real cursor, we move it. Coordinate systems differ (AppKit uses a global space with origin at the bottom-left of the primary display and y up, Core Graphics puts the origin at the top-left of the primary display with y down): keep all geometry in one system inside VimouseCore and convert at the edges, with tests. Full-screen apps and Spaces can hide overlays if window flags are wrong. Keyboard layouts: bind to key codes, show layout-aware labels. Dev signing identity must stay stable or permissions reset on every build. Key repeat and held modifiers when the mode exits can leave an app seeing a stuck key or button: always release on exit.

## 9. Decisions log

2026-10-16: quadrant keys i/o/j/k, configurable; hotkey from config file only; Swift, macOS 14+; GPLv3; hints after v1; real cursor first; reading measurement stubbed via Telemetry protocol; tap-tap activation dropped.

2026-10-16: discoverability is a must-have (in-place labels, status strip, hold-? map), in Phase 1.

2026-10-16: licence GPL-3.0-or-later. Phase 0 scaffold committed (Package.swift, VimouseCore + tests, VimouseMac spike).

2026-10-16: Phase 0 verified on Shan's Mac: event tap, overlay over full-screen apps, cursor warp and click all work; display switching added (Tab/Shift+Tab, digits 1-9, bisect resets on switch). Phase 0 closed.

2026-10-16: 2x2 confirmed as the default after real use (3x3 would make the new navigation habit harder). Scroll mode, drag, modifier clicks, double click, click-and-stay and a first status strip implemented and verified on Shan's Mac (all tests green, status strip approved).

Phase 1 remaining: Nudge sub-mode, hold-? key map, config file. Phase 3 (ruler) may be pulled forward since it serves the reading goal directly.

2026-10-16: config `[keys]` split into `[pointer]`, `[actions]`, `[global]` and per-mode toggles; migration gained value-carrying renames. Drag ramp turned off by default (it broke text drags in Chromium apps).

Parked ideas, recorded on Shan's request:

Half-split navigation. Shan's proposal: show the rectangle split one way (top/bottom), up/down picks a half, left/right flips the split to vertical. Counter-proposal: each arrow halves along its own axis (up = top half, left = left half, and so on), both split lines drawn faintly, no orientation state; same cost (1 bit per press, about 15 presses to 10 px) but bits go where needed. Would live inside Pointer mode as a second key set (`[pointer] half_*`). Undecided.

Mode plugins. Modes behind a `Mode` protocol (keys handled, effects, hints, help, overlay contribution, own config section or `~/.config/vimouse/<mode>.toml`), a registry, `[modes] enabled = [...]`, and the config able to name a plugin. Caveat: runtime-loaded compiled Swift plugins need a stable ABI between app and plugin, which Swift only guarantees within one toolchain; realistic routes are modules compiled into the app and toggled in config, or a scripting layer (Lua) for user-written modes. The refactor towards the protocol is worth doing before Phase 6 (vim-mode foundations) regardless of loading mechanism.

2026-10-16: config migration no longer annotates inline (renames silent, retired block at the end); `[config] update` switch; `config.example.toml` and a generated man page `vimouse.1` rewritten on every start. Before the v1 release: delete the pre-release renames and superseded entries from ConfigSchema (and the Deprecations section they feed), since no released config ever had them.

Trackpad-like convenience (discussed 2026-10-16). What a trackpad has: modeless, analogue, inertial. Planned, in order: (1) trackpad-style scrolling: continuous scroll events with scroll and momentum phases, acceleration while a key is held, momentum tail on release (technique used by Mos and LinearMouse); (2) quasi-mode: hold a modifier (`[hotkey] hold`) to be in Pointer mode, release to leave, its modifier bit stripped from typed keys; (3) nudge acceleration while a key is held; (4) optional passthrough of system shortcuts (Spaces, Mission Control, zoom) from inside Pointer mode. Not attempted: synthesising multitouch gestures or magnify/swipe events (private APIs only). Shan's extension idea for the quasi-mode: a reverse quadrant search, or a non-linear expanding step in a chosen direction (2, 4, 8, 16 px or a doubling rectangle), as a navigation plugin alongside the half-split.

2026-10-16 (evening): quasi-mode (`[hotkey] hold`: one key or a chord, sided modifiers, both-sides rule, pin via the hotkey into `activate_mode`); start modes for hotkey and hold; activation leaves the pointer in place; trackpad-style scrolling (continuous events with phases, tap/hold/coast, brake, double-tap or `flick_with` flick, `friction`); sided modifier names in all key specs; `[colours.modes]` and `[colours.markers]`; config: inline comments, `[config] update`, example file and generated man page, silent renames with a retired block. Drag ramp off by default.

Next candidates, in suggested order: (1) Phase 2 robustness: permission-revocation handling (poll CGEventTapCreate, tear down), secure-input detection with a badge; (2) a standalone .app bundle with launch at login and a stable signing identity, so the app no longer needs a terminal and the Accessibility grant stops resetting (part of Phase 5, pulled forward); (3) nudge acceleration while a key is held; (4) parked: ruler polish (AX line snapping), half-split keys, expanding-step navigation, mode plugin refactor, system-shortcut passthrough.

2026-10-16 (late): app bundle (`scripts/bundle.sh`, `scripts/install.sh`, Info.plist with LSUIElement, Developer ID signing picked automatically, Launch at login via SMAppService) installed and verified. Phase 2 robustness verified: Accessibility revoked while running tears the tap down and restores it on re-grant (clicks never froze); secure input shows a lock (system password dialogs enable it, a plain `sudo` prompt does not, which is the terminal's call).

2026-10-16 (night): nudge acceleration (tap = step, hold ramps to `[nudge] speed`, release stops dead, two keys steer diagonally at the same speed) and ruler line snapping (`[ruler] snap`, `pad`, `snap_toggle`: the band is created on the line of text under the pointer and moves a line at a time via the accessibility API's RangeForPosition / LineForIndex / RangeForLine / BoundsForRange; probes run at the pointer's column at creation, so with two apps side by side the band follows whichever window is under that column) implemented. Ruler polish still open: `[ruler] width` (`screen` / `line` / `window`) so the band shrinks to what it matched; dim only the matched window.

2026-10-16 (night): mode-plugin refactor done, pulled ahead of every other feature at Shan's request. Modes are compiled-in Swift package targets behind the `Mode` protocol (`docs/PLUGINS.md`): each owns its `[<id>]` config section (schema, parse, apply), its bindings, `handle`/`handleRelease`/`handleAnywhere`, hints, help, a manual paragraph and `Drawable`s; the engine keeps activation, counts, exit, clicks, drag, display switching, mode toggles, strip and help, and assembles a `Scene` the overlay renders generically. `[modes] enabled` chooses and orders the modes; the first is the default. Moved settings: `[snap] enabled` is `[pointer] snap`, `[drag] restart_search` is `[pointer] drag_restart` (migrated). Decision: compiled-in over runtime bundles or Lua for now. On a later C or Rust rebuild (Shan's thought): the plugin problem is a stable binary interface plus signing and crash isolation, not the language; Rust gives no stable ABI either, so drop-in plugins would mean a C ABI boundary whatever the language, which Swift can also expose. Rust would pay off for portability (Linux, Windows) since the platform layer is the part that changes; the data-only `Mode` interface is the shape that ports.

2026-10-16 (late night): ruler polish done (`[ruler] width` window/screen/line, pointer rides on the band, band removed by its own toggle or exit and kept only on an explicit switch); cursor marker as a second plugin kind (`[cursor] style`); strip glyphs (`[global] legend`); migration replaces reworded comments. Then "do it all": crash-safe shutdown (signals, uncaught exceptions, held buttons released, tap and overlay down); Phase 4 hints as a plugin (`f`, letter labels on AX clickables, click or move); Half and Expand modes as experimental plugins off by default (`enabledByDefault`); `[global] passthrough` for system shortcuts; `scripts/release.sh` (hardened runtime, notarytool, stapler, zip) and `Casks/vimouse.rb`. Phases 0 to 5 are complete apart from the first real notarised release and the tap repo; Phase 6 (operator-pending state, command registry) waits for a text mode to need it; reading measurement stays deferred.

Open: delete pre-release deprecations at v1; first notarised release and a `homebrew-vimouse` tap; Half and Expand behaviour to be decided by use; `AXLineProvider` and hints untested on Chromium content until Shan reports.

## Sources

- https://github.com/rvaiya/warpd
- https://news.ycombinator.com/item?id=33221901
- https://vim.tonis.dev/articles/best-homerow-alternatives (published by the ovim project; biased toward ovim)
- https://cdn.jsdelivr.net/gh/nchudleigh/vimac@master/README.md
- https://pkg.go.dev/github.com/y3owk1n/neru@v1.15.1
- https://gittrend.io/repo/mjrusso/scoot
- https://developer.apple.com/forums/thread/735204
- https://indiestack.com/2021/03/discoverable-key-commands/
- https://docsearch.algolia.com/mcp/docs/repo/folke/which-key.nvim
- https://pkg.go.dev/github.com/y3owk1n/neru@v1.43.0
- https://talk.tidbits.com/t/apple-reduces-excessive-sequoia-permission-requests-shifts-to-monthly/28621
