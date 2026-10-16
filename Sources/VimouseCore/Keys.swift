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
public struct KeyMap: Sendable {
    public var activate: KeyPress
    public var quadrants: [KeyPress: Quadrant]
    public var up: Set<KeyPress>
    public var leftClick: Set<KeyPress>
    public var rightClick: Set<KeyPress>
    public var middleClick: Set<KeyPress>
    public var exit: Set<KeyPress>
    public var nextScreen: Set<KeyPress>
    public var previousScreen: Set<KeyPress>
    /// Direct jump: key -> 0-based screen index.
    public var screens: [KeyPress: Int]

    public init(
        activate: KeyPress,
        quadrants: [KeyPress: Quadrant],
        up: Set<KeyPress>,
        leftClick: Set<KeyPress>,
        rightClick: Set<KeyPress>,
        middleClick: Set<KeyPress>,
        exit: Set<KeyPress>,
        nextScreen: Set<KeyPress> = [],
        previousScreen: Set<KeyPress> = [],
        screens: [KeyPress: Int] = [:]
    ) {
        self.activate = activate
        self.quadrants = quadrants
        self.up = up
        self.leftClick = leftClick
        self.rightClick = rightClick
        self.middleClick = middleClick
        self.exit = exit
        self.nextScreen = nextScreen
        self.previousScreen = previousScreen
        self.screens = screens
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
        leftClick: [KeyPress(.return), KeyPress(.m)],
        rightClick: [KeyPress(.period)],
        middleClick: [KeyPress(.comma)],
        exit: [KeyPress(.escape)],
        nextScreen: [KeyPress(.tab)],
        previousScreen: [KeyPress(.tab, [.shift])],
        screens: [
            KeyPress(.one): 0, KeyPress(.two): 1, KeyPress(.three): 2, KeyPress(.four): 3, KeyPress(.five): 4,
            KeyPress(.six): 5, KeyPress(.seven): 6, KeyPress(.eight): 7, KeyPress(.nine): 8,
        ]
    )

    /// Label shown inside each quadrant. Derived from the ANSI key name for now;
    /// a layout-aware version comes with the config loader.
    public func label(for quadrant: Quadrant) -> String {
        guard let press = quadrants.first(where: { $0.value == quadrant })?.key else { return "?" }
        return KeyMap.ansiNames[press.code] ?? "?"
    }

    static let ansiNames: [KeyCode: String] = [
        .a: "a", .s: "s", .d: "d", .f: "f", .h: "h", .g: "g", .z: "z", .x: "x", .c: "c", .v: "v",
        .b: "b", .q: "q", .w: "w", .e: "e", .r: "r", .y: "y", .t: "t", .o: "o", .u: "u", .i: "i",
        .p: "p", .l: "l", .j: "j", .k: "k", .n: "n", .m: "m", .comma: ",", .period: ".", .slash: "/",
    ]
}
