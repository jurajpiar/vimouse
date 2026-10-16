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

Actions, available at any depth: Enter or m for left click, . for right click (and the context-menu key), , for middle, Enter twice quickly for double click, with Shift/Cmd/Alt held for modifier clicks. v starts a drag (mouse down), navigate, v again releases. Text selection is a drag plus an option to snap the endpoints to AX text positions. s enters Scroll mode (hjkl scroll, d/u half page, gg/G). Shift+Enter clicks and keeps the mode open.

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

Open: 2x2 vs 3x3 default (decide after spike measurements).

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
