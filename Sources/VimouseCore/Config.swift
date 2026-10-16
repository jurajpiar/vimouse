import Foundation

/// Overlay colours as "#RRGGBB": one per mode (keyed by mode id) and the markers.
public struct Colours: Equatable {
    public var modes: [String: String] = [:]
    public var drag = "#30D158"
    public var snap = "#FF375F"
    /// Used for a mode without a configured colour.
    public static let fallback = "#0A84FF"

    public init() {}

    public func mode(_ id: String) -> String { modes[id] ?? Colours.fallback }

    public static func isValid(_ hex: String) -> Bool {
        hex.count == 7 && hex.hasPrefix("#") && hex.dropFirst().allSatisfy(\.isHexDigit)
    }
}

/// User configuration: the shared bindings and tunables, plus each mode's parsed
/// settings. Parsed from config.toml; every missing key keeps its default, so an empty
/// file is a valid config.
public struct Config: Equatable {
    public static func == (a: Config, b: Config) -> Bool {
        a.keymap == b.keymap && a.activateMode == b.activateMode && a.holdMode == b.holdMode
            && a.colours == b.colours && a.enabledModes == b.enabledModes && a.autoUpdate == b.autoUpdate
            && a.dragRamp == b.dragRamp && a.cursor == b.cursor && a.legendSymbols == b.legendSymbols && Set(a.modeSettings.keys) == Set(b.modeSettings.keys)
            && a.modeSettings.allSatisfy { id, s in b.modeSettings[id].map(s.isEqual(to:)) ?? false }
    }

    public var keymap: KeyMap = .default
    /// Mode entered by the hotkey and by the hold key (mode ids).
    public var activateMode: String
    public var holdMode: String
    public var colours = Colours()
    /// `[modes] enabled`; nil when not set (all registered modes, in registration order).
    public var enabledModes: [String]?
    /// Whether the app may rewrite config.toml on start (migration).
    public var autoUpdate: Bool = true
    public var dragRamp: Bool = false
    public var cursor = CursorConfig()
    /// Status strip shows glyphs (true) or words (false) for actions.
    public var legendSymbols = true
    /// Each mode's settings, keyed by mode id, as parsed by the mode.
    public var modeSettings: [String: ModeSettings] = [:]

    public init(modes: [Mode] = []) {
        activateMode = modes.first?.id ?? "pointer"
        holdMode = activateMode
        enabledModes = modes.isEmpty ? nil : modes.filter(\.enabledByDefault).map(\.id)
        for m in modes {
            colours.modes[m.id] = m.defaultColour
            modeSettings[m.id] = try? m.parseSettings([:])
        }
    }

    public struct ParseError: Error, CustomStringConvertible {
        public let description: String
        public init(description: String) { self.description = description }
    }

    /// The whole file, with the modes' sections. Parsing it must reproduce the defaults
    /// (there is a test).
    public static func parse(_ text: String, modes: [Mode], cursors: [CursorStyle] = []) throws -> Config {
        let t: TOMLTable
        do { t = try TOML.parse(text) } catch let e as TOMLError { throw ParseError(description: e.description) }
        var c = Config(modes: modes)
        var k = KeyMap.default
        let ids = modes.map(\.id)

        // Unknown sections and keys are tolerated (migration retires them); known ones must parse.
        if let v = try ConfigReader(t, section: "config").bool("update") { c.autoUpdate = v }

        let hotkey = ConfigReader(t, section: "hotkey")
        if let p = try hotkey.one("activate") { k.activate = p }
        func mode(_ name: String) throws -> String? {
            guard let s = try hotkey.string(name) else { return nil }
            let id = s.lowercased()
            guard ids.contains(id) else { throw hotkey.fail(name, "expected one of \(ids.joined(separator: ", "))") }
            return id
        }
        if let m = try mode("activate_mode") { c.activateMode = m }
        if let m = try mode("hold_mode") { c.holdMode = m }
        if let name = try hotkey.string("hold") {
            if name.isEmpty {
                k.hold = nil
            } else if let code = KeyCode.named(name.lowercased()), code.modifierBit != nil || code == .function {
                k.hold = .key(code)
            } else if let chord = Modifiers.parse(name) {
                k.hold = .chord(chord)
            } else {
                throw hotkey.fail("hold", "expected a modifier chord like \"cmd+shift\" or one of left_cmd, right_cmd, left_alt, right_alt, left_ctrl, right_ctrl, left_shift, right_shift, fn")
            }
        }

        let modesSection = ConfigReader(t, section: "modes")
        if let v = modesSection.value("enabled") {
            guard let list = v.strings else { throw modesSection.fail("enabled", "expected a list of mode names") }
            var out: [String] = []
            for name in list {
                let id = name.lowercased()
                guard ids.contains(id) else { throw modesSection.fail("enabled", "unknown mode \"\(name)\"; available: \(ids.joined(separator: ", "))") }
                if !out.contains(id) { out.append(id) }
            }
            guard !out.isEmpty else { throw modesSection.fail("enabled", "at least one mode") }
            c.enabledModes = out
        }

        let global = ConfigReader(t, section: "global")
        if let v = try global.keys("exit") { k.exit = v }
        if let v = try global.keys("next_screen") { k.nextScreen = v }
        if let v = try global.keys("previous_screen") { k.previousScreen = v }
        if let v = try global.keys("help") { k.help = v }
        if let v = try global.keys("passthrough") { k.passthrough = v }
        if let v = try global.string("legend") {
            switch v.lowercased() {
            case "symbols": c.legendSymbols = true
            case "words": c.legendSymbols = false
            default: throw global.fail("legend", "expected \"symbols\" or \"words\"")
            }
        }

        let actions = ConfigReader(t, section: "actions")
        if let v = try actions.keys("left_click") { k.leftClick = v }
        if let v = try actions.keys("click_stay") { k.clickStay = v }
        if let v = try actions.keys("double_click") { k.doubleClick = v }
        if let v = try actions.keys("right_click") { k.rightClick = v }
        if let v = try actions.keys("middle_click") { k.middleClick = v }
        if let v = try actions.keys("drag") { k.dragToggle = v }

        if let v = try ConfigReader(t, section: "drag").bool("ramp") { c.dragRamp = v }

        let cursor = ConfigReader(t, section: "cursor")
        if let v = try cursor.string("style") {
            let id = v.lowercased()
            guard id.isEmpty || cursors.contains(where: { $0.id == id }) else {
                throw cursor.fail("style", "unknown style \"\(v)\"; available: \(cursors.map(\.id).joined(separator: ", ")), or \"\" for none")
            }
            c.cursor.style = id
        }
        if let v = try cursor.number("size") { c.cursor.size = max(4, v) }
        if let v = try cursor.string("colour") {
            guard v.isEmpty || Colours.isValid(v) else { throw cursor.fail("colour", "expected \"#RRGGBB\" or \"\"") }
            c.cursor.colour = v.uppercased()
        }

        func colour(_ section: String, _ name: String, _ set: (inout Colours, String) -> Void) throws {
            guard let v = t[section]?[name] else { return }
            guard let hex = v.string, Colours.isValid(hex) else { throw ParseError(description: "[\(section)] \(name): expected \"#RRGGBB\"") }
            set(&c.colours, hex.uppercased())
        }
        for id in ids { try colour("colours.modes", id) { $0.modes[id] = $1 } }
        try colour("colours.markers", "drag") { $0.drag = $1 }
        try colour("colours.markers", "snap") { $0.snap = $1 }

        for m in modes { c.modeSettings[m.id] = try m.parseSettings(t) }

        c.keymap = k
        return c
    }

    /// A mode's settings, typed.
    public func settings<S: ModeSettings>(_ type: S.Type, for id: String) -> S? {
        modeSettings[id] as? S
    }
}

// MARK: - Key specs

public extension Modifiers {
    /// One modifier name: generic ("shift") or sided ("left_shift", "rshift").
    static func named(_ name: String) -> Modifiers? {
        switch name {
        case "cmd", "command", "meta": return .command
        case "shift": return .shift
        case "ctrl", "control": return .control
        case "alt", "opt", "option": return .option
        case "left_shift", "lshift": return .leftShift
        case "right_shift", "rshift": return .rightShift
        case "left_ctrl", "lctrl", "left_control": return .leftControl
        case "right_ctrl", "rctrl", "right_control": return .rightControl
        case "left_alt", "lalt", "left_option": return .leftOption
        case "right_alt", "ralt", "right_option": return .rightOption
        case "left_cmd", "lcmd", "left_command": return .leftCommand
        case "right_cmd", "rcmd", "right_command": return .rightCommand
        default: return nil
        }
    }

    /// Parses "cmd+shift+ctrl" or "cmd+left_shift" (modifiers only, at least one).
    static func parse(_ spec: String) -> Modifiers? {
        var mods: Modifiers = []
        for m in spec.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            guard let bit = Modifiers.named(m) else { return nil }
            mods.insert(bit)
        }
        return mods.isEmpty ? nil : mods
    }
}

public extension KeyPress {
    /// Display form: modifier symbols then the key, e.g. "⇧⇥", "⌘⇧␣", "↓".
    var label: String {
        var s = ""
        func sym(_ m: Modifiers, _ symbol: String) {
            let (l, r) = Modifiers.sides(of: m)
            if modifiers.contains(l) { s += "L" + symbol }
            else if modifiers.contains(r) { s += "R" + symbol }
            else if modifiers.contains(m) { s += symbol }
        }
        sym(.control, "⌃"); sym(.option, "⌥"); sym(.shift, "⇧"); sym(.command, "⌘")
        return s + code.label
    }

    /// Parses "cmd+shift+space", "shift+r", "leftbracket", "a".
    static func parse(_ spec: String) -> KeyPress? {
        let parts = spec.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let last = parts.last, let code = KeyCode.named(last) else { return nil }
        var mods: Modifiers = []
        for m in parts.dropLast() {
            guard let bit = Modifiers.named(m) else { return nil }
            mods.insert(bit)
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
        case "left_cmd", "lcmd": return .leftCommand
        case "right_cmd", "rcmd": return .rightCommand
        case "left_shift", "lshift": return .leftShift
        case "right_shift", "rshift": return .rightShift
        case "left_alt", "lalt", "left_option": return .leftOption
        case "right_alt", "ralt", "right_option": return .rightOption
        case "left_ctrl", "lctrl": return .leftControl
        case "right_ctrl", "rctrl": return .rightControl
        case "fn": return .function
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
        m[.leftCommand] = "⌘"; m[.rightCommand] = "⌘"; m[.leftShift] = "⇧"; m[.rightShift] = "⇧"
        m[.leftOption] = "⌥"; m[.rightOption] = "⌥"; m[.leftControl] = "⌃"; m[.rightControl] = "⌃"; m[.function] = "fn"
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
