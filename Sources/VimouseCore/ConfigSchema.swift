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

    public init(section: String, key: String, defaultValue: String, comment: String) {
        self.section = section
        self.key = key
        self.defaultValue = defaultValue
        self.comment = comment
    }
}

/// The file layout for a given set of modes: the shared sections, then one section per
/// mode (in registration order), then dragging and colours.
public struct ConfigSchema {
    public static let changelog = "CHANGELOG.md in the vimouse repository"

    public static let header = """
    # vimouse configuration. Edit and save; the app reloads within a second.
    #
    # Key names (US layout positions): letters a-z, digits 0-9, space, return, tab,
    # escape, backspace, left, right, up, down, pageup, pagedown, home, end, comma,
    # period, slash, leftbracket, rightbracket, minus, equal.
    # Modifiers cmd, shift, ctrl, alt are joined with "+", e.g. "cmd+shift+space"; a
    # side can be named: left_shift, right_cmd, right_alt, left_ctrl (plain names match
    # either side).
    # A list binds several keys to one action, e.g. ["j", "down"].
    #
    # On start (unless [config] update = false) settings missing from this file are
    # appended with their defaults and unknown or superseded ones are moved to a
    # "Retired settings" block at the end. config.example.toml next to this file is
    # always rewritten with the current defaults, and vimouse.1 is the manual:
    #   man ~/.config/vimouse/vimouse.1
    """

    public let modes: [Mode]
    public let cursors: [CursorStyle]
    /// One line above each section header.
    public let sectionComments: [String: String]
    public let entries: [ConfigEntry]

    public init(modes: [Mode], cursors: [CursorStyle] = []) {
        self.modes = modes
        self.cursors = cursors
        let ids = modes.map(\.id)
        let list = ids.joined(separator: ", ")
        let first = ids.first ?? "pointer"
        var comments: [String: String] = [
            "config": "How this file itself is maintained.",
            "hotkey": "How a mode is entered.",
            "modes": "Which modes are available. Each mode has its own section below.",
            "global": "Bindings that work in every mode: leaving, help, switching displays.",
            "actions": "Clicking and dragging, available in every mode.",
            "drag": "Dragging: holding the left button while navigating, for text selection and drag-and-drop.",
            "cursor": "The marker drawn at the pointer while a mode is active.",
            "colours.modes": "Overlay colour of each mode (its drawings and status strip), as \"#RRGGBB\".",
            "colours.markers": "Overlay colours of markers that appear in any mode, as \"#RRGGBB\".",
        ]
        for m in modes { comments[m.id] = m.summary }
        sectionComments = comments

        var e: [ConfigEntry] = [
            .init(section: "config", key: "update", defaultValue: "true", comment: "On start, add new settings to this file and retire old ones in place (true), or leave this file alone and only refresh config.example.toml (false)."),

            .init(section: "hotkey", key: "activate", defaultValue: "\"cmd+shift+space\"", comment: "Global hotkey that enters a mode, e.g. \"cmd+shift+space\", \"ctrl+alt+m\"."),
            .init(section: "hotkey", key: "activate_mode", defaultValue: "\"\(first)\"", comment: "Mode the hotkey starts in: \(list)."),
            .init(section: "hotkey", key: "hold", defaultValue: "\"\"", comment: "Quasi-mode: the mode is active while this is held and left on release; these modifiers are ignored on the keys you type meanwhile, unless you also press the key on the other side (a left-hand hyper plus right shift still shifts). A chord like \"cmd+ctrl+alt\" or \"cmd+ctrl+alt+shift\", one key such as right_cmd, left_alt, right_ctrl, fn, or \"\" for none. The activate hotkey pins a held activation."),
            .init(section: "hotkey", key: "hold_mode", defaultValue: "\"\(first)\"", comment: "Mode the hold key starts in: \(list)."),

            .init(section: "modes", key: "enabled", defaultValue: "[" + modes.filter(\.enabledByDefault).map { "\"\($0.id)\"" }.joined(separator: ", ") + "]", comment: "Modes that can be entered, in order; the first is the default that mode toggles return to. Available: \(list)."),

            .init(section: "global", key: "exit", defaultValue: "\"escape\"", comment: "Leave the active mode (releases a drag; keeps a ruler), e.g. \"escape\", \"ctrl+c\"."),
            .init(section: "global", key: "next_screen", defaultValue: "\"tab\"", comment: "Next display; with a count, that display (2 then tab = display 2), e.g. \"tab\"."),
            .init(section: "global", key: "previous_screen", defaultValue: "\"shift+tab\"", comment: "Previous display, e.g. \"shift+tab\"."),
            .init(section: "global", key: "help", defaultValue: "\"shift+slash\"", comment: "Hold to show every binding of the current mode; release to hide, e.g. \"shift+slash\" (the ? key)."),
            .init(section: "global", key: "passthrough", defaultValue: "[\"cmd+tab\", \"cmd+shift+tab\", \"cmd+space\", \"ctrl+up\", \"ctrl+down\", \"ctrl+left\", \"ctrl+right\", \"cmd+shift+3\", \"cmd+shift+4\", \"cmd+shift+5\"]", comment: "System shortcuts that still work while a mode is active (passed through untouched): app switching, Spotlight, Spaces and Mission Control, screenshots. [] passes nothing."),
            .init(section: "global", key: "legend", defaultValue: "\"symbols\"", comment: "Status strip actions as glyphs (\"symbols\": ● click, ⤒ drag, ✕ exit; the help panel spells them out) or as \"words\"."),

            .init(section: "actions", key: "left_click", defaultValue: "[\"return\", \"m\"]", comment: "Left-click and exit; a count sets the click count (3 = triple), modifiers held pass through."),
            .init(section: "actions", key: "click_stay", defaultValue: "\"space\"", comment: "Left-click and stay in the mode, e.g. \"space\"."),
            .init(section: "actions", key: "double_click", defaultValue: "\"x\"", comment: "Double-click and exit, e.g. \"x\"."),
            .init(section: "actions", key: "right_click", defaultValue: "\"period\"", comment: "Right-click (context menu) and exit, e.g. \"period\", \"ctrl+return\"."),
            .init(section: "actions", key: "middle_click", defaultValue: "\"comma\"", comment: "Middle-click and exit, e.g. \"comma\"."),
            .init(section: "actions", key: "drag", defaultValue: "\"v\"", comment: "Press the left button; navigate; press again to release (drag or text selection), e.g. \"v\"."),
        ]
        for m in modes {
            for entry in m.schema {
                precondition(entry.section == m.id, "mode \(m.id) may only define its own section")
                e.append(entry)
            }
        }
        let styles = cursors.map { "\"\($0.id)\" (\($0.summary))" }.joined(separator: ", ")
        e.append(.init(section: "cursor", key: "style", defaultValue: "\"ring\"", comment: "Marker at the pointer: \(styles), or \"\" for none (the real pointer only)."))
        e.append(.init(section: "cursor", key: "size", defaultValue: "36", comment: "Marker size in pixels, e.g. 24, 36, 60."))
        e.append(.init(section: "cursor", key: "colour", defaultValue: "\"\"", comment: "Marker colour as \"#RRGGBB\", or \"\" for the active mode's colour."))
        e.append(.init(section: "drag", key: "ramp", defaultValue: "false", comment: "After pressing the button, wiggle the pointer a few pixels so apps that need movement before starting a drag-and-drop session do so. Breaks text drags in Chromium-based apps, so off unless an app needs it: true or false."))
        for m in modes {
            e.append(.init(section: "colours.modes", key: m.id, defaultValue: "\"\(m.defaultColour)\"", comment: "\(m.name.capitalized) mode."))
        }
        e.append(.init(section: "colours.markers", key: "drag", defaultValue: "\"#30D158\"", comment: "Drag badge, origin dot and line."))
        e.append(.init(section: "colours.markers", key: "snap", defaultValue: "\"#FF375F\"", comment: "Ring marking the snap target."))
        entries = e
    }

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
        "drag.restart_search": "pointer.drag_restart", "snap.enabled": "pointer.snap",
    ]

    /// Splits "section.sub.key" into its section ("section.sub") and key ("key").
    public static func split(_ path: String) -> (section: String, key: String) {
        guard let dot = path.lastIndex(of: ".") else { return ("", path) }
        return (String(path[..<dot]), String(path[path.index(after: dot)...]))
    }

    public var sections: [String] {
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
    public func template() -> String {
        var out = ConfigSchema.header + "\n"
        for section in sections {
            out += "\n# \(sectionComments[section] ?? section)\n[\(section)]\n"
            for e in entries where e.section == section {
                out += ConfigSchema.render(e).joined(separator: "\n") + "\n"
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
    public func migrate(_ text: String) -> (text: String, changed: Bool) {
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
            if line == ConfigSchema.retiredHeader { inRetired = true; continue }
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
        /// An earlier wording of the same comment: most words in common. A user's own note
        /// ("# clamped", "# my notes") shares few words with a schema comment.
        func isEarlierWording(_ old: String, of new: String) -> Bool {
            func words(_ s: String) -> Set<String> {
                Set(s.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 2 })
            }
            let a = words(old), b = words(new)
            guard !a.isEmpty, !b.isEmpty else { return false }
            return Double(a.intersection(b).count) / Double(a.union(b).count) >= 0.5
        }
        /// Index of a comment line directly above `i` that is an earlier wording of `comment`.
        func staleComment(above i: Int, for comment: String) -> Int? {
            var j = i - 1
            while j >= 0 {
                let l = lines[j].trimmingCharacters(in: .whitespaces)
                guard l.hasPrefix("#") else { return nil }
                if isEarlierWording(String(l.dropFirst()), of: comment) { return j }
                j -= 1
            }
            return nil
        }
        /// The key line without its inline comment, and that comment's text, if any.
        func splitInline(_ raw: String) -> (body: String, comment: String?) {
            let body = TOML.stripComment(raw)
            guard body.count < raw.count else { return (raw, nil) }
            let c = String(raw.dropFirst(body.count).dropFirst()).trimmingCharacters(in: .whitespaces)
            return (String(body.reversed().drop { $0 == " " }.reversed()), c)
        }
        for (i, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") && line.hasSuffix("]") {
                let name = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                current = name
                sections[name] = SectionInfo(start: i, end: i, keys: [], keyLines: 0)
                if let c = sectionComments[name], !hasComment("# \(c)", above: i) {
                    if let j = staleComment(above: i, for: c) {
                        lines[j] = "# \(c)"
                    } else {
                        commentsToInsert.append((before: i, text: ["# \(c)"]))
                    }
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
                    // An earlier wording of this comment, inline or above, makes way for the new one.
                    let (body, inline) = splitInline(raw)
                    var keyLine = raw
                    if let inline, isEarlierWording(inline, of: entry.comment) { keyLine = body }
                    if let j = staleComment(above: i, for: entry.comment) { removals.insert(j) }
                    if entry.comment.count <= ConfigSchema.inlineCommentLimit {
                        lines[i] = "\(keyLine)   # \(entry.comment)"
                    } else {
                        lines[i] = keyLine
                        // Blank line first unless the key already follows a blank line or the header.
                        var p = i - 1
                        while p >= 0, removals.contains(p) { p -= 1 }
                        let prev = p >= 0 ? lines[p].trimmingCharacters(in: .whitespaces) : ""
                        let separated = prev.isEmpty || prev.hasPrefix("[") || prev.hasPrefix("#")
                        commentsToInsert.append((before: i, text: (separated ? [] : [""]) + ["# \(entry.comment)"]))
                    }
                }
            } else if let target = ConfigSchema.renamed["\(sec).\(key)"] {
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
            let block = missing.flatMap { ConfigSchema.render($0, value: carried["\($0.section).\($0.key)"]) }
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
            lines += ["", ConfigSchema.retiredHeader] + retiredUnique.map { "# \($0)" }
        }
        // "Changed" means the text differs; the flags above only steer the passes.
        _ = changed
        let result = lines.joined(separator: "\n") + "\n"
        return (result, result != text)
    }
}
