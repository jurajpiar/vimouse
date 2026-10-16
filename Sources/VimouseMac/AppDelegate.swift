#if canImport(AppKit)
import AppKit
import VimouseCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var controller: Controller!

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = Controller()
        setUpStatusItem()

        guard Permissions.ensureAccessibility() else {
            NSLog("vimouse: waiting for Accessibility permission (System Settings > Privacy & Security > Accessibility)")
            Permissions.pollUntilTrusted { [weak self] in self?.startTap() }
            return
        }
        startTap()
    }

    private func startTap() {
        do {
            try controller.start()
            NSLog("vimouse: ready. Press ⌘⇧Space.")
        } catch {
            NSLog("vimouse: could not start event tap: \(error)")
        }
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "vm"
        let menu = NSMenu()
        menu.addItem(withTitle: "Activate pointer (⌘⇧Space)", action: #selector(activate), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit vimouse", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    @objc private func activate() { controller.activateFromMenu() }
    @objc private func quit() { NSApp.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }
}
#endif
