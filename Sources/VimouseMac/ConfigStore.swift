#if canImport(AppKit)
import AppKit
import VimouseCore

/// Loads ~/.config/vimouse/config.toml, writes the commented default on first run,
/// and reloads when the file changes (editors save by replacing the file, so the
/// directory is watched rather than the file).
final class ConfigStore {
    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/vimouse", isDirectory: true)
    static let file = directory.appendingPathComponent("config.toml")

    private(set) var config = Config()
    /// Last load error, shown in the menu bar; nil when the file parsed.
    private(set) var lastError: String?
    var onChange: ((Config) -> Void)?

    private var source: DispatchSourceFileSystemObject?
    private var lastModified: Date?

    func start() {
        ensureFile()
        load()
        watch()
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
        let fd = open(ConfigStore.directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in self?.directoryChanged() }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    private func directoryChanged() {
        // Only reload when the config file itself changed (directory events fire for any entry).
        let attrs = try? FileManager.default.attributesOfItem(atPath: ConfigStore.file.path)
        let modified = attrs?[.modificationDate] as? Date
        guard modified != lastModified else { return }
        lastModified = modified
        // Editors write in steps; give them a moment to finish.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.load() }
    }
}
#endif
