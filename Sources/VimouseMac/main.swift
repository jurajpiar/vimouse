#if canImport(AppKit)
import AppKit
import VimouseCore
import PointerMode
import HalfMode
import HintsMode
import NudgeMode
import ScrollMode
import RulerMode
import ExpandMode

// The modes this build ships, in default order (the first is the default mode).
// Remove a line (and its import) to drop a mode; add one for a new plugin target.
let modes: [Mode] = [PointerMode(), HalfMode(), HintsMode(), NudgeMode(), ScrollMode(), RulerMode(), ExpandMode()]
// Cursor markers selectable with [cursor] style; add a CursorStyle here for a new one.
let cursors: [CursorStyle] = [RingCursor(), CrosshairCursor(), DotCursor()]

// Headless line-provider check: vimouse --probe "App Name" ...
if let i = CommandLine.arguments.firstIndex(of: "--probe") {
    exit(Probe.run(apps: Array(CommandLine.arguments[(i + 1)...])))
}

let app = NSApplication.shared
let delegate = AppDelegate(modes: modes, cursors: cursors)
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
app.run()
#else
print("vimouse runs only on macOS. VimouseCore, the modes and their tests build anywhere.")
#endif
