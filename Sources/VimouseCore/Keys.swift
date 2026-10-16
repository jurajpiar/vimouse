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

public struct Modifiers: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let shift = Modifiers(rawValue: 1 << 0)
    public static let control = Modifiers(rawValue: 1 << 1)
    public static let option = Modifiers(rawValue: 1 << 2)
    public static let command = Modifiers(rawValue: 1 << 3)
}

public struct KeyPress: Hashable, Sendable {
    public var code: KeyCode
    public var modifiers: Modifiers

    public init(_ code: KeyCode, _ modifiers: Modifiers = []) {
        self.code = code
        self.modifiers = modifiers
    }
}

/// Bindings for Pointer mode. Will be loaded from config.toml later; the
/// defaults match docs/PLAN.md.
public struct KeyMap: Sendable, Equatable {
    public var activate: KeyPress
    /// A modifier key that enters Pointer mode while held (quasi-mode); nil when unused.
    public var hold: KeyCode?
    public var quadrants: [KeyPress: Quadrant]
    public var up: Set<KeyPress>
    /// Back to the whole screen (root of the descent).
    public var top: Set<KeyPress>
    public var leftClick: Set<KeyPress>
    public var rightClick: Set<KeyPress>
    public var middleClick: Set<KeyPress>
    public var exit: Set<KeyPress>
    public var nextScreen: Set<KeyPress>
    public var previousScreen: Set<KeyPress>
    /// Count prefix digits (vi style): key -> digit value.
    public var digits: [KeyPress: Int]
    public var clickStay: Set<KeyPress>
    public var doubleClick: Set<KeyPress>
    public var dragToggle: Set<KeyPress>
    public var scrollToggle: Set<KeyPress>
    public var scrollDown: Set<KeyPress>
    public var scrollUp: Set<KeyPress>
    public var scrollLeft: Set<KeyPress>
    public var scrollRight: Set<KeyPress>
    public var scrollHalfDown: Set<KeyPress>
    public var scrollHalfUp: Set<KeyPress>
    public var snapToggle: Set<KeyPress>
    public var rulerToggle: Set<KeyPress>
    public var rulerRemove: Set<KeyPress>
    public var rulerDown: Set<KeyPress>
    public var rulerUp: Set<KeyPress>
    public var rulerGrow: Set<KeyPress>
    public var rulerShrink: Set<KeyPress>
    public var nudgeToggle: Set<KeyPress>
    public var nudgeLeft: Set<KeyPress>
    public var nudgeRight: Set<KeyPress>
    public var nudgeUp: Set<KeyPress>
    public var nudgeDown: Set<KeyPress>
    public var help: Set<KeyPress>

    public init(
        activate: KeyPress,
        quadrants: [KeyPress: Quadrant],
        up: Set<KeyPress>,
        top: Set<KeyPress> = [],
        leftClick: Set<KeyPress>,
        rightClick: Set<KeyPress>,
        middleClick: Set<KeyPress>,
        exit: Set<KeyPress>,
        nextScreen: Set<KeyPress> = [],
        previousScreen: Set<KeyPress> = [],
        digits: [KeyPress: Int] = [:],
        clickStay: Set<KeyPress> = [],
        doubleClick: Set<KeyPress> = [],
        dragToggle: Set<KeyPress> = [],
        scrollToggle: Set<KeyPress> = [],
        scrollDown: Set<KeyPress> = [],
        scrollUp: Set<KeyPress> = [],
        scrollLeft: Set<KeyPress> = [],
        scrollRight: Set<KeyPress> = [],
        scrollHalfDown: Set<KeyPress> = [],
        scrollHalfUp: Set<KeyPress> = [],
        snapToggle: Set<KeyPress> = [],
        rulerToggle: Set<KeyPress> = [],
        rulerRemove: Set<KeyPress> = [],
        rulerDown: Set<KeyPress> = [],
        rulerUp: Set<KeyPress> = [],
        rulerGrow: Set<KeyPress> = [],
        rulerShrink: Set<KeyPress> = [],
        nudgeToggle: Set<KeyPress> = [],
        nudgeLeft: Set<KeyPress> = [],
        nudgeRight: Set<KeyPress> = [],
        nudgeUp: Set<KeyPress> = [],
        nudgeDown: Set<KeyPress> = [],
        help: Set<KeyPress> = []
    ) {
        self.activate = activate
        self.quadrants = quadrants
        self.up = up
        self.top = top
        self.leftClick = leftClick
        self.rightClick = rightClick
        self.middleClick = middleClick
        self.exit = exit
        self.nextScreen = nextScreen
        self.previousScreen = previousScreen
        self.digits = digits
        self.clickStay = clickStay
        self.doubleClick = doubleClick
        self.dragToggle = dragToggle
        self.scrollToggle = scrollToggle
        self.scrollDown = scrollDown
        self.scrollUp = scrollUp
        self.scrollLeft = scrollLeft
        self.scrollRight = scrollRight
        self.scrollHalfDown = scrollHalfDown
        self.scrollHalfUp = scrollHalfUp
        self.snapToggle = snapToggle
        self.rulerToggle = rulerToggle
        self.rulerRemove = rulerRemove
        self.rulerDown = rulerDown
        self.rulerUp = rulerUp
        self.rulerGrow = rulerGrow
        self.rulerShrink = rulerShrink
        self.nudgeToggle = nudgeToggle
        self.nudgeLeft = nudgeLeft
        self.nudgeRight = nudgeRight
        self.nudgeUp = nudgeUp
        self.nudgeDown = nudgeDown
        self.help = help
    }

    public static let `default` = KeyMap(
        activate: KeyPress(.space, [.command, .shift]),
        quadrants: [
            KeyPress(.i): .topLeft,
            KeyPress(.o): .topRight,
            KeyPress(.j): .bottomLeft,
            KeyPress(.k): .bottomRight,
        ],
        up: [KeyPress(.delete), KeyPress(.u)],
        top: [KeyPress(.u, [.shift]), KeyPress(.delete, [.shift])],
        leftClick: [KeyPress(.return), KeyPress(.m)],
        rightClick: [KeyPress(.period)],
        middleClick: [KeyPress(.comma)],
        exit: [KeyPress(.escape)],
        nextScreen: [KeyPress(.tab)],
        previousScreen: [KeyPress(.tab, [.shift])],
        digits: [
            KeyPress(.zero): 0, KeyPress(.one): 1, KeyPress(.two): 2, KeyPress(.three): 3, KeyPress(.four): 4,
            KeyPress(.five): 5, KeyPress(.six): 6, KeyPress(.seven): 7, KeyPress(.eight): 8, KeyPress(.nine): 9,
        ],
        clickStay: [KeyPress(.space)],
        doubleClick: [KeyPress(.x)],
        dragToggle: [KeyPress(.v)],
        scrollToggle: [KeyPress(.s)],
        scrollDown: [KeyPress(.j)],
        scrollUp: [KeyPress(.k)],
        scrollLeft: [KeyPress(.h)],
        scrollRight: [KeyPress(.l)],
        scrollHalfDown: [KeyPress(.d)],
        scrollHalfUp: [KeyPress(.u)],
        snapToggle: [KeyPress(.a)],
        rulerToggle: [KeyPress(.r)],
        rulerRemove: [KeyPress(.r, [.shift])],
        rulerDown: [KeyPress(.j)],
        rulerUp: [KeyPress(.k)],
        rulerGrow: [KeyPress(.rightBracket)],
        rulerShrink: [KeyPress(.leftBracket)],
        nudgeToggle: [KeyPress(.n)],
        nudgeLeft: [KeyPress(.h), KeyPress(.leftArrow)],
        nudgeRight: [KeyPress(.l), KeyPress(.rightArrow)],
        nudgeUp: [KeyPress(.k), KeyPress(.upArrow)],
        nudgeDown: [KeyPress(.j), KeyPress(.downArrow)],
        help: [KeyPress(.slash, [.shift])]
    )

    /// Label shown inside each quadrant.
    public func label(for quadrant: Quadrant) -> String {
        KeyMap.label(of: quadrants.filter { $0.value == quadrant }.map(\.key))
    }

    /// One representative key for a binding, for legends: fewest modifiers, then shortest label.
    public static func label(of keys: some Collection<KeyPress>) -> String {
        keys.min { a, b in
            if a.modifiers.rawValue != b.modifiers.rawValue { return a.modifiers.rawValue < b.modifiers.rawValue }
            return a.label.count < b.label.count || (a.label.count == b.label.count && a.label < b.label)
        }?.label ?? "?"
    }
}
