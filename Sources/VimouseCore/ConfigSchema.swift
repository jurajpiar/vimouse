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
    # On start (unless [config] update = false) settings missing from this file are
    # appended with their defaults and unknown or superseded ones are moved to a
    # "Retired settings" block at the end. config.example.toml next to this file is
    # always rewritten with the current defaults, and vimouse.1 is the manual:
    #   man ~/.config/vimouse/vimouse.1
    """

    /// One line above each section header.
    public static let sectionComments: [String: String] = [
        "config": "How this file itself is maintained.",
        "hotkey": "How Pointer mode is entered.",
        "global": "Bindings that work in every mode: leaving, help, switching displays.",
        "actions": "Clicking and dragging, available in every mode.",
        "pointer": "Pointer mode: narrowing down on the target by picking quadrants.",
        "scroll": "Scroll mode: scrolling the content under the pointer with the keyboard.",
        "ruler": "Ruler mode: the reading band that dims everything except the line being read.",
        "nudge": "Nudge mode: moving the pointer by a few pixels at a time for the final adjustment.",
        "drag": "Dragging: holding the left button while navigating, for text selection and drag-and-drop.",
        "colours.modes": "Overlay colour of each mode (its rectangles, ring and status strip), as \"#RRGGBB\".",
        "colours.markers": "Overlay colours of markers that appear in any mode, as \"#RRGGBB\".",
        "snap": "Snapping the pointer to clickable UI elements read from the accessibility tree.",
    ]

    public static let entries: [ConfigEntry] = [
        .init(section: "config", key: "update", defaultValue: "true", comment: "On start, add new settings to this file and retire old ones in place (true), or leave this file alone and only refresh config.example.toml (false)."),

        .init(section: "hotkey", key: "activate", defaultValue: "\"cmd+shift+space\"", comment: "Global hotkey that enters Pointer mode, e.g. \"cmd+shift+space\", \"ctrl+alt+m\"."),
        .init(section: "hotkey", key: "hold", defaultValue: "\"\"", comment: "Quasi-mode: a modifier key that enters Pointer mode while held and leaves it on release; its own modifier is ignored on the keys you type meanwhile. One of left_cmd, right_cmd, left_alt, right_alt, left_ctrl, right_ctrl, left_shift, right_shift, fn, or \"\" for none."),

        .init(section: "global", key: "exit", defaultValue: "\"escape\"", comment: "Leave Pointer mode (releases a drag; keeps a ruler), e.g. \"escape\", \"ctrl+c\"."),
        .init(section: "global", key: "next_screen", defaultValue: "\"tab\"", comment: "Next display; with a count, that display (2 then tab = display 2), e.g. \"tab\"."),
        .init(section: "global", key: "previous_screen", defaultValue: "\"shift+tab\"", comment: "Previous display, e.g. \"shift+tab\"."),
        .init(section: "global", key: "help", defaultValue: "\"shift+slash\"", comment: "Hold to show every binding of the current mode; release to hide, e.g. \"shift+slash\" (the ? key)."),

        .init(section: "actions", key: "left_click", defaultValue: "[\"return\", \"m\"]", comment: "Left-click and exit; a count sets the click count (3 = triple), modifiers held pass through."),
        .init(section: "actions", key: "click_stay", defaultValue: "\"space\"", comment: "Left-click and stay in Pointer mode, e.g. \"space\"."),
        .init(section: "actions", key: "double_click", defaultValue: "\"x\"", comment: "Double-click and exit, e.g. \"x\"."),
        .init(section: "actions", key: "right_click", defaultValue: "\"period\"", comment: "Right-click (context menu) and exit, e.g. \"period\", \"ctrl+return\"."),
        .init(section: "actions", key: "middle_click", defaultValue: "\"comma\"", comment: "Middle-click and exit, e.g. \"comma\"."),
        .init(section: "actions", key: "drag", defaultValue: "\"v\"", comment: "Press the left button; navigate; press again to release (drag or text selection), e.g. \"v\"."),

        .init(section: "pointer", key: "top_left", defaultValue: "\"i\"", comment: "Pick the top-left quadrant, e.g. \"i\", \"up\"."),
        .init(section: "pointer", key: "top_right", defaultValue: "\"o\"", comment: "Pick the top-right quadrant, e.g. \"o\", \"right\"."),
        .init(section: "pointer", key: "bottom_left", defaultValue: "\"j\"", comment: "Pick the bottom-left quadrant, e.g. \"j\", \"left\"."),
        .init(section: "pointer", key: "bottom_right", defaultValue: "\"k\"", comment: "Pick the bottom-right quadrant, e.g. \"k\", \"down\"."),
        .init(section: "pointer", key: "up", defaultValue: "[\"backspace\", \"u\"]", comment: "Go up one level in the quadrant descent; a count repeats, e.g. [\"backspace\", \"u\"]."),
        .init(section: "pointer", key: "top", defaultValue: "[\"shift+u\", \"shift+backspace\"]", comment: "Restart the quadrant search from the whole screen, e.g. [\"shift+u\", \"shift+backspace\"]."),
        .init(section: "pointer", key: "snap_toggle", defaultValue: "\"a\"", comment: "Toggle snapping to UI elements for this session, e.g. \"a\"."),

        .init(section: "nudge", key: "step", defaultValue: "5", comment: "Pixels the pointer moves per press; Shift held moves one pixel; a count multiplies, e.g. 5, 10."),
        .init(section: "nudge", key: "toggle", defaultValue: "\"n\"", comment: "Enter or leave Nudge mode from Pointer mode, e.g. \"n\"."),
        .init(section: "nudge", key: "left", defaultValue: "[\"h\", \"left\"]", comment: "Move the pointer left, e.g. [\"h\", \"left\"]."),
        .init(section: "nudge", key: "right", defaultValue: "[\"l\", \"right\"]", comment: "Move the pointer right, e.g. [\"l\", \"right\"]."),
        .init(section: "nudge", key: "up", defaultValue: "[\"k\", \"up\"]", comment: "Move the pointer up, e.g. [\"k\", \"up\"]."),
        .init(section: "nudge", key: "down", defaultValue: "[\"j\", \"down\"]", comment: "Move the pointer down, e.g. [\"j\", \"down\"]."),

        .init(section: "scroll", key: "toggle", defaultValue: "\"s\"", comment: "Enter or leave Scroll mode, e.g. \"s\"."),
        .init(section: "scroll", key: "step", defaultValue: "60", comment: "Pixels scrolled per press; a count multiplies (45j). Try 20 for line-by-line reading, 60 to 120 for browsing."),
        .init(section: "scroll", key: "down", defaultValue: "\"j\"", comment: "Scroll down, e.g. \"j\", \"down\", [\"j\", \"down\"]."),
        .init(section: "scroll", key: "up", defaultValue: "\"k\"", comment: "Scroll up, e.g. \"k\", \"up\"."),
        .init(section: "scroll", key: "left", defaultValue: "\"h\"", comment: "Scroll left, e.g. \"h\", \"left\"."),
        .init(section: "scroll", key: "right", defaultValue: "\"l\"", comment: "Scroll right, e.g. \"l\", \"right\"."),
        .init(section: "scroll", key: "half_page_down", defaultValue: "\"d\"", comment: "Scroll half a screen down, e.g. \"d\", \"pagedown\"."),
        .init(section: "scroll", key: "half_page_up", defaultValue: "\"u\"", comment: "Scroll half a screen up, e.g. \"u\", \"pageup\"."),

        .init(section: "ruler", key: "toggle", defaultValue: "\"r\"", comment: "Create the reading band / enter or leave Ruler mode, e.g. \"r\"."),
        .init(section: "ruler", key: "remove", defaultValue: "\"shift+r\"", comment: "Remove the reading band, e.g. \"shift+r\"."),
        .init(section: "ruler", key: "height", defaultValue: "32", comment: "Band height in pixels when created; 20 to 40 covers one or two text lines."),
        .init(section: "ruler", key: "move", defaultValue: "0", comment: "How far the band moves per press: 0 = its own height (one line when sized to a line), otherwise pixels, e.g. 20. A count multiplies."),
        .init(section: "ruler", key: "fine", defaultValue: "1", comment: "Pixels the band moves or resizes per press while Shift is held (micro-adjustment), e.g. 1, 2."),
        .init(section: "ruler", key: "height_step", defaultValue: "4", comment: "Pixels added or removed from the band height per press, e.g. 2, 4, 8."),
        .init(section: "ruler", key: "dim", defaultValue: "0.35", comment: "Darkening outside the band, 0 (none) to 1 (black); 0.2 subtle, 0.35 default, 0.6 strong."),
        .init(section: "ruler", key: "down", defaultValue: "\"j\"", comment: "Move the band down, e.g. \"j\", \"down\"."),
        .init(section: "ruler", key: "up", defaultValue: "\"k\"", comment: "Move the band up, e.g. \"k\", \"up\"."),
        .init(section: "ruler", key: "grow", defaultValue: "\"rightbracket\"", comment: "Make the band taller, e.g. \"rightbracket\", \"equal\"."),
        .init(section: "ruler", key: "shrink", defaultValue: "\"leftbracket\"", comment: "Make the band shorter, e.g. \"leftbracket\", \"minus\"."),

        .init(section: "drag", key: "restart_search", defaultValue: "true", comment: "When a drag starts, restart the quadrant search from the whole screen (good for moving items far; set false to keep extending a selection from where you are): true or false."),
        .init(section: "drag", key: "ramp", defaultValue: "false", comment: "After pressing the button, wiggle the pointer a few pixels so apps that need movement before starting a drag-and-drop session do so. Breaks text drags in Chromium-based apps, so off unless an app needs it: true or false."),

        .init(section: "colours.modes", key: "pointer", defaultValue: "\"#0A84FF\"", comment: "Pointer mode."),
        .init(section: "colours.modes", key: "nudge", defaultValue: "\"#40C8E0\"", comment: "Nudge mode."),
        .init(section: "colours.modes", key: "scroll", defaultValue: "\"#FF9F0A\"", comment: "Scroll mode."),
        .init(section: "colours.modes", key: "ruler", defaultValue: "\"#BF5AF2\"", comment: "Ruler mode and the band edges."),

        .init(section: "colours.markers", key: "drag", defaultValue: "\"#30D158\"", comment: "Drag badge, origin dot and line."),
        .init(section: "colours.markers", key: "snap", defaultValue: "\"#FF375F\"", comment: "Ring marking the snap target."),

        .init(section: "snap", key: "enabled", defaultValue: "true", comment: "Snap the pointer to the nearest clickable element in the chosen rectangle: true or false."),
    ]

    /// Settings that no longer exist, with a note for the user. Keyed by "section.key".
    public static let superseded: [String: String] = [
        "ruler.step": "superseded by `move` (0 = the band's own height)",
    ]

    /// Settings that moved: old "section.key" -> new "section.key". The user's value moves with it.
    public static let renamed: [String: String] = [
        "keys.top_left": "pointer.top_left", "keys.top_right": "pointer.top_right",
        "keys.bottom_left": "pointer.bottom_left", "keys.bottom_right": "pointer.bottom_right",
        "keys.up": "pointer.up", "keys.top": "pointer.top", "keys.snap_toggle": "pointer.snap_toggle",
        "keys.left_click": "actions.left_click", "keys.click_stay": "actions.click_stay",
        "keys.double_click": "actions.double_click", "keys.right_click": "actions.right_click",
        "keys.middle_click": "actions.middle_click", "keys.drag": "actions.drag",
        "keys.exit": "global.exit", "keys.next_screen": "global.next_screen",
        "keys.previous_screen": "global.previous_screen", "keys.help": "global.help",
        "keys.scroll_toggle": "scroll.toggle", "keys.ruler_toggle": "ruler.toggle", "keys.ruler_remove": "ruler.remove",
        "colours.pointer": "colours.modes.pointer", "colours.nudge": "colours.modes.nudge",
        "colours.scroll": "colours.modes.scroll", "colours.ruler": "colours.modes.ruler",
        "colours.drag": "colours.markers.drag", "colours.snap": "colours.markers.snap",
    ]

    /// Splits "section.sub.key" into its section ("section.sub") and key ("key").
    public static func split(_ path: String) -> (section: String, key: String) {
        guard let dot = path.lastIndex(of: ".") else { return ("", path) }
        return (String(path[..<dot]), String(path[path.index(after: dot)...]))
    }

    public static var sections: [String] {
        var seen: [String] = []
        for e in entries where !seen.contains(e.section) { seen.append(e.section) }
        return seen
    }

    /// Short comments go on the key's line, longer ones above it.
    public static let inlineCommentLimit = 48

    /// One setting as written to the file: the key with the comment on the same line
    /// when it is short, otherwise a blank line, the comment line, then the key, so the
    /// comment reads as belonging to what follows.
    public static func render(_ e: ConfigEntry, value: String? = nil) -> [String] {
        let v = value ?? e.defaultValue
        if e.comment.count <= inlineCommentLimit {
            return ["\(e.key) = \(v)   # \(e.comment)"]
        }
        return ["", "# \(e.comment)", "\(e.key) = \(v)"]
    }

    /// The complete default file.
    public static func template() -> String {
        var out = header + "\n"
        for section in sections {
            out += "\n# \(sectionComments[section] ?? section)\n[\(section)]\n"
            for e in entries where e.section == section {
                out += render(e).joined(separator: "\n") + "\n"
            }
        }
        return out
    }

    static let retiredHeader = "# Retired settings (see \(changelog)):"

    /// Brings a file up to date: adds missing settings with their defaults and comments
    /// (and descriptions for known sections and keys that lack them), moves renamed
    /// settings silently with their values, and gathers superseded or unknown settings
    /// into one block at the end. Line based, so the user's own comments and ordering
    /// are preserved. Returns the new text and whether anything changed.
    public static func migrate(_ text: String) -> (text: String, changed: Bool) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return (template(), true) }
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        var changed = false

        // Pass 0: notes written by earlier versions inline ("# moved to ...: x = 1",
        // "# ..., ignored (see ...): x = 1") and an existing retired block.
        var retired: [String] = []
        var cleaned: [String] = []
        var inRetired = false
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line == retiredHeader { inRetired = true; continue }
            if inRetired {
                if line.hasPrefix("#"), line.count > 1 {
                    retired.append(String(line.dropFirst()).trimmingCharacters(in: .whitespaces))
                    continue
                }
                inRetired = false
                if line.isEmpty { continue }
            }
            if line.hasPrefix("# moved to ["), line.contains("): ") {
                continue // the value already lives at its new place
            }
            if line.hasPrefix("#"), line.contains("ignored (see "), let r = line.range(of: "): ") {
                retired.append(String(line[r.upperBound...]))
                changed = true
                continue
            }
            cleaned.append(raw)
        }
        lines = cleaned

        // Pass 1: sections, their line ranges and keys. Known sections and keys without
        // their description directly above get it. Renamed keys are removed and their
        // values carried; superseded and unknown keys are retired.
        struct SectionInfo { var start: Int; var end: Int; var keys: Set<String>; var keyLines: Int }
        var sections: [String: SectionInfo] = [:]
        var current: String? = nil
        var commentsToInsert: [(before: Int, text: [String])] = []
        var removals = Set<Int>()
        var carried: [String: String] = [:]
        func hasComment(_ comment: String, above i: Int) -> Bool {
            var j = i - 1
            while j >= 0 {
                let l = lines[j].trimmingCharacters(in: .whitespaces)
                guard l.hasPrefix("#") else { return false }
                if l == comment { return true }
                j -= 1
            }
            return false
        }
        for (i, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") && line.hasSuffix("]") {
                let name = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                current = name
                sections[name] = SectionInfo(start: i, end: i, keys: [], keyLines: 0)
                if let c = sectionComments[name], !hasComment("# \(c)", above: i) {
                    commentsToInsert.append((before: i, text: ["# \(c)"]))
                }
                continue
            }
            guard let sec = current, sections[sec] != nil else { continue }
            if !line.isEmpty { sections[sec]!.end = i }
            guard !line.isEmpty, !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let value = TOML.stripComment(String(line[line.index(after: eq)...])).trimmingCharacters(in: .whitespaces)
            if let entry = entries.first(where: { $0.section == sec && $0.key == key }) {
                sections[sec]!.keys.insert(key)
                sections[sec]!.keyLines += 1
                let documented = hasComment("# \(entry.comment)", above: i) || line.hasSuffix("# \(entry.comment)")
                if !documented {
                    if entry.comment.count <= inlineCommentLimit {
                        lines[i] = "\(raw)   # \(entry.comment)"
                    } else {
                        // Blank line first unless the key already follows a blank line or the header.
                        let prev = i > 0 ? lines[i - 1].trimmingCharacters(in: .whitespaces) : ""
                        let separated = prev.isEmpty || prev.hasPrefix("[") || prev.hasPrefix("#")
                        commentsToInsert.append((before: i, text: (separated ? [] : [""]) + ["# \(entry.comment)"]))
                    }
                }
            } else if let target = renamed["\(sec).\(key)"] {
                carried[target] = value
                removals.insert(i)
                changed = true
            } else {
                retired.append("[\(sec)] \(key) = \(value)")
                removals.insert(i)
                changed = true
            }
        }

        // Pass 2: blocks of missing keys per known section (carried values first), and
        // missing sections.
        var insertions: [(after: Int, text: [String])] = []
        var appendix: [String] = []
        for section in self.sections {
            let missing = entries.filter { $0.section == section && !(sections[section]?.keys.contains($0.key) ?? false) }
            guard !missing.isEmpty else { continue }
            let block = missing.flatMap { render($0, value: carried["\($0.section).\($0.key)"]) }
            if let info = sections[section] {
                insertions.append((after: info.end, text: block))
            } else {
                appendix += ["", "# \(sectionComments[section] ?? section)", "[\(section)]"] + block
            }
            changed = true
        }

        // Unknown sections left without any key (for example a former [keys]) go away,
        // header and all, together with the comments directly above them.
        for (name, info) in sections where sectionComments[name] == nil && !entries.contains(where: { $0.section == name }) {
            let remaining = (info.start...info.end).filter { i in
                let l = lines[i].trimmingCharacters(in: .whitespaces)
                return !l.isEmpty && !l.hasPrefix("#") && !l.hasPrefix("[") && !removals.contains(i)
            }
            guard remaining.isEmpty else { continue }
            for i in info.start...info.end { removals.insert(i) }
            var j = info.start - 1
            while j >= 0, lines[j].trimmingCharacters(in: .whitespaces).hasPrefix("#") { removals.insert(j); j -= 1 }
            changed = true
        }

        // Apply every insert bottom up so earlier indices stay valid. A comment goes at
        // `before`; a block of new keys goes at `after + 1`. At the same position the
        // comment (which belongs to the line after it) is inserted first, so the block,
        // which belongs to the section before, ends up above it. Removals are marked
        // first so their indices are not shifted.
        for i in removals { lines[i] = "\u{0}" }
        var inserts: [(at: Int, isComment: Bool, text: [String])] =
            commentsToInsert.map { (at: $0.before, isComment: true, text: $0.text) }
            + insertions.map { (at: $0.after + 1, isComment: false, text: $0.text) }
        inserts.sort { a, b in a.at != b.at ? a.at > b.at : (a.isComment && !b.isComment) }
        for ins in inserts {
            lines.insert(contentsOf: ins.text, at: ins.at)
            changed = true
        }
        lines.removeAll { $0 == "\u{0}" }
        lines += appendix

        // Retired block, deduplicated, at the very end.
        var seen = Set<String>()
        let retiredUnique = retired.filter { seen.insert($0).inserted }
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
        if !retiredUnique.isEmpty {
            lines += ["", retiredHeader] + retiredUnique.map { "# \($0)" }
        }
        // "Changed" means the text differs; the flags above only steer the passes.
        _ = changed
        let result = lines.joined(separator: "\n") + "\n"
        return (result, result != text)
    }
}
