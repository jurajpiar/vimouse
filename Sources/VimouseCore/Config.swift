import Foundation

/// User configuration: key bindings and tunables. Parsed from config.toml; every
/// missing key keeps its default, so an empty file is a valid config.
/// Overlay colours as "#RRGGBB".
public struct Colours: Equatable {
    public var pointer = "#0A84FF"
    public var drag = "#30D158"
    public var nudge = "#40C8E0"
    public var scroll = "#FF9F0A"
    public var ruler = "#BF5AF2"
    public var snap = "#FF375F"

    public init() {}

    public static func isValid(_ hex: String) -> Bool {
        hex.count == 7 && hex.hasPrefix("#") && hex.dropFirst().allSatisfy(\.isHexDigit)
    }
}

public struct Config: Equatable {
    public var keymap: KeyMap = .default
    public var colours = Colours()
    /// Whether the app may rewrite config.toml on start (migration).
    public var autoUpdate: Bool = true
    public var scrollStep: Double = 60
    public var rulerHeight: Double = 32
    /// 0 means move by the band's own height.
    public var rulerMove: Double = 0
    public var rulerHeightStep: Double = 4
    /// Pixels per press with Shift held, for move and resize.
    public var rulerFine: Double = 1
    public var rulerDim: Double = 0.35
    public var snapEnabled: Bool = true
    public var nudgeStep: Double = 5
    public var dragRestartsSearch: Bool = true
    public var dragRamp: Bool = false

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

        if let v = t["config"]?["update"] {
            guard let b = v.bool else { throw ParseError(description: "[config] update: expected true or false") }
            c.autoUpdate = b
        }
        if let p = try one("hotkey", "activate") { k.activate = p }

        var quadrants: [KeyPress: Quadrant] = [:]
        let qNames: [(String, Quadrant)] = [("top_left", .topLeft), ("top_right", .topRight), ("bottom_left", .bottomLeft), ("bottom_right", .bottomRight)]
        for (name, q) in qNames {
            if let p = try one("pointer", name) { quadrants[p] = q }
        }
        if !quadrants.isEmpty {
            guard quadrants.count == 4 else { throw ParseError(description: "[pointer]: all four quadrant keys must be set and distinct") }
            k.quadrants = quadrants
        }
        if let v = try keys("pointer", "up") { k.up = v }
        if let v = try keys("pointer", "top") { k.top = v }
        if let v = try keys("actions", "left_click") { k.leftClick = v }
        if let v = try keys("actions", "click_stay") { k.clickStay = v }
        if let v = try keys("actions", "double_click") { k.doubleClick = v }
        if let v = try keys("actions", "right_click") { k.rightClick = v }
        if let v = try keys("actions", "middle_click") { k.middleClick = v }
        if let v = try keys("actions", "drag") { k.dragToggle = v }
        if let v = try keys("global", "exit") { k.exit = v }
        if let v = try keys("global", "next_screen") { k.nextScreen = v }
        if let v = try keys("global", "previous_screen") { k.previousScreen = v }
        if let v = try keys("pointer", "snap_toggle") { k.snapToggle = v }
        if let v = try keys("scroll", "toggle") { k.scrollToggle = v }
        if let v = try keys("ruler", "toggle") { k.rulerToggle = v }
        if let v = try keys("ruler", "remove") { k.rulerRemove = v }

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

        if let v = try keys("global", "help") { k.help = v }
        if let v = try number("nudge", "step") { c.nudgeStep = max(1, v) }
        if let v = try keys("nudge", "toggle") { k.nudgeToggle = v }
        if let v = try keys("nudge", "left") { k.nudgeLeft = v }
        if let v = try keys("nudge", "right") { k.nudgeRight = v }
        if let v = try keys("nudge", "up") { k.nudgeUp = v }
        if let v = try keys("nudge", "down") { k.nudgeDown = v }

        if let v = t["drag"]?["restart_search"] {
            guard let b = v.bool else { throw ParseError(description: "[drag] restart_search: expected true or false") }
            c.dragRestartsSearch = b
        }
        if let v = t["drag"]?["ramp"] {
            guard let b = v.bool else { throw ParseError(description: "[drag] ramp: expected true or false") }
            c.dragRamp = b
        }
        func colour(_ name: String, _ set: (inout Colours, String) -> Void) throws {
            guard let v = t["colours"]?[name] else { return }
            guard let hex = v.string, Colours.isValid(hex) else { throw ParseError(description: "[colours] \(name): expected \"#RRGGBB\"") }
            set(&c.colours, hex.uppercased())
        }
        try colour("pointer") { $0.pointer = $1 }
        try colour("drag") { $0.drag = $1 }
        try colour("nudge") { $0.nudge = $1 }
        try colour("scroll") { $0.scroll = $1 }
        try colour("ruler") { $0.ruler = $1 }
        try colour("snap") { $0.snap = $1 }

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
