import VimouseCore

/// Quadrant navigation: the screen is divided into four, one key picks a quadrant,
/// which is divided again, until the pointer is on the target. Optionally snaps each
/// step to the nearest clickable UI element (via `Services.snap`).
public final class PointerMode: Mode {
    public struct Settings: ModeSettings, Equatable {
        public var quadrants: [KeyPress: Quadrant] = [
            KeyPress(.i): .topLeft, KeyPress(.o): .topRight, KeyPress(.j): .bottomLeft, KeyPress(.k): .bottomRight,
        ]
        public var up: Set<KeyPress> = [KeyPress(.delete), KeyPress(.u)]
        public var top: Set<KeyPress> = [KeyPress(.u, [.shift]), KeyPress(.delete, [.shift])]
        public var snapToggle: Set<KeyPress> = [KeyPress(.a)]
        public var snap = true
        /// Whether starting a drag restarts the quadrant search from the whole screen.
        public var dragRestart = true
        public init() {}

        public func quadrant(for event: KeyPress) -> Quadrant? {
            quadrants.first { $0.key.matches(event: event) }?.value
        }

        /// Label shown inside each quadrant.
        public func label(for quadrant: Quadrant) -> String {
            KeyMap.label(of: quadrants.filter { $0.value == quadrant }.map(\.key))
        }
    }

    public let id = "pointer"
    public let name = "POINTER"
    public let summary = "Pointer mode: narrowing down on the target by picking quadrants."
    public let defaultColour = "#0A84FF"
    public var settings = Settings()
    /// Snap the pointer to UI elements this session (needs `Services.snap`). Toggled with a key.
    public private(set) var snapping = true
    public private(set) var session: BisectSession?

    public init() {}

    public var schema: [ConfigEntry] {
        [
            .init(section: id, key: "top_left", defaultValue: "\"i\"", comment: "Pick the top-left quadrant, e.g. \"i\", \"up\"."),
            .init(section: id, key: "top_right", defaultValue: "\"o\"", comment: "Pick the top-right quadrant, e.g. \"o\", \"right\"."),
            .init(section: id, key: "bottom_left", defaultValue: "\"j\"", comment: "Pick the bottom-left quadrant, e.g. \"j\", \"left\"."),
            .init(section: id, key: "bottom_right", defaultValue: "\"k\"", comment: "Pick the bottom-right quadrant, e.g. \"k\", \"down\"."),
            .init(section: id, key: "up", defaultValue: "[\"backspace\", \"u\"]", comment: "Go up one level in the quadrant descent; a count repeats, e.g. [\"backspace\", \"u\"]."),
            .init(section: id, key: "top", defaultValue: "[\"shift+u\", \"shift+backspace\"]", comment: "Restart the quadrant search from the whole screen, e.g. [\"shift+u\", \"shift+backspace\"]."),
            .init(section: id, key: "snap", defaultValue: "true", comment: "Snap the pointer to the nearest clickable element in the chosen rectangle (read from the accessibility tree): true or false."),
            .init(section: id, key: "snap_toggle", defaultValue: "\"a\"", comment: "Toggle snapping to UI elements for this session, e.g. \"a\"."),
            .init(section: id, key: "drag_restart", defaultValue: "true", comment: "When a drag starts, restart the quadrant search from the whole screen (good for moving items far; set false to keep extending a selection from where you are): true or false."),
        ]
    }

    public func parseSettings(_ table: TOMLTable) throws -> ModeSettings {
        let r = ConfigReader(table, section: id)
        var s = Settings()
        var quadrants: [KeyPress: Quadrant] = [:]
        for (name, q) in [("top_left", Quadrant.topLeft), ("top_right", .topRight), ("bottom_left", .bottomLeft), ("bottom_right", .bottomRight)] {
            if let p = try r.one(name) { quadrants[p] = q }
        }
        if !quadrants.isEmpty {
            guard quadrants.count == 4 else { throw Config.ParseError(description: "[\(id)]: all four quadrant keys must be set and distinct") }
            s.quadrants = quadrants
        }
        if let v = try r.keys("up") { s.up = v }
        if let v = try r.keys("top") { s.top = v }
        if let v = try r.keys("snap_toggle") { s.snapToggle = v }
        if let v = try r.bool("snap") { s.snap = v }
        if let v = try r.bool("drag_restart") { s.dragRestart = v }
        return s
    }

    public func apply(_ s: ModeSettings) {
        guard let s = s as? Settings else { return }
        settings = s
        if session == nil { snapping = s.snap }
    }

    public let toggle: Set<KeyPress> = []
    public var acceptsKeyRepeat: Bool { false }
    public var showsDragLine: Bool { true }

    public func activate(_ ctx: ModeContext) {
        if session?.root != ctx.screen { session = BisectSession(root: ctx.screen) }
    }

    public func deactivate(_ ctx: ModeContext, reason: LeaveReason) {
        guard reason != .switched else { return } // another mode: keep the descent for when we return
        session = nil
        snapping = settings.snap
    }

    public func screenChanged(_ ctx: ModeContext) {
        session = BisectSession(root: ctx.screen)
    }

    public func dragStarted(_ ctx: ModeContext) {
        // The task is now "where to drop": restart the search from the whole screen,
        // pointer staying where it is.
        if settings.dragRestart { session = BisectSession(root: ctx.screen) }
    }

    /// The point to send the pointer to for a rectangle: a snapped element if enabled and
    /// available, otherwise the centre.
    private func aim(_ r: Rect, _ ctx: ModeContext) -> Point {
        if snapping, let p = ctx.services.snap?.snapPoint(in: r), r.contains(p) {
            ctx.target = p
        } else {
            ctx.target = r.center
        }
        return ctx.target
    }

    public func handle(_ key: KeyPress, count: Int?, _ ctx: ModeContext) -> [Effect]? {
        guard var s = session else { return nil }
        defer { session = s }
        if let q = settings.quadrant(for: key) {
            for _ in 0..<(count ?? 1) { s.select(q) }
            return [.warp(aim(s.current, ctx)), .redraw]
        }
        if settings.top.has(key) {
            guard s.depth > 0 else { return [] }
            s.reset()
            return [.warp(aim(s.current, ctx)), .redraw]
        }
        if settings.up.has(key) {
            guard s.up() else { return [] }
            for _ in 1..<(count ?? 1) { s.up() }
            return [.warp(aim(s.current, ctx)), .redraw]
        }
        if settings.snapToggle.has(key) {
            snapping.toggle()
            return [.warp(aim(s.current, ctx)), .redraw]
        }
        return nil
    }

    public func hints(_ ctx: ModeContext) -> [(key: String, action: String)] {
        let quads = [Quadrant.topLeft, .topRight, .bottomLeft, .bottomRight].map { settings.label(for: $0) }.joined()
        var h: [(key: String, action: String)] = [(quads, "pick")]
        if let s = session, s.depth > 0 {
            h.append((KeyMap.label(of: settings.up), "up"))
            h.append((KeyMap.label(of: settings.top), "top"))
        }
        if ctx.services.snap != nil { h.append((KeyMap.label(of: settings.snapToggle), snapping ? "snap on" : "snap off")) }
        return h
    }

    public func help(_ ctx: ModeContext) -> [(keys: String, action: String)] {
        func all(_ set: Set<KeyPress>) -> String { set.map(\.label).sorted().joined(separator: " ") }
        return [
            ([Quadrant.topLeft, .topRight, .bottomLeft, .bottomRight].map { settings.label(for: $0) }.joined(separator: " "), "pick top-left, top-right, bottom-left, bottom-right quadrant"),
            (all(settings.up), "up one level (count: several)"),
            (all(settings.top), "back to the whole screen"),
            (all(settings.snapToggle), "toggle snapping to UI elements"),
        ]
    }

    public func draw(_ ctx: ModeContext, active: Bool) -> [Drawable] {
        guard active, let s = session else { return [] }
        let c = ctx.colour(of: id)
        var d: [Drawable] = []
        // Ancestors: faint outlines so the descent stays visible (the root is the screen).
        for (i, a) in s.ancestors.enumerated() where i > 0 {
            d.append(.outline(a, colour: c, alpha: 0.25, width: 1))
        }
        // Current rectangle: light fill, strong outline.
        d.append(.fill(s.current, colour: c, alpha: 0.08))
        d.append(.outline(s.current, colour: c, alpha: 1, width: 2))
        // Next choices: the four quadrants, each with its key in the middle.
        for (q, r) in s.current.subdivided() {
            d.append(.outline(r, colour: c, alpha: 0.6, width: 1))
            d.append(.label(settings.label(for: q), in: r, colour: c, alpha: 0.85))
        }
        // Snap target, when it is not simply the centre.
        if snapping, ctx.target != s.current.center {
            d.append(.ring(ctx.target, radius: 7, colour: ctx.colours.snap, alpha: 1, width: 2))
        }
        return d
    }

    public var manual: String {
        let s = Settings()
        func keys(_ set: Set<KeyPress>) -> String { set.map(\.label).sorted().joined(separator: ", ") }
        return "Quadrant navigation. Keys: \([Quadrant.topLeft, .topRight, .bottomLeft, .bottomRight].map { s.label(for: $0) }.joined(separator: " ")) pick a quadrant; \(keys(s.up)) up one level; \(keys(s.top)) back to the whole screen; \(keys(s.snapToggle)) toggles snapping to UI elements."
    }
}
