#if canImport(AppKit)
import AppKit
import VimouseCore

/// Loads ~/.config/vimouse/config.toml, writes the commented default on first run,
/// and reloads when the file changes. Change detection polls the modification time
/// once a second: a vnode watch on the file misses atomic saves (the editor replaces
/// the file) and one on the directory misses in-place writes, so polling is the
/// simple option that covers both.
final class ConfigStore {
    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/vimouse", isDirectory: true)
    static let file = directory.appendingPathComponent("config.toml")
    static let exampleFile = directory.appendingPathComponent("config.example.toml")
    static let manualFile = directory.appendingPathComponent("vimouse.1")

    private(set) var config = Config()
    /// Last load error, shown in the menu bar; nil when the file parsed.
    private(set) var lastError: String?
    var onChange: ((Config) -> Void)?

    private var timer: Timer?
    private var lastModified: Date?

    func start() {
        ensureFile()
        writeReference()
        if updateAllowed() { migrate() }
        load()
        watch()
    }

    /// The example config and the manual, always current. Overwritten on every start.
    private func writeReference() {
        do {
            try Config.defaultTOML.write(to: ConfigStore.exampleFile, atomically: true, encoding: .utf8)
            try Manual.roff().write(to: ConfigStore.manualFile, atomically: true, encoding: .utf8)
        } catch {
            NSLog("vimouse: could not write reference files: \(error)")
        }
    }

    /// [config] update, read on its own so a file that fails to parse elsewhere can still say no.
    private func updateAllowed() -> Bool {
        guard let text = try? String(contentsOf: ConfigStore.file, encoding: .utf8),
              let table = try? TOML.parse(text) else { return true }
        return table["config"]?["update"]?.bool ?? true
    }

    /// Append settings added since the file was written; retire ones that went away.
    private func migrate() {
        guard let text = try? String(contentsOf: ConfigStore.file, encoding: .utf8) else { return }
        let (updated, changed) = ConfigSchema.migrate(text)
        guard changed else { return }
        do {
            try updated.write(to: ConfigStore.file, atomically: true, encoding: .utf8)
            NSLog("vimouse: config updated with new settings")
        } catch {
            NSLog("vimouse: could not update config: \(error)")
        }
    }

    func reload() { load() }

    private func ensureFile() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: ConfigStore.file.path) else { return }
        do {
            try fm.createDirectory(at: ConfigStore.directory, withIntermediateDirectories: true)
            try Config.defaultTOML.write(to: ConfigStore.file, atomically: true, encoding: .utf8)
            NSLog("vimouse: wrote default config to \(ConfigStore.file.path)")
        } catch {
            NSLog("vimouse: could not write default config: \(error)")
        }
    }

    private func load() {
        lastModified = modificationDate()
        do {
            let text = try String(contentsOf: ConfigStore.file, encoding: .utf8)
            config = try Config.parse(text)
            lastError = nil
            NSLog("vimouse: config loaded")
        } catch {
            lastError = "\(error)"
            NSLog("vimouse: config error: \(error) (keeping previous settings)")
        }
        onChange?(config)
    }

    private func watch() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.modificationDate() != self.lastModified else { return }
            self.load()
        }
    }

    private func modificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: ConfigStore.file.path))?[.modificationDate] as? Date
    }
}
#endif
