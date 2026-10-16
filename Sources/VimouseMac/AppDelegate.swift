#if canImport(AppKit)
import AppKit
import VimouseCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var controller: Controller!
    private let configStore = ConfigStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = Controller()
        setUpStatusItem()
        configStore.onChange = { [weak self] config in
            self?.controller.apply(config)
            self?.statusItem.button?.title = self?.configStore.lastError == nil ? "vm" : "vm!"
        }
        configStore.start()

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
        menu.addItem(withTitle: "Activate pointer", action: #selector(activate), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open config file", action: #selector(openConfig), keyEquivalent: "")
        menu.addItem(withTitle: "Reload config", action: #selector(reloadConfig), keyEquivalent: "")
        menu.addItem(withTitle: "Show config error", action: #selector(showConfigError), keyEquivalent: "")
        menu.addItem(withTitle: "Open example config", action: #selector(openExample), keyEquivalent: "")
        menu.addItem(withTitle: "Open manual", action: #selector(openManual), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit vimouse", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    @objc private func activate() { controller.activateFromMenu() }
    @objc private func openConfig() { NSWorkspace.shared.open(ConfigStore.file) }
    @objc private func reloadConfig() { configStore.reload() }
    @objc private func openExample() { NSWorkspace.shared.open(ConfigStore.exampleFile) }

    /// `man` in a Terminal window; falls back to opening the file if Terminal cannot be scripted.
    @objc private func openManual() {
        let script = "tell application \"Terminal\"\nactivate\ndo script \"man '\(ConfigStore.manualFile.path)'\"\nend tell"
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if error != nil { NSWorkspace.shared.open(ConfigStore.manualFile) }
    }

    @objc private func showConfigError() {
        let alert = NSAlert()
        alert.messageText = configStore.lastError == nil ? "Config is fine" : "Config error"
        alert.informativeText = configStore.lastError ?? "\(ConfigStore.file.path) parsed without errors."
        alert.runModal()
    }
    @objc private func quit() { NSApp.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }
}
#endif
