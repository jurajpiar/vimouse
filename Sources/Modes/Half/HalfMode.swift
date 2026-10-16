import VimouseCore

/// Narrowing down by halves: each key keeps one half of the current rectangle along
/// its own axis (left/right or top/bottom), so a target is reached by a series of
/// one-dimensional choices rather than quadrant picks. Starts from the whole screen.
public final class HalfMode: Mode {
    public struct Settings: ModeSettings, Equatable {
        public var toggle: Set<KeyPress> = [KeyPress(.b)]
        public var halves: [Half: Set<KeyPress>] = [
            .left: [KeyPress(.h), KeyPress(.leftArrow)], .right: [KeyPress(.l), KeyPress(.rightArrow)],
            .top: [KeyPress(.k), KeyPress(.upArrow)], .bottom: [KeyPress(.j), KeyPress(.downArrow)],
        ]
        public var up: Set<KeyPress> = [KeyPress(.delete), KeyPress(.u)]
        public var top: Set<KeyPress> = [KeyPress(.u, [.shift]), KeyPress(.delete, [.shift])]
        public init() {}

        public func half(for event: KeyPress) -> Half? {
            halves.first { $0.value.has(event) }?.key
        }
    }

    public let id = "half"
    public let name = "HALF"
    public let summary = "Half mode (work in progress, off unless listed in [modes] enabled): narrowing down by keeping the left, right, top or bottom half of the rectangle."
    public let enabledByDefault = false
    public let defaultColour = "#64D2FF"
    public var settings = Settings()
    public private(set) var session: BisectSession?

    public init() {}

    public var schema: [ConfigEntry] {
        [
            .init(section: id, key: "toggle", defaultValue: "\"b\"", comment: "Enter or leave Half mode, e.g. \"b\"."),
            .init(section: id, key: "left", defaultValue: "[\"h\", \"left\"]", comment: "Keep the left half of the rectangle, e.g. [\"h\", \"left\"]."),
            .init(section: id, key: "right", defaultValue: "[\"l\", \"right\"]", comment: "Keep the right half, e.g. [\"l\", \"right\"]."),
            .init(section: id, key: "up", defaultValue: "[\"k\", \"up\"]", comment: "Keep the top half, e.g. [\"k\", \"up\"]."),
            .init(section: id, key: "down", defaultValue: "[\"j\", \"down\"]", comment: "Keep the bottom half, e.g. [\"j\", \"down\"]."),
            .init(section: id, key: "back", defaultValue: "[\"backspace\", \"u\"]", comment: "Undo the last halving; a count repeats, e.g. [\"backspace\", \"u\"]."),
            .init(section: id, key: "top", defaultValue: "[\"shift+u\", \"shift+backspace\"]", comment: "Back to the whole screen, e.g. [\"shift+u\", \"shift+backspace\"]."),
        ]
    }

    public func parseSettings(_ table: TOMLTable) throws -> ModeSettings {
        let r = ConfigReader(table, section: id)
        var s = Settings()
        if let v = try r.keys("toggle") { s.toggle = v }
        for (name, h) in [("left", Half.left), ("right", .right), ("up", .top), ("down", .bottom)] {
            if let v = try r.keys(name) { s.halves[h] = v }
        }
        if let v = try r.keys("back") { s.up = v }
        if let v = try r.keys("top") { s.top = v }
        return s
    }

    public func apply(_ s: ModeSettings) {
        if let s = s as? Settings { settings = s }
    }

    public var toggle: Set<KeyPress> { settings.toggle }
    public var acceptsKeyRepeat: Bool { false }
    public var showsDragLine: Bool { true }

    public func activate(_ ctx: ModeContext) {
        if session?.root != ctx.screen { session = BisectSession(root: ctx.screen) }
        ctx.target = session!.current.center
    }

    public func deactivate(_ ctx: ModeContext, reason: LeaveReason) {
        if reason != .switched { session = nil }
    }

    public func screenChanged(_ ctx: ModeContext) {
        session = BisectSession(root: ctx.screen)
    }

    public func dragStarted(_ ctx: ModeContext) {
        session = BisectSession(root: ctx.screen)
    }

    public func handle(_ key: KeyPress, count: Int?, _ ctx: ModeContext) -> [Effect]? {
        guard var s = session else { return nil }
        defer { session = s }
        func go() -> [Effect] { ctx.target = s.current.center; return [.warp(ctx.target), .redraw] }
        if let h = settings.half(for: key) {
            for _ in 0..<(count ?? 1) { s.select(h) }
            return go()
        }
        if settings.top.has(key) {
            guard s.depth > 0 else { return [] }
            s.reset()
            return go()
        }
        if settings.up.has(key) {
            guard s.up() else { return [] }
            for _ in 1..<(count ?? 1) { s.up() }
            return go()
        }
        return nil
    }

    public func hints(_ ctx: ModeContext) -> [(key: String, action: String)] {
        let order: [Half] = [.left, .bottom, .top, .right]
        var h: [(key: String, action: String)] = [(order.map { KeyMap.label(of: settings.halves[$0] ?? []) }.joined(), "halve")]
        if let s = session, s.depth > 0 {
            h.append((KeyMap.label(of: settings.up), "back"))
            h.append((KeyMap.label(of: settings.top), "top"))
        }
        return h
    }

    public func help(_ ctx: ModeContext) -> [(keys: String, action: String)] {
        func all(_ set: Set<KeyPress>) -> String { set.map(\.label).sorted().joined(separator: " ") }
        return [
            ([Half.left, .right, .top, .bottom].map { all(settings.halves[$0] ?? []) }.joined(separator: " / "), "keep the left / right / top / bottom half (count repeats)"),
            (all(settings.up), "undo the last halving (count: several)"),
            (all(settings.top), "back to the whole screen"),
        ]
    }

    public func draw(_ ctx: ModeContext, active: Bool) -> [Drawable] {
        guard active, let s = session else { return [] }
        let c = ctx.colour(of: id)
        var d: [Drawable] = []
        for (i, a) in s.ancestors.enumerated() where i > 0 {
            d.append(.outline(a, colour: c, alpha: 0.25, width: 1))
        }
        let r = s.current
        d.append(.fill(r, colour: c, alpha: 0.08))
        d.append(.outline(r, colour: c, alpha: 1, width: 2))
        // The two split lines, and each half's key at the middle of its edge.
        d.append(.line(Point(x: r.midX, y: r.y), Point(x: r.midX, y: r.maxY), colour: c, alpha: 0.6, width: 1, dashed: true))
        d.append(.line(Point(x: r.x, y: r.midY), Point(x: r.maxX, y: r.midY), colour: c, alpha: 0.6, width: 1, dashed: true))
        let tag = min(r.width, r.height) * 0.25
        let spots: [(Half, Rect)] = [
            (.left, Rect(x: r.x, y: r.midY - tag / 2, width: tag, height: tag)),
            (.right, Rect(x: r.maxX - tag, y: r.midY - tag / 2, width: tag, height: tag)),
            (.top, Rect(x: r.midX - tag / 2, y: r.y, width: tag, height: tag)),
            (.bottom, Rect(x: r.midX - tag / 2, y: r.maxY - tag, width: tag, height: tag)),
        ]
        for (h, spot) in spots {
            d.append(.label(KeyMap.label(of: settings.halves[h] ?? []), in: spot, colour: c, alpha: 0.85))
        }
        return d
    }

    public var manual: String {
        let s = Settings()
        func keys(_ set: Set<KeyPress>) -> String { set.map(\.label).sorted().joined(separator: ", ") }
        return "Narrowing down by halves, starting from the whole screen: \([Half.left, .right, .top, .bottom].map { keys(s.halves[$0] ?? []) }.joined(separator: " / ")) keep the left / right / top / bottom half of the current rectangle; \(keys(s.up)) undoes the last halving; \(keys(s.top)) goes back to the whole screen."
    }
}
