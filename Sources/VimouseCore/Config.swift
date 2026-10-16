import Foundation

/// User configuration: key bindings and tunables. Parsed from config.toml; every
/// missing key keeps its default, so an empty file is a valid config.
public struct Config: Equatable {
    public var keymap: KeyMap = .default
    public var scrollStep: Double = 60
    public var rulerHeight: Double = 32
    /// 0 means move by the band's own height.
    public var rulerMove: Double = 0
    public var rulerHeightStep: Double = 4
    /// Pixels per press with Shift held, for move and resize.
    public var rulerFine: Double = 1
    public var rulerDim: Double = 0.35
    public var snapEnabled: Bool = true

    public init() {}

    public struct ParseError: Error, CustomStringConvertible {
        public let description: String
    }

    /// The file written on first run. Generated from `ConfigSchema`; parsing it must
    /// reproduce `Config()` (there is a test).
    public static var defaultTOML: String { ConfigSchema.template() }

    public static func parse(_ text: String) throws -> Config {
        let t: TOMLTable
        do { t = try TOML.parse(text) } catch let e as TOMLError { throw ParseError(description: e.description) }
        var c = Config()
        var k = KeyMap.default

        func keys(_ section: String, _ name: String) throws -> Set<KeyPress>? {
            guard let v = t[section]?[name] else { return nil }
            guard let specs = v.strings else { throw ParseError(description: "[\(section)] \(name): expected a key name or list of key names") }
            var out = Set<KeyPress>()
            for spec in specs {
                guard let p = KeyPress.parse(spec) else { throw ParseError(description: "[\(section)] \(name): unknown key \"\(spec)\"") }
                out.insert(p)
            }
            return out
        }
        func one(_ section: String, _ name: String) throws -> KeyPress? {
            guard let set = try keys(section, name) else { return nil }
            guard set.count == 1, let p = set.first else { throw ParseError(description: "[\(section)] \(name): exactly one key expected") }
            return p
        }
        func number(_ section: String, _ name: String) throws -> Double? {
            guard let v = t[section]?[name] else { return nil }
            guard let d = v.double else { throw ParseError(description: "[\(section)] \(name): expected a number") }
            return d
        }

        if let p = try one("hotkey", "activate") { k.activate = p }

        var quadrants: [KeyPress: Quadrant] = [:]
        let qNames: [(String, Quadrant)] = [("top_left", .topLeft), ("top_right", .topRight), ("bottom_left", .bottomLeft), ("bottom_right", .bottomRight)]
        for (name, q) in qNames {
            if let p = try one("keys", name) { quadrants[p] = q }
        }
        if !quadrants.isEmpty {
            guard quadrants.count == 4 else { throw ParseError(description: "[keys]: all four quadrant keys must be set and distinct") }
            k.quadrants = quadrants
        }
        if let v = try keys("keys", "up") { k.up = v }
        if let v = try keys("keys", "left_click") { k.leftClick = v }
        if let v = try keys("keys", "click_stay") { k.clickStay = v }
        if let v = try keys("keys", "double_click") { k.doubleClick = v }
        if let v = try keys("keys", "right_click") { k.rightClick = v }
        if let v = try keys("keys", "middle_click") { k.middleClick = v }
        if let v = try keys("keys", "drag") { k.dragToggle = v }
        if let v = try keys("keys", "exit") { k.exit = v }
        if let v = try keys("keys", "next_screen") { k.nextScreen = v }
        if let v = try keys("keys", "previous_screen") { k.previousScreen = v }
        if let v = try keys("keys", "snap_toggle") { k.snapToggle = v }
        if let v = try keys("keys", "scroll_toggle") { k.scrollToggle = v }
        if let v = try keys("keys", "ruler_toggle") { k.rulerToggle = v }
        if let v = try keys("keys", "ruler_remove") { k.rulerRemove = v }

        if let v = try number("scroll", "step") { c.scrollStep = v }
        if let v = try keys("scroll", "down") { k.scrollDown = v }
        if let v = try keys("scroll", "up") { k.scrollUp = v }
        if let v = try keys("scroll", "left") { k.scrollLeft = v }
        if let v = try keys("scroll", "right") { k.scrollRight = v }
        if let v = try keys("scroll", "half_page_down") { k.scrollHalfDown = v }
        if let v = try keys("scroll", "half_page_up") { k.scrollHalfUp = v }

        if let v = try number("ruler", "height") { c.rulerHeight = v }
        if let v = try number("ruler", "move") { c.rulerMove = max(0, v) }
        if let v = try number("ruler", "height_step") { c.rulerHeightStep = v }
        if let v = try number("ruler", "fine") { c.rulerFine = max(0.5, v) }
        if let v = try number("ruler", "dim") { c.rulerDim = min(max(v, 0), 1) }
        if let v = try keys("ruler", "down") { k.rulerDown = v }
        if let v = try keys("ruler", "up") { k.rulerUp = v }
        if let v = try keys("ruler", "grow") { k.rulerGrow = v }
        if let v = try keys("ruler", "shrink") { k.rulerShrink = v }

        if let v = t["snap"]?["enabled"] {
            guard let b = v.bool else { throw ParseError(description: "[snap] enabled: expected true or false") }
            c.snapEnabled = b
        }

        c.keymap = k
        return c
    }
}

// MARK: - Key specs

public extension KeyPress {
    /// Display form: modifier symbols then the key, e.g. "⇧⇥", "⌘⇧␣", "↓".
    var label: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + code.label
    }

    /// Parses "cmd+shift+space", "shift+r", "leftbracket", "a".
    static func parse(_ spec: String) -> KeyPress? {
        let parts = spec.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let last = parts.last, let code = KeyCode.named(last) else { return nil }
        var mods: Modifiers = []
        for m in parts.dropLast() {
            switch m {
            case "cmd", "command", "meta": mods.insert(.command)
            case "shift": mods.insert(.shift)
            case "ctrl", "control": mods.insert(.control)
            case "alt", "opt", "option": mods.insert(.option)
            default: return nil
            }
        }
        return KeyPress(code, mods)
    }
}

public extension KeyCode {
    static let minus = KeyCode(rawValue: 27)
    static let equal = KeyCode(rawValue: 24)
    static let leftArrow = KeyCode(rawValue: 123)
    static let rightArrow = KeyCode(rawValue: 124)
    static let downArrow = KeyCode(rawValue: 125)
    static let upArrow = KeyCode(rawValue: 126)
    static let pageUp = KeyCode(rawValue: 116)
    static let pageDown = KeyCode(rawValue: 121)
    static let home = KeyCode(rawValue: 115)
    static let end = KeyCode(rawValue: 119)

    static func named(_ name: String) -> KeyCode? {
        if name.count == 1, let c = name.first {
            if let letter = letters[c] { return letter }
            if let digit = digits[c] { return digit }
            switch c {
            case ",": return .comma
            case ".": return .period
            case "/": return .slash
            case "[": return .leftBracket
            case "]": return .rightBracket
            case "-": return .minus
            case "=": return .equal
            default: return nil
            }
        }
        switch name {
        case "space": return .space
        case "return", "enter": return .return
        case "tab": return .tab
        case "escape", "esc": return .escape
        case "backspace", "delete": return .delete
        case "comma": return .comma
        case "period", "dot": return .period
        case "slash": return .slash
        case "leftbracket": return .leftBracket
        case "rightbracket": return .rightBracket
        case "minus": return .minus
        case "equal", "equals": return .equal
        case "left", "arrowleft": return .leftArrow
        case "right", "arrowright": return .rightArrow
        case "up", "arrowup": return .upArrow
        case "down", "arrowdown": return .downArrow
        case "pageup": return .pageUp
        case "pagedown": return .pageDown
        case "home": return .home
        case "end": return .end
        default: return nil
        }
    }

    /// Short display name for legends and in-rectangle labels.
    var label: String {
        if let n = KeyCode.labels[self] { return n }
        return "?"
    }

    private static let labels: [KeyCode: String] = {
        var m: [KeyCode: String] = [:]
        for (c, k) in letters { m[k] = String(c) }
        for (c, k) in digits { m[k] = String(c) }
        m[.space] = "␣"; m[.return] = "⏎"; m[.tab] = "⇥"; m[.escape] = "esc"; m[.delete] = "⌫"
        m[.comma] = ","; m[.period] = "."; m[.slash] = "/"; m[.leftBracket] = "["; m[.rightBracket] = "]"
        m[.minus] = "-"; m[.equal] = "="
        m[.leftArrow] = "←"; m[.rightArrow] = "→"; m[.upArrow] = "↑"; m[.downArrow] = "↓"
        m[.pageUp] = "⇞"; m[.pageDown] = "⇟"; m[.home] = "↖"; m[.end] = "↘"
        return m
    }()

    private static let letters: [Character: KeyCode] = [
        "a": .a, "b": .b, "c": .c, "d": .d, "e": .e, "f": .f, "g": .g, "h": .h, "i": .i, "j": .j, "k": .k, "l": .l, "m": .m,
        "n": .n, "o": .o, "p": .p, "q": .q, "r": .r, "s": .s, "t": .t, "u": .u, "v": .v, "w": .w, "x": .x, "y": .y, "z": .z,
    ]
    private static let digits: [Character: KeyCode] = [
        "0": .zero, "1": .one, "2": .two, "3": .three, "4": .four, "5": .five, "6": .six, "7": .seven, "8": .eight, "9": .nine,
    ]
}
