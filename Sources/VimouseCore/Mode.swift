/// The plugin interface. A mode is a self-contained way of driving the pointer: it owns
/// its bindings and settings (one `[<id>]` section of config.toml), handles the keys the
/// engine passes it, and describes what to draw. It never touches the platform: keys come
/// in, `Effect`s and `Drawable`s go out, so a mode builds and tests anywhere.
///
/// The engine keeps what is shared: activation, the count prefix, exit, clicks, drag,
/// display switching, mode toggles, the status strip and the help panel.
public protocol Mode: AnyObject {
    /// Config section and the name in `[hotkey] activate_mode`, `[modes] enabled`; lower case.
    var id: String { get }
    /// Shown in the status strip and as the help group title, e.g. "POINTER".
    var name: String { get }
    /// One line for the config section header and the manual.
    var summary: String { get }
    /// Default "#RRGGBB" for `[colours.modes] <id>`.
    var defaultColour: String { get }
    /// Settings of the `[<id>]` section, in file order, with comments and defaults.
    var schema: [ConfigEntry] { get }
    /// Listed in the default `[modes] enabled`. False for an experimental mode the user opts into.
    var enabledByDefault: Bool { get }

    /// Parse the section into a settings value, throwing `Config.ParseError` with the
    /// `[section] key: ...` wording on a bad value. Called when the file is read.
    func parseSettings(_ table: TOMLTable) throws -> ModeSettings
    /// Adopt settings parsed earlier. Called on every (re)load, at any time.
    func apply(_ settings: ModeSettings)

    /// Keys that enter this mode from any other and return to the default mode from it.
    var toggle: Set<KeyPress> { get }
    /// Whether the platform should pass key repeats (a held key) to `handle`.
    var acceptsKeyRepeat: Bool { get }
    /// The mode sees every key before the shared bindings (clicks, drag, mode toggles),
    /// except exit and the count digits; for modes that take typed letters. Return nil
    /// from `handle` to let the shared binding run.
    var capturesKeys: Bool { get }
    /// Whether the dashed line from the drag origin to the pointer is drawn while dragging
    /// (off where it would sit on the text being selected).
    var showsDragLine: Bool { get }
    /// True when the mode draws something while no mode is active (a persistent band).
    var drawsWhileIdle: Bool { get }

    /// The mode became active (from idle or another mode). `ctx.target` is the pointer.
    func activate(_ ctx: ModeContext)
    /// The mode stopped being active. `.switched`: another mode was chosen explicitly
    /// (keep what a return would want: a descent, a band). `.toggledOff`: its own toggle
    /// or a hand-back. `.exited`: the engine went idle.
    func deactivate(_ ctx: ModeContext, reason: LeaveReason)
    /// The session moved to another display; `ctx.target` is already at its centre.
    func screenChanged(_ ctx: ModeContext)
    /// A drag started with this mode active.
    func dragStarted(_ ctx: ModeContext)

    /// A key pressed while this mode is active and no shared binding claimed it.
    /// `count` is the vi-style prefix (nil when none). Return nil when the key is not
    /// one of yours; the engine then swallows it silently.
    func handle(_ key: KeyPress, count: Int?, _ ctx: ModeContext) -> [Effect]?
    /// A key released while this mode is active.
    func handleRelease(_ key: KeyPress, _ ctx: ModeContext) -> [Effect]
    /// A key pressed in any mode, before the active mode sees it (for a binding that
    /// must work everywhere, such as removing a band). Return nil to pass.
    func handleAnywhere(_ key: KeyPress, count: Int?, _ ctx: ModeContext) -> [Effect]?

    /// Status strip entries while active, bindings first.
    func hints(_ ctx: ModeContext) -> [Hint]
    /// One glyph standing for the mode in the strip (its toggle's action), e.g. "⊞".
    var symbol: String { get }
    /// Help panel rows: ("keys", "what it does").
    func help(_ ctx: ModeContext) -> [(keys: String, action: String)]
    /// What to draw. Called for the active mode, and for idle modes that `drawsWhileIdle`.
    func draw(_ ctx: ModeContext, active: Bool) -> [Drawable]
    /// One paragraph for the manual's MODES section (roff escaped by the caller).
    var manual: String { get }
}

/// Why a mode stopped being active.
public enum LeaveReason: Equatable, Sendable {
    case switched, toggledOff, exited
}

/// A mode's parsed settings. Each mode defines its own Equatable struct; equality is
/// type-erased so a whole `Config` can be compared (the template-reproduces-defaults test).
public protocol ModeSettings {
    func isEqual(to other: ModeSettings) -> Bool
}

public extension ModeSettings where Self: Equatable {
    func isEqual(to other: ModeSettings) -> Bool { (other as? Self) == self }
}

/// One status strip entry: the key, what it does in words, and a glyph for it when
/// one is clear enough (the strip shows glyphs by default, words on request).
public struct Hint: Equatable, Sendable {
    public var key: String
    public var action: String
    public var symbol: String?
    /// Shown greyed: the key is bound but cannot do anything just now (no text under
    /// the band to follow, say).
    public var unavailable = false
    public init(_ key: String, _ action: String, _ symbol: String? = nil, unavailable: Bool = false) {
        self.key = key
        self.action = action
        self.symbol = symbol
        self.unavailable = unavailable
    }
}

public extension Mode {
    var enabledByDefault: Bool { true }
    var capturesKeys: Bool { false }
    var symbol: String { String(name.prefix(1)) }
    var acceptsKeyRepeat: Bool { true }
    var showsDragLine: Bool { false }
    var drawsWhileIdle: Bool { false }
    func activate(_ ctx: ModeContext) {}
    func deactivate(_ ctx: ModeContext, reason: LeaveReason) {}
    func screenChanged(_ ctx: ModeContext) {}
    func dragStarted(_ ctx: ModeContext) {}
    func handleRelease(_ key: KeyPress, _ ctx: ModeContext) -> [Effect] { [] }
    func handleAnywhere(_ key: KeyPress, count: Int?, _ ctx: ModeContext) -> [Effect]? { nil }
    func draw(_ ctx: ModeContext, active: Bool) -> [Drawable] { [] }
    var manual: String { summary }
}

/// Platform services a mode may use. All optional: a mode must work without them.
public final class Services {
    public weak var snap: SnapProvider?
    public weak var lines: LineProvider?
    public weak var elements: ElementProvider?
    public init() {}
}

/// Supplies the frames of clickable UI elements on a display (from the accessibility
/// tree), for hint labels.
public protocol ElementProvider: AnyObject {
    func elements(on screen: Rect) -> [Rect]
}

/// Supplies a better pointer target inside a rectangle (for example the centre of
/// the nearest clickable UI element). Return nil to use the rectangle's centre.
public protocol SnapProvider: AnyObject {
    /// Called once when a session starts on a screen; a chance to cache.
    func prepare(screen: Rect)
    func snapPoint(in rect: Rect) -> Point?
}

/// Supplies the bounds of lines of text (from the accessibility API) so a reading band
/// can follow real lines instead of a fixed step.
public protocol LineProvider: AnyObject {
    /// The line containing (x, y) when `direction` is 0, the first line below it when 1,
    /// the first line above it when -1. nil when no text is found there.
    func textLine(at x: Double, y: Double, direction: Int, on screen: Rect) -> Rect?
    /// The frame of the window under (x, y), if any.
    func window(at x: Double, y: Double) -> Rect?
}

public extension LineProvider {
    func window(at x: Double, y: Double) -> Rect? { nil }
}

/// What the engine shares with modes: the session's geometry, the pointer target, the
/// drag state, services and colours. Owned by the engine; modes read it and set `target`.
public final class ModeContext {
    /// All displays (CG coordinates, top-left origin) and which one the session is on.
    public internal(set) var screens: [Rect] = []
    public internal(set) var screenIndex: Int = 0
    public var screen: Rect { screens[screenIndex] }
    /// Where the pointer is (or was last sent). A mode moves the pointer by setting this
    /// and returning `.warp`, or through the platform (held nudge), which reports back.
    public var target: Point = Point(x: 0, y: 0)
    /// Left button held by the drag toggle, and where it went down.
    public internal(set) var dragging = false
    public internal(set) var dragOrigin: Point?
    /// Id of the active mode; nil when idle.
    public internal(set) var activeMode: String?
    public let services = Services()
    /// "#RRGGBB" for a mode id (its configured colour) or a marker ("drag", "snap").
    public internal(set) var colours = Colours()

    public func colour(of modeID: String) -> String { colours.mode(modeID) }

    /// Ask the engine to switch mode once the current key is handled: an id, or nil for
    /// the previous mode (the default when there is none).
    public func switchMode(to id: String?) { requestedMode = .some(id) }
    var requestedMode: String?? = nil
    /// Ask the engine to leave altogether once the current key is handled.
    public func requestExit() { exitRequested = true }
    var exitRequested = false

    /// `target` clamped to the current display.
    public func clamped(_ p: Point) -> Point {
        let s = screen
        return Point(x: min(max(p.x, s.x), s.maxX - 1), y: min(max(p.y, s.y), s.maxY - 1))
    }
}

/// Reads one section of config.toml with the error wording the rest of the file uses.
public struct ConfigReader {
    public let table: TOMLTable
    public let section: String

    public init(_ table: TOMLTable, section: String) {
        self.table = table
        self.section = section
    }

    public func fail(_ key: String, _ message: String) -> Config.ParseError {
        Config.ParseError(description: "[\(section)] \(key): \(message)")
    }

    public func value(_ key: String) -> TOMLValue? { table[section]?[key] }

    public func keys(_ key: String) throws -> Set<KeyPress>? {
        guard let v = value(key) else { return nil }
        guard let specs = v.strings else { throw fail(key, "expected a key name or list of key names") }
        var out = Set<KeyPress>()
        for spec in specs {
            guard let p = KeyPress.parse(spec) else { throw fail(key, "unknown key \"\(spec)\"") }
            out.insert(p)
        }
        return out
    }

    public func one(_ key: String) throws -> KeyPress? {
        guard let set = try keys(key) else { return nil }
        guard set.count == 1, let p = set.first else { throw fail(key, "exactly one key expected") }
        return p
    }

    public func number(_ key: String) throws -> Double? {
        guard let v = value(key) else { return nil }
        guard let d = v.double else { throw fail(key, "expected a number") }
        return d
    }

    public func bool(_ key: String) throws -> Bool? {
        guard let v = value(key) else { return nil }
        guard let b = v.bool else { throw fail(key, "expected true or false") }
        return b
    }

    public func string(_ key: String) throws -> String? {
        guard let v = value(key) else { return nil }
        guard let s = v.string else { throw fail(key, "expected a string") }
        return s
    }
}

/// Drawing primitives, in CG coordinates spanning all displays. Colours are "#RRGGBB";
/// a mode uses `ctx.colour(of: id)` for its own and `ctx.colours.snap` etc. for markers.
public enum Drawable: Equatable, Sendable {
    case fill(Rect, colour: String, alpha: Double)
    case outline(Rect, colour: String, alpha: Double, width: Double)
    case ring(Point, radius: Double, colour: String, alpha: Double, width: Double)
    case dot(Point, radius: Double, colour: String, alpha: Double)
    case line(Point, Point, colour: String, alpha: Double, width: Double, dashed: Bool)
    case crosshair(Point, size: Double, colour: String, alpha: Double, width: Double)
    /// Text centred in a rectangle, sized to it.
    case label(String, in: Rect, colour: String, alpha: Double)
    /// Darken an area of a display except one rectangle.
    case dim(screen: Int, area: Rect, except: Rect, alpha: Double)
}

/// Everything the overlay draws, assembled by the engine.
public struct Scene: Equatable {
    public var screens: [Rect]
    public var activeScreen: Int
    /// nil when no mode is active (only idle drawings, such as a band, are shown).
    public var modeName: String?
    public var modeColour: String
    public var dragging: Bool
    public var pendingCount: Int?
    /// Where the pointer is; the status strip keeps away from it.
    public var focus: Point
    public var hints: [Hint]
    /// Show each hint's glyph instead of its words when it has one.
    public var legendSymbols: Bool
    public var help: [HelpGroup]?
    public var drawables: [Drawable]
    public var colours: Colours

    public struct HelpRow: Equatable { public var keys: String; public var action: String }
    public struct HelpGroup: Equatable { public var title: String; public var rows: [HelpRow] }
}

/// Tunables the platform's scroll driver reads from whichever mode provides them
/// (the standard Scroll mode's settings conform).
public protocol ScrollTunables {
    var step: Double { get }
    var speed: Double { get }
    var acceleration: Double { get }
    var flick: Double { get }
    var friction: Double { get }
    var momentum: Bool { get }
    var smooth: Bool { get }
    var flickDoubleTapEnabled: Bool { get }
    var flickWith: Modifiers? { get }
}

/// Tunables the platform's nudge driver reads (the standard Nudge mode's settings conform).
public protocol NudgeTunables {
    var step: Double { get }
    var speed: Double { get }
    var acceleration: Double { get }
}
