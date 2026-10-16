#if canImport(AppKit)
import AppKit
import VimouseCore
import PointerMode
import NudgeMode
import ScrollMode
import RulerMode

// The modes this build ships, in default order (the first is the default mode).
// Remove a line (and its import) to drop a mode; add one for a new plugin target.
let modes: [Mode] = [PointerMode(), NudgeMode(), ScrollMode(), RulerMode()]

let app = NSApplication.shared
let delegate = AppDelegate(modes: modes)
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
app.run()
#else
print("vimouse runs only on macOS. VimouseCore, the modes and their tests build anywhere.")
#endif
