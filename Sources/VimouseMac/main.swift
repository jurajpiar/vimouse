#if canImport(AppKit)
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
app.run()
#else
print("vimouse runs only on macOS. VimouseCore and its tests build anywhere.")
#endif
