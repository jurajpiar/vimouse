import Foundation

/// One setting in config.toml. The schema is the single source of truth: the default
/// file is generated from it, and `migrate` brings an older file up to date.
public struct ConfigEntry: Equatable {
    public let section: String
    public let key: String
    /// TOML literal, e.g. `"i"`, `["backspace", "u"]`, `60`, `true`.
    public let defaultValue: String
    /// One line, shown above the key. Mention example values.
    public let comment: String
}

public enum ConfigSchema {
    public static let changelog = "CHANGELOG.md in the vimouse repository"

    public static let header = """
    # vimouse configuration. Edit and save; the app reloads within a second.
    #
    # Key names (US layout positions): letters a-z, digits 0-9, space, return, tab,
    # escape, backspace, left, right, up, down, pageup, pagedown, home, end, comma,
    # period, slash, leftbracket, rightbracket, minus, equal.
    # Modifiers cmd, shift, ctrl, alt are joined with "+", e.g. "cmd+shift+space".
    # A list binds several keys to one action, e.g. ["j", "down"].
    #
    # On start, settings missing from this file are appended with their defaults, and
    # unknown or superseded settings are commented out (see \(changelog)).
    """

    public static let entries: [ConfigEntry] = [
        .init(section: "hotkey", key: "activate", defaultValue: "\"cmd+shift+space\"", comment: "Global hotkey that enters Pointer mode, e.g. \"cmd+shift+space\", \"ctrl+alt+m\"."),

        .init(section: "keys", key: "top_left", defaultValue: "\"i\"", comment: "Pick the top-left quadrant, e.g. \"i\", \"up\"."),
        .init(section: "keys", key: "top_right", defaultValue: "\"o\"", comment: "Pick the top-right quadrant, e.g. \"o\", \"right\"."),
        .init(section: "keys", key: "bottom_left", defaultValue: "\"j\"", comment: "Pick the bottom-left quadrant, e.g. \"j\", \"left\"."),
        .init(section: "keys", key: "bottom_right", defaultValue: "\"k\"", comment: "Pick the bottom-right quadrant, e.g. \"k\", \"down\"."),
        .init(section: "keys", key: "up", defaultValue: "[\"backspace\", \"u\"]", comment: "Go up one level in the quadrant descent; a count repeats, e.g. [\"backspace\", \"u\"]."),
        .init(section: "keys", key: "left_click", defaultValue: "[\"return\", \"m\"]", comment: "Left-click and exit; a count sets the click count (3 = triple), modifiers held pass through."),
        .init(section: "keys", key: "click_stay", defaultValue: "\"space\"", comment: "Left-click and stay in Pointer mode, e.g. \"space\"."),
        .init(section: "keys", key: "double_click", defaultValue: "\"x\"", comment: "Double-click and exit, e.g. \"x\"."),
        .init(section: "keys", key: "right_click", defaultValue: "\"period\"", comment: "Right-click (context menu) and exit, e.g. \"period\", \"ctrl+return\"."),
        .init(section: "keys", key: "middle_click", defaultValue: "\"comma\"", comment: "Middle-click and exit, e.g. \"comma\"."),
        .init(section: "keys", key: "drag", defaultValue: "\"v\"", comment: "Press the left button; navigate; press again to release (drag or text selection), e.g. \"v\"."),
        .init(section: "keys", key: "exit", defaultValue: "\"escape\"", comment: "Leave Pointer mode (releases a drag; keeps a ruler), e.g. \"escape\", \"ctrl+c\"."),
        .init(section: "keys", key: "next_screen", defaultValue: "\"tab\"", comment: "Next display; with a count, that display (2 then tab = display 2), e.g. \"tab\"."),
        .init(section: "keys", key: "previous_screen", defaultValue: "\"shift+tab\"", comment: "Previous display, e.g. \"shift+tab\"."),
        .init(section: "keys", key: "snap_toggle", defaultValue: "\"a\"", comment: "Toggle snapping to UI elements for this session, e.g. \"a\"."),
        .init(section: "keys", key: "scroll_toggle", defaultValue: "\"s\"", comment: "Enter or leave Scroll mode, e.g. \"s\"."),
        .init(section: "keys", key: "ruler_toggle", defaultValue: "\"r\"", comment: "Create the reading band / enter or leave Ruler mode, e.g. \"r\"."),
        .init(section: "keys", key: "ruler_remove", defaultValue: "\"shift+r\"", comment: "Remove the reading band, e.g. \"shift+r\"."),

        .init(section: "scroll", key: "step", defaultValue: "60", comment: "Pixels scrolled per press; a count multiplies (45j). Try 20 for line-by-line reading, 60 to 120 for browsing."),
        .init(section: "scroll", key: "down", defaultValue: "\"j\"", comment: "Scroll down, e.g. \"j\", \"down\", [\"j\", \"down\"]."),
        .init(section: "scroll", key: "up", defaultValue: "\"k\"", comment: "Scroll up, e.g. \"k\", \"up\"."),
        .init(section: "scroll", key: "left", defaultValue: "\"h\"", comment: "Scroll left, e.g. \"h\", \"left\"."),
        .init(section: "scroll", key: "right", defaultValue: "\"l\"", comment: "Scroll right, e.g. \"l\", \"right\"."),
        .init(section: "scroll", key: "half_page_down", defaultValue: "\"d\"", comment: "Scroll half a screen down, e.g. \"d\", \"pagedown\"."),
        .init(section: "scroll", key: "half_page_up", defaultValue: "\"u\"", comment: "Scroll half a screen up, e.g. \"u\", \"pageup\"."),

        .init(section: "ruler", key: "height", defaultValue: "32", comment: "Band height in pixels when created; 20 to 40 covers one or two text lines."),
        .init(section: "ruler", key: "step", defaultValue: "20", comment: "Pixels the band moves per press; a count multiplies. Match your line height, 18 to 24 is typical."),
        .init(section: "ruler", key: "height_step", defaultValue: "4", comment: "Pixels added or removed from the band height per press, e.g. 2, 4, 8."),
        .init(section: "ruler", key: "dim", defaultValue: "0.35", comment: "Darkening outside the band, 0 (none) to 1 (black); 0.2 subtle, 0.35 default, 0.6 strong."),
        .init(section: "ruler", key: "down", defaultValue: "\"j\"", comment: "Move the band down, e.g. \"j\", \"down\"."),
        .init(section: "ruler", key: "up", defaultValue: "\"k\"", comment: "Move the band up, e.g. \"k\", \"up\"."),
        .init(section: "ruler", key: "grow", defaultValue: "\"rightbracket\"", comment: "Make the band taller, e.g. \"rightbracket\", \"equal\"."),
        .init(section: "ruler", key: "shrink", defaultValue: "\"leftbracket\"", comment: "Make the band shorter, e.g. \"leftbracket\", \"minus\"."),

        .init(section: "snap", key: "enabled", defaultValue: "true", comment: "Snap the pointer to the nearest clickable element in the chosen rectangle: true or false."),
    ]

    /// Settings that no longer exist, with a note for the user. Keyed by "section.key".
    public static let superseded: [String: String] = [:]

    public static var sections: [String] {
        var seen: [String] = []
        for e in entries where !seen.contains(e.section) { seen.append(e.section) }
        return seen
    }

    /// The complete default file.
    public static func template() -> String {
        var out = header + "\n"
        for section in sections {
            out += "\n[\(section)]\n"
            for e in entries where e.section == section {
                out += "# \(e.comment)\n\(e.key) = \(e.defaultValue)\n"
            }
        }
        return out
    }

    /// Adds missing settings with their defaults (and comments) and comments out
    /// unknown or superseded ones. Returns the new text and whether anything changed.
    /// Line based, so the user's own comments and ordering are preserved.
    public static func migrate(_ text: String) -> (text: String, changed: Bool) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return (template(), true) }
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        var changed = false

        // Pass 1: find sections, their line ranges, and the keys they contain.
        struct SectionInfo { var start: Int; var end: Int; var keys: Set<String> }
        var sections: [String: SectionInfo] = [:]
        var current: String? = nil
        for (i, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") && line.hasSuffix("]") {
                let name = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                current = name
                sections[name] = SectionInfo(start: i, end: i, keys: [])
                continue
            }
            guard let sec = current, sections[sec] != nil else { continue }
            if !line.isEmpty { sections[sec]!.end = i }
            guard !line.isEmpty, !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            sections[sec]!.keys.insert(key)
            let known = entries.contains { $0.section == sec && $0.key == key }
            if !known {
                let note = superseded["\(sec).\(key)"] ?? "unknown setting"
                lines[i] = "# \(note), ignored (see \(changelog)): \(raw)"
                changed = true
            }
        }

        // Pass 2: append missing keys per known section, and missing sections. Insert
        // from the bottom up so earlier indices stay valid.
        var insertions: [(after: Int, text: [String])] = []
        var appendix: [String] = []
        for section in self.sections {
            let missing = entries.filter { $0.section == section && !(sections[section]?.keys.contains($0.key) ?? false) }
            guard !missing.isEmpty else { continue }
            let block = missing.flatMap { ["# \($0.comment)", "\($0.key) = \($0.defaultValue)"] }
            if let info = sections[section] {
                insertions.append((after: info.end, text: block))
            } else {
                appendix += ["", "[\(section)]"] + block
            }
            changed = true
        }
        for ins in insertions.sorted(by: { $0.after > $1.after }) {
            lines.insert(contentsOf: ins.text, at: ins.after + 1)
        }
        lines += appendix
        return (lines.joined(separator: "\n") + "\n", changed)
    }
}
