import VimouseCore

/// Non-linear stepping: a press moves the pointer; each further press the same way
/// moves twice as far (expanding), and from the first reversal on every press moves
/// half as far as the last (refining), so a target is reached by overshooting and
/// homing in, a one-dimensional bisection. A perpendicular direction starts again from
/// the base step. Experimental.
public final class ExpandMode: Mode {
    public struct Settings: ModeSettings, Equatable {
        public var toggle: Set<KeyPress> = [KeyPress(.e)]
        public var base: Double = 8
        public var factor: Double = 2
        public var max: Double = 1024
        public var left: Set<KeyPress> = [KeyPress(.h), KeyPress(.leftArrow)]
        public var right: Set<KeyPress> = [KeyPress(.l), KeyPress(.rightArrow)]
        public var up: Set<KeyPress> = [KeyPress(.k), KeyPress(.upArrow)]
        public var down: Set<KeyPress> = [KeyPress(.j), KeyPress(.downArrow)]
        public init() {}
    }

    public let id = "expand"
    public let name = "EXPAND"
    public let summary = "Expand mode (work in progress, off unless listed in [modes] enabled): each press in a direction doubles the step, the opposite direction halves it."
    public let defaultColour = "#FF6482"
    public let enabledByDefault = false
    public var settings = Settings()
    private var last: (dx: Double, dy: Double, step: Double)?
    private var refining = false

    public init() {}

    public var schema: [ConfigEntry] {
        [
            .init(section: id, key: "toggle", defaultValue: "\"e\"", comment: "Enter or leave Expand mode, e.g. \"e\"."),
            .init(section: id, key: "base", defaultValue: "8", comment: "Pixels of the first press in a direction, e.g. 4, 8, 16."),
            .init(section: id, key: "factor", defaultValue: "2", comment: "Growth per press in the same direction (and shrink when reversing), e.g. 2, 1.5."),
            .init(section: id, key: "max", defaultValue: "1024", comment: "Largest step in pixels, e.g. 512, 1024."),
            .init(section: id, key: "left", defaultValue: "[\"h\", \"left\"]", comment: "Move left, e.g. [\"h\", \"left\"]."),
            .init(section: id, key: "right", defaultValue: "[\"l\", \"right\"]", comment: "Move right, e.g. [\"l\", \"right\"]."),
            .init(section: id, key: "up", defaultValue: "[\"k\", \"up\"]", comment: "Move up, e.g. [\"k\", \"up\"]."),
            .init(section: id, key: "down", defaultValue: "[\"j\", \"down\"]", comment: "Move down, e.g. [\"j\", \"down\"]."),
        ]
    }

    public func parseSettings(_ table: TOMLTable) throws -> ModeSettings {
        let r = ConfigReader(table, section: id)
        var s = Settings()
        if let v = try r.keys("toggle") { s.toggle = v }
        if let v = try r.number("base") { s.base = Swift.max(1, v) }
        if let v = try r.number("factor") { s.factor = Swift.max(1.1, v) }
        if let v = try r.number("max") { s.max = Swift.max(s.base, v) }
        if let v = try r.keys("left") { s.left = v }
        if let v = try r.keys("right") { s.right = v }
        if let v = try r.keys("up") { s.up = v }
        if let v = try r.keys("down") { s.down = v }
        return s
    }

    public func apply(_ s: ModeSettings) {
        if let s = s as? Settings { settings = s }
    }

    public var toggle: Set<KeyPress> { settings.toggle }
    public let symbol = "⤼"

    public func activate(_ ctx: ModeContext) { last = nil; refining = false }
    public func deactivate(_ ctx: ModeContext, reason: LeaveReason) { last = nil; refining = false }

    public func handle(_ key: KeyPress, count: Int?, _ ctx: ModeContext) -> [Effect]? {
        var dir = (dx: 0.0, dy: 0.0)
        if settings.left.has(key) { dir.dx = -1 }
        else if settings.right.has(key) { dir.dx = 1 }
        else if settings.up.has(key) { dir.dy = -1 }
        else if settings.down.has(key) { dir.dy = 1 }
        else { return nil }
        let step: Double
        if let l = last, l.dx == dir.dx, l.dy == dir.dy, !refining {
            step = min(settings.max, l.step * settings.factor)           // expanding
        } else if let l = last, l.dx == -dir.dx, l.dy == -dir.dy {
            refining = true                                              // overshot: home in
            step = max(1, (l.step / settings.factor).rounded())
        } else if let l = last, refining, l.dx == dir.dx, l.dy == dir.dy {
            step = max(1, (l.step / settings.factor).rounded())          // still refining
        } else {
            refining = false                                             // new axis: start over
            step = settings.base
        }
        last = (dir.dx, dir.dy, step)
        let n = Double(count ?? 1)
        ctx.target = ctx.clamped(Point(x: ctx.target.x + dir.dx * step * n, y: ctx.target.y + dir.dy * step * n))
        return [.warp(ctx.target), .redraw]
    }

    public func hints(_ ctx: ModeContext) -> [Hint] {
        let s = settings
        let next = last.map { Int(refining ? max(1, ($0.step / s.factor).rounded()) : min(s.max, $0.step * s.factor)) } ?? Int(s.base)
        return [
            Hint(KeyMap.label(of: s.left) + KeyMap.label(of: s.down) + KeyMap.label(of: s.up) + KeyMap.label(of: s.right), "move, same way: ×\(Int(s.factor)), back: ÷\(Int(s.factor))", "⤼ \(next)px"),
        ]
    }

    public func help(_ ctx: ModeContext) -> [(keys: String, action: String)] {
        func all(_ set: Set<KeyPress>) -> String { set.map(\.label).sorted().joined(separator: " ") }
        let s = settings
        return [
            (all(s.left) + " / " + all(s.right), "move left / right: \(Int(s.base))px, then ×\(Int(s.factor)) per press the same way, ÷\(Int(s.factor)) when reversing"),
            (all(s.up) + " / " + all(s.down), "move up / down, the same way"),
        ]
    }

    public func draw(_ ctx: ModeContext, active: Bool) -> [Drawable] {
        guard active, let l = last else { return [] }
        // Where the next press in the same direction would land.
        let next = refining ? max(1, (l.step / settings.factor).rounded()) : min(settings.max, l.step * settings.factor)
        let p = ctx.clamped(Point(x: ctx.target.x + l.dx * next, y: ctx.target.y + l.dy * next))
        let c = ctx.colour(of: id)
        return [
            .line(ctx.target, p, colour: c, alpha: 0.6, width: 1, dashed: true),
            .ring(p, radius: 5, colour: c, alpha: 0.8, width: 1),
        ]
    }

    public var manual: String {
        let s = Settings()
        func keys(_ set: Set<KeyPress>) -> String { set.map(\.label).sorted().joined(separator: ", ") }
        return "Non-linear stepping. \(keys(s.left)) / \(keys(s.down)) / \(keys(s.up)) / \(keys(s.right)) move the pointer \(Int(s.base)) px; each further press the same way multiplies the step by \(Int(s.factor)), the opposite direction divides it, a perpendicular one starts over. Overshoot, then home in."
    }
}
