import VimouseCore

/// Letter labels on every clickable element the accessibility tree exposes; type a
/// label to go there (and click, by default). The same idea as Vimac, Shortcat and
/// Vimium. Electron and browser content show up when the app exposes it.
public final class HintsMode: Mode {
    public struct Settings: ModeSettings, Equatable {
        public var toggle: Set<KeyPress> = [KeyPress(.f)]
        /// Letters used for labels, most comfortable first.
        public var letters = "asdfghjklqwertyuiopzxcvbnm"
        /// Click the element once chosen (and exit), or only move the pointer there.
        public var click = true
        public var backspace: Set<KeyPress> = [KeyPress(.delete)]
        public init() {}
    }

    public let id = "hints"
    public let name = "HINTS"
    public let summary = "Hints mode: letter labels on clickable elements; type one to jump to it."
    public let defaultColour = "#FFD60A"
    public var settings = Settings()
    /// Labelled elements, and the letters typed so far.
    public private(set) var targets: [(label: String, frame: Rect)] = []
    public private(set) var typed = ""

    public init() {}

    public var schema: [ConfigEntry] {
        [
            .init(section: id, key: "toggle", defaultValue: "\"f\"", comment: "Enter or leave Hints mode, e.g. \"f\"."),
            .init(section: id, key: "letters", defaultValue: "\"asdfghjklqwertyuiopzxcvbnm\"", comment: "Letters used for the labels, most comfortable first; more letters mean shorter labels."),
            .init(section: id, key: "click", defaultValue: "true", comment: "Click the chosen element and exit (true), or only move the pointer onto it and return to the previous mode (false)."),
            .init(section: id, key: "backspace", defaultValue: "\"backspace\"", comment: "Delete the last typed letter, e.g. \"backspace\"."),
        ]
    }

    public func parseSettings(_ table: TOMLTable) throws -> ModeSettings {
        let r = ConfigReader(table, section: id)
        var s = Settings()
        if let v = try r.keys("toggle") { s.toggle = v }
        if let v = try r.string("letters") {
            let l = v.lowercased()
            guard l.count >= 2, l.allSatisfy({ $0.isLetter }), Set(l).count == l.count else { throw r.fail("letters", "expected at least two distinct letters") }
            s.letters = l
        }
        if let v = try r.bool("click") { s.click = v }
        if let v = try r.keys("backspace") { s.backspace = v }
        return s
    }

    public func apply(_ s: ModeSettings) {
        if let s = s as? Settings { settings = s }
    }

    public var toggle: Set<KeyPress> { settings.toggle }
    public var acceptsKeyRepeat: Bool { false }
    public var capturesKeys: Bool { true }

    public func activate(_ ctx: ModeContext) {
        typed = ""
        let frames = ctx.services.elements?.elements(on: ctx.screen) ?? []
        targets = zip(HintsMode.labels(count: frames.count, letters: settings.letters), frames).map { (label: $0, frame: $1) }
    }

    public func deactivate(_ ctx: ModeContext, reason: LeaveReason) {
        targets = []
        typed = ""
    }

    public func screenChanged(_ ctx: ModeContext) { activate(ctx) }

    /// Labels of one length, enough for `count` elements, from the given letters.
    public static func labels(count: Int, letters: String) -> [String] {
        let chars = Array(letters)
        guard count > 0, chars.count >= 2 else { return [] }
        var length = 1
        var capacity = chars.count
        while capacity < count { capacity *= chars.count; length += 1 }
        var out: [String] = []
        var indices = [Int](repeating: 0, count: length)
        while out.count < count {
            out.append(String(indices.map { chars[$0] }))
            var i = length - 1
            while i >= 0 {
                indices[i] += 1
                if indices[i] < chars.count { break }
                indices[i] = 0
                i -= 1
            }
        }
        return out
    }

    public func handle(_ key: KeyPress, count: Int?, _ ctx: ModeContext) -> [Effect]? {
        if settings.backspace.has(key) {
            guard !typed.isEmpty else { return [] }
            typed.removeLast()
            return [.redraw]
        }
        // A letter of the label alphabet, typed without modifiers.
        let label = key.code.label
        guard key.modifiers.generic.isEmpty, label.count == 1, let letter = label.first, settings.letters.contains(letter) else { return nil }
        let next = typed + String(letter)
        let matches = targets.filter { $0.label.hasPrefix(next) }
        guard !matches.isEmpty else { return [.redraw] } // no such label: ignore the letter
        typed = next
        if matches.count == 1, matches[0].label == typed {
            ctx.target = matches[0].frame.center
            if settings.click {
                // Warp, click, and leave, as a click key would.
                ctx.requestExit()
                return [.warp(ctx.target), .click(.left, count: 1, modifiers: [])]
            }
            ctx.switchMode(to: nil)
            return [.warp(ctx.target), .redraw]
        }
        return [.redraw]
    }

    public let symbol = "⌨"

    public func hints(_ ctx: ModeContext) -> [Hint] {
        var h = [Hint(targets.isEmpty ? "" : "a-z", targets.isEmpty ? "no elements found" : "type a label", "⌨" + (typed.isEmpty ? "" : " " + typed))]
        if !typed.isEmpty { h.append(Hint(KeyMap.label(of: settings.backspace), "delete letter", "⌫")) }
        return h
    }

    public func help(_ ctx: ModeContext) -> [(keys: String, action: String)] {
        [
            ("letters", settings.click ? "type a label to click its element" : "type a label to move the pointer onto its element"),
            (settings.backspace.map(\.label).sorted().joined(separator: " "), "delete the last typed letter"),
        ]
    }

    public func draw(_ ctx: ModeContext, active: Bool) -> [Drawable] {
        guard active else { return [] }
        let c = ctx.colour(of: id)
        var d: [Drawable] = []
        for t in targets where t.label.hasPrefix(typed) {
            let tag = Rect(x: t.frame.x, y: t.frame.y, width: 10 + Double(t.label.count) * 9, height: 18)
            d.append(.fill(tag, colour: c, alpha: 0.92))
            d.append(.outline(tag, colour: "#000000", alpha: 0.6, width: 1))
            d.append(.label(t.label, in: tag, colour: "#000000", alpha: 1))
        }
        return d
    }

    public var manual: String {
        "Letter labels on every clickable element the frontmost app exposes through accessibility; typing a label moves the pointer onto that element and clicks it (or only moves there with [hints] click = false). Backspace deletes a typed letter."
    }
}
