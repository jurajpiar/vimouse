import VimouseCore

/// Pixel movement for the final adjustment: a tap moves one step, a hold accelerates
/// (the platform drives it, see `Effect.nudgeStart`), two keys move diagonally,
/// Shift moves one pixel per press.
public final class NudgeMode: Mode {
    public struct Settings: ModeSettings, NudgeTunables, Equatable {
        public var step: Double = 5
        public var speed: Double = 600
        public var acceleration: Double = 0.6
        public var toggle: Set<KeyPress> = [KeyPress(.n)]
        public var left: Set<KeyPress> = [KeyPress(.h), KeyPress(.leftArrow)]
        public var right: Set<KeyPress> = [KeyPress(.l), KeyPress(.rightArrow)]
        public var up: Set<KeyPress> = [KeyPress(.k), KeyPress(.upArrow)]
        public var down: Set<KeyPress> = [KeyPress(.j), KeyPress(.downArrow)]
        public init() {}
    }

    public let id = "nudge"
    public let name = "NUDGE"
    public let summary = "Nudge mode: moving the pointer by a few pixels at a time for the final adjustment."
    public let defaultColour = "#40C8E0"
    public var settings = Settings()
    /// Keys currently held, by key code, with the direction each contributes.
    private var held: [KeyCode: (dx: Double, dy: Double)] = [:]

    public init() {}

    public var schema: [ConfigEntry] {
        [
            .init(section: id, key: "toggle", defaultValue: "\"n\"", comment: "Enter or leave Nudge mode, e.g. \"n\"."),
            .init(section: id, key: "step", defaultValue: "5", comment: "Pixels the pointer moves on a tap; Shift held moves one pixel per repeat; a count multiplies, e.g. 5, 10."),
            .init(section: id, key: "speed", defaultValue: "600", comment: "Full speed while a nudge key is held, in pixels per second, e.g. 300 (careful), 600, 1500 (sweeping)."),
            .init(section: id, key: "acceleration", defaultValue: "0.6", comment: "Seconds from the start of a hold to full speed, e.g. 0.3, 0.6, 1.0."),
            .init(section: id, key: "left", defaultValue: "[\"h\", \"left\"]", comment: "Move the pointer left, e.g. [\"h\", \"left\"]."),
            .init(section: id, key: "right", defaultValue: "[\"l\", \"right\"]", comment: "Move the pointer right, e.g. [\"l\", \"right\"]."),
            .init(section: id, key: "up", defaultValue: "[\"k\", \"up\"]", comment: "Move the pointer up, e.g. [\"k\", \"up\"]."),
            .init(section: id, key: "down", defaultValue: "[\"j\", \"down\"]", comment: "Move the pointer down, e.g. [\"j\", \"down\"]."),
        ]
    }

    public func parseSettings(_ table: TOMLTable) throws -> ModeSettings {
        let r = ConfigReader(table, section: id)
        var s = Settings()
        if let v = try r.number("step") { s.step = max(1, v) }
        if let v = try r.number("speed") { s.speed = max(20, v) }
        if let v = try r.number("acceleration") { s.acceleration = max(0.05, v) }
        if let v = try r.keys("toggle") { s.toggle = v }
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

    public func activate(_ ctx: ModeContext) { held = [:] }
    public func deactivate(_ ctx: ModeContext, reason: LeaveReason) { held = [:] }

    public func handle(_ key: KeyPress, count: Int?, _ ctx: ModeContext) -> [Effect]? {
        let n = Double(count ?? 1)
        let fine = key.modifiers.contains(.shift)
        let base = KeyPress(key.code, key.modifiers.subtracting(.shift))
        func hit(_ set: Set<KeyPress>) -> Bool { set.has(key) || (fine && set.has(base)) }
        var dir = (dx: 0.0, dy: 0.0)
        if hit(settings.left) { dir.dx = -1 }
        else if hit(settings.right) { dir.dx = 1 }
        else if hit(settings.up) { dir.dy = -1 }
        else if hit(settings.down) { dir.dy = 1 }
        else { return nil }
        if fine {
            // One pixel per press (key repeat gives a slow, exact crawl).
            ctx.target = ctx.clamped(Point(x: ctx.target.x + dir.dx * n, y: ctx.target.y + dir.dy * n))
            return [.warp(ctx.target), .redraw]
        }
        held[key.code] = dir
        return [effect(multiplier: n)]
    }

    public func handleRelease(_ key: KeyPress, _ ctx: ModeContext) -> [Effect] {
        guard held.removeValue(forKey: key.code) != nil else { return [] }
        return [held.isEmpty ? .nudgeStop : effect(multiplier: 1)]
    }

    /// Combined direction of the held keys, normalised so a diagonal is no faster.
    private func effect(multiplier: Double) -> Effect {
        var dx = 0.0, dy = 0.0
        for d in held.values { dx += d.dx; dy += d.dy }
        let len = (dx * dx + dy * dy).squareRoot()
        if len > 0 { dx /= len; dy /= len }
        return .nudgeStart(dx: dx, dy: dy, multiplier: multiplier)
    }

    public func hints(_ ctx: ModeContext) -> [(key: String, action: String)] {
        let s = settings
        return [
            (KeyMap.label(of: s.left) + KeyMap.label(of: s.down) + KeyMap.label(of: s.up) + KeyMap.label(of: s.right), "move (hold: faster, two: diagonal)"),
            ("⇧", "1px"),
        ]
    }

    public func help(_ ctx: ModeContext) -> [(keys: String, action: String)] {
        func all(_ set: Set<KeyPress>) -> String { set.map(\.label).sorted().joined(separator: " ") }
        return [
            (all(settings.left) + " / " + all(settings.right), "move left / right \(Int(settings.step))px; hold to accelerate (⇧: 1px, count multiplies)"),
            (all(settings.up) + " / " + all(settings.down), "move up / down; a horizontal and a vertical key together: diagonal"),
        ]
    }

    public var manual: String {
        let s = Settings()
        func keys(_ set: Set<KeyPress>) -> String { set.map(\.label).sorted().joined(separator: ", ") }
        return "Pixel movement for the final adjustment. \(keys(s.left)) / \(keys(s.down)) / \(keys(s.up)) / \(keys(s.right)) move: a tap is one step, a hold accelerates, a horizontal and a vertical key held together move diagonally; Shift held moves one pixel per press."
    }
}
