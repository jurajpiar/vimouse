/// A hardware key, identified by macOS virtual key code so bindings survive
/// keyboard-layout changes. Names below are for the ANSI US layout.
public struct KeyCode: Hashable, RawRepresentable, Sendable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }
}

public extension KeyCode {
    static let a = KeyCode(rawValue: 0)
    static let s = KeyCode(rawValue: 1)
    static let d = KeyCode(rawValue: 2)
    static let f = KeyCode(rawValue: 3)
    static let h = KeyCode(rawValue: 4)
    static let g = KeyCode(rawValue: 5)
    static let z = KeyCode(rawValue: 6)
    static let x = KeyCode(rawValue: 7)
    static let c = KeyCode(rawValue: 8)
    static let v = KeyCode(rawValue: 9)
    static let b = KeyCode(rawValue: 11)
    static let q = KeyCode(rawValue: 12)
    static let w = KeyCode(rawValue: 13)
    static let e = KeyCode(rawValue: 14)
    static let r = KeyCode(rawValue: 15)
    static let y = KeyCode(rawValue: 16)
    static let t = KeyCode(rawValue: 17)
    static let o = KeyCode(rawValue: 31)
    static let u = KeyCode(rawValue: 32)
    static let i = KeyCode(rawValue: 34)
    static let p = KeyCode(rawValue: 35)
    static let l = KeyCode(rawValue: 37)
    static let j = KeyCode(rawValue: 38)
    static let k = KeyCode(rawValue: 40)
    static let n = KeyCode(rawValue: 45)
    static let m = KeyCode(rawValue: 46)
    static let comma = KeyCode(rawValue: 43)
    static let period = KeyCode(rawValue: 47)
    static let slash = KeyCode(rawValue: 44)
    static let `return` = KeyCode(rawValue: 36)
    static let space = KeyCode(rawValue: 49)
    static let delete = KeyCode(rawValue: 51)
    static let escape = KeyCode(rawValue: 53)
    static let tab = KeyCode(rawValue: 48)
    static let one = KeyCode(rawValue: 18)
    static let two = KeyCode(rawValue: 19)
    static let three = KeyCode(rawValue: 20)
    static let four = KeyCode(rawValue: 21)
    static let five = KeyCode(rawValue: 23)
    static let six = KeyCode(rawValue: 22)
    static let seven = KeyCode(rawValue: 26)
    static let eight = KeyCode(rawValue: 28)
    static let nine = KeyCode(rawValue: 25)
    static let zero = KeyCode(rawValue: 29)
    static let leftBracket = KeyCode(rawValue: 33)
    static let leftCommand = KeyCode(rawValue: 55)
    static let rightCommand = KeyCode(rawValue: 54)
    static let leftShift = KeyCode(rawValue: 56)
    static let rightShift = KeyCode(rawValue: 60)
    static let leftOption = KeyCode(rawValue: 58)
    static let rightOption = KeyCode(rawValue: 61)
    static let leftControl = KeyCode(rawValue: 59)
    static let rightControl = KeyCode(rawValue: 62)
    static let function = KeyCode(rawValue: 63)

    /// The side-specific bit of a modifier key.
    var sideBit: Modifiers? {
        switch self {
        case .leftCommand: return .leftCommand
        case .rightCommand: return .rightCommand
        case .leftShift: return .leftShift
        case .rightShift: return .rightShift
        case .leftOption: return .leftOption
        case .rightOption: return .rightOption
        case .leftControl: return .leftControl
        case .rightControl: return .rightControl
        default: return nil
        }
    }

    /// The modifier bit a modifier key sets, for stripping it while it is used as a hold key.
    var modifierBit: Modifiers? {
        switch self {
        case .leftCommand, .rightCommand: return .command
        case .leftShift, .rightShift: return .shift
        case .leftOption, .rightOption: return .option
        case .leftControl, .rightControl: return .control
        default: return nil
        }
    }
    static let rightBracket = KeyCode(rawValue: 30)
}

/// Modifier state. The four generic bits say a modifier is down; the side bits say
/// which key. Events carry both; a binding carries generic bits (either side) or
/// side bits (that side only).
public struct Modifiers: OptionSet, Hashable, Sendable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    public static let shift = Modifiers(rawValue: 1 << 0)
    public static let control = Modifiers(rawValue: 1 << 1)
    public static let option = Modifiers(rawValue: 1 << 2)
    public static let command = Modifiers(rawValue: 1 << 3)
    public static let leftShift = Modifiers(rawValue: 1 << 4)
    public static let rightShift = Modifiers(rawValue: 1 << 5)
    public static let leftControl = Modifiers(rawValue: 1 << 6)
    public static let rightControl = Modifiers(rawValue: 1 << 7)
    public static let leftOption = Modifiers(rawValue: 1 << 8)
    public static let rightOption = Modifiers(rawValue: 1 << 9)
    public static let leftCommand = Modifiers(rawValue: 1 << 10)
    public static let rightCommand = Modifiers(rawValue: 1 << 11)

    public static let generics: [Modifiers] = [.shift, .control, .option, .command]

    static func sides(of generic: Modifiers) -> (left: Modifiers, right: Modifiers) {
        switch generic {
        case .shift: return (.leftShift, .rightShift)
        case .control: return (.leftControl, .rightControl)
        case .option: return (.leftOption, .rightOption)
        default: return (.leftCommand, .rightCommand)
        }
    }

    /// The generic bits implied by this set (a side bit implies its generic).
    public var generic: Modifiers {
        var g = intersection([.shift, .control, .option, .command])
        for m in Modifiers.generics {
            let (l, r) = Modifiers.sides(of: m)
            if contains(l) || contains(r) { g.insert(m) }
        }
        return g
    }

    /// Are all of these modifiers (generic: either side; sided: that side) held in `event`?
    /// Extra modifiers in the event are allowed.
    public func matchesHeld(in event: Modifiers) -> Bool {
        for m in Modifiers.generics {
            let (l, r) = Modifiers.sides(of: m)
            if contains(m), !event.contains(m) { return false }
            if contains(l), !event.contains(l) { return false }
            if contains(r), !event.contains(r) { return false }
        }
        return true
    }

    /// Does an event's modifier state satisfy this binding's requirement?
    public func matches(event: Modifiers) -> Bool {
        for m in Modifiers.generics {
            let (l, r) = Modifiers.sides(of: m)
            let required = contains(m) || contains(l) || contains(r)
            if required != event.contains(m) { return false }
            if contains(l), !event.contains(l) { return false }
            if contains(r), !event.contains(r) { return false }
        }
        return true
    }
}

public struct KeyPress: Hashable, Sendable {
    public var code: KeyCode
    public var modifiers: Modifiers

    public init(_ code: KeyCode, _ modifiers: Modifiers = []) {
        self.code = code
        self.modifiers = modifiers
    }

    /// This binding matches the event (same key; modifiers as required, sides respected).
    public func matches(event: KeyPress) -> Bool {
        code == event.code && modifiers.matches(event: event.modifiers)
    }
}

public extension Set where Element == KeyPress {
    /// Any binding in the set matches the event.
    func has(_ event: KeyPress) -> Bool { contains { $0.matches(event: event) } }
}

/// What has to be held for quasi-mode: one specific modifier key, or a chord of
/// modifiers regardless of side.
public enum HoldKey: Equatable, Sendable {
    case key(KeyCode)
    case chord(Modifiers)

    /// The modifiers the hold key accounts for (stripped from typed keys while held).
    public var bits: Modifiers {
        switch self {
        case .key(let c): return c.modifierBit ?? []
        case .chord(let m): return m
        }
    }

    public var label: String {
        switch self {
        case .key(let c): return c.label
        case .chord(let m): return KeyPress(.space, m).label.replacingOccurrences(of: "␣", with: "")
        }
    }
}

/// Bindings shared by every mode. Mode-specific bindings live in each mode's settings.
public struct KeyMap: Sendable, Equatable {
    public var activate: KeyPress
    /// Quasi-mode trigger: active while this is held; nil when unused.
    public var hold: HoldKey?
    public var leftClick: Set<KeyPress>
    public var rightClick: Set<KeyPress>
    public var middleClick: Set<KeyPress>
    public var clickStay: Set<KeyPress>
    public var doubleClick: Set<KeyPress>
    public var dragToggle: Set<KeyPress>
    public var exit: Set<KeyPress>
    public var nextScreen: Set<KeyPress>
    public var previousScreen: Set<KeyPress>
    /// Count prefix digits (vi style): key -> digit value.
    public var digits: [KeyPress: Int]
    public var help: Set<KeyPress>
    /// Combinations handed to the system untouched while a mode is active.
    public var passthrough: Set<KeyPress>

    public init(
        activate: KeyPress,
        hold: HoldKey? = nil,
        leftClick: Set<KeyPress>,
        rightClick: Set<KeyPress>,
        middleClick: Set<KeyPress>,
        clickStay: Set<KeyPress> = [],
        doubleClick: Set<KeyPress> = [],
        dragToggle: Set<KeyPress> = [],
        exit: Set<KeyPress>,
        nextScreen: Set<KeyPress> = [],
        previousScreen: Set<KeyPress> = [],
        digits: [KeyPress: Int] = [:],
        help: Set<KeyPress> = [],
        passthrough: Set<KeyPress> = []
    ) {
        self.activate = activate
        self.hold = hold
        self.leftClick = leftClick
        self.rightClick = rightClick
        self.middleClick = middleClick
        self.clickStay = clickStay
        self.doubleClick = doubleClick
        self.dragToggle = dragToggle
        self.exit = exit
        self.nextScreen = nextScreen
        self.previousScreen = previousScreen
        self.digits = digits
        self.help = help
        self.passthrough = passthrough
    }

    public static let `default` = KeyMap(
        activate: KeyPress(.space, [.command, .shift]),
        leftClick: [KeyPress(.return), KeyPress(.m)],
        rightClick: [KeyPress(.period)],
        middleClick: [KeyPress(.comma)],
        clickStay: [KeyPress(.space)],
        doubleClick: [KeyPress(.x)],
        dragToggle: [KeyPress(.v)],
        exit: [KeyPress(.escape)],
        nextScreen: [KeyPress(.tab)],
        previousScreen: [KeyPress(.tab, [.shift])],
        digits: [
            KeyPress(.zero): 0, KeyPress(.one): 1, KeyPress(.two): 2, KeyPress(.three): 3, KeyPress(.four): 4,
            KeyPress(.five): 5, KeyPress(.six): 6, KeyPress(.seven): 7, KeyPress(.eight): 8, KeyPress(.nine): 9,
        ],
        help: [KeyPress(.slash, [.shift])],
        passthrough: [
            KeyPress(.tab, [.command]), KeyPress(.tab, [.command, .shift]), KeyPress(.space, [.command]),
            KeyPress(.upArrow, [.control]), KeyPress(.downArrow, [.control]), KeyPress(.leftArrow, [.control]), KeyPress(.rightArrow, [.control]),
            KeyPress(.three, [.command, .shift]), KeyPress(.four, [.command, .shift]), KeyPress(.five, [.command, .shift]),
        ]
    )

    public func digit(for event: KeyPress) -> Int? {
        digits.first { $0.key.matches(event: event) }?.value
    }

    /// One representative key for a binding, for legends: fewest modifiers, then shortest label.
    public static func label(of keys: some Collection<KeyPress>) -> String {
        keys.min { a, b in
            if a.modifiers.rawValue != b.modifiers.rawValue { return a.modifiers.rawValue < b.modifiers.rawValue }
            return a.label.count < b.label.count || (a.label.count == b.label.count && a.label < b.label)
        }?.label ?? "?"
    }
}
