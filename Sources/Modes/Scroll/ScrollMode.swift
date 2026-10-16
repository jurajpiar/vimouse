import VimouseCore

/// Scrolls the content under the pointer. The platform turns `scrollStart`/`scrollStop`
/// into trackpad-like gestures (tap, accelerate, coast, flick, brake); the settings for
/// that live here so the file has one [scroll] section.
public final class ScrollMode: Mode {
    public struct Settings: ModeSettings, ScrollTunables, Equatable {
        public var step: Double = 60
        public var speed: Double = 1500
        public var acceleration: Double = 0.5
        public var flick: Double = 4000
        /// Double tap of a scroll key flicks: nil = auto (only when no flick modifier is set).
        public var flickDoubleTap: Bool? = nil
        /// Modifiers that turn a scroll key into a flick; nil for none.
        public var flickWith: Modifiers? = nil
        public var friction: Double = 0.85
        public var momentum = true
        public var smooth = true
        public var toggle: Set<KeyPress> = [KeyPress(.s)]
        public var down: Set<KeyPress> = [KeyPress(.j)]
        public var up: Set<KeyPress> = [KeyPress(.k)]
        public var left: Set<KeyPress> = [KeyPress(.h)]
        public var right: Set<KeyPress> = [KeyPress(.l)]
        public var halfDown: Set<KeyPress> = [KeyPress(.d)]
        public var halfUp: Set<KeyPress> = [KeyPress(.u)]
        public init() {}

        /// The effective double-tap setting.
        public var flickDoubleTapEnabled: Bool { flickDoubleTap ?? (flickWith == nil) }
    }

    public let id = "scroll"
    public let name = "SCROLL"
    public let summary = "Scroll mode: scrolling the content under the pointer with the keyboard."
    public let defaultColour = "#FF9F0A"
    public var settings = Settings()

    public init() {}

    public var schema: [ConfigEntry] {
        [
            .init(section: id, key: "toggle", defaultValue: "\"s\"", comment: "Enter or leave Scroll mode, e.g. \"s\"."),
            .init(section: id, key: "step", defaultValue: "60", comment: "Pixels scrolled by a quick tap; a count multiplies (45j). Try 20 for line-by-line reading, 60 to 120 for browsing."),
            .init(section: id, key: "speed", defaultValue: "1500", comment: "Full speed while a scroll key is held, in pixels per second, e.g. 800 (calm), 1500, 3000 (fast)."),
            .init(section: id, key: "acceleration", defaultValue: "0.5", comment: "Seconds from the start of a hold to full speed, e.g. 0.3, 0.5, 1.0."),
            .init(section: id, key: "flick", defaultValue: "4000", comment: "Double-tap a scroll key to flick: the page launches at this speed in pixels per second and coasts. 0 disables; try 2500 (gentle), 4000, 8000."),
            .init(section: id, key: "flick_double_tap", defaultValue: "\"auto\"", comment: "Double-tapping a scroll key flicks: \"auto\" (only while flick_with is empty), true or false."),
            .init(section: id, key: "flick_with", defaultValue: "\"\"", comment: "Modifiers that make a single press of a scroll key a flick, e.g. \"alt\" (alt+j flicks down), \"cmd+shift\"; \"\" for none."),
            .init(section: id, key: "friction", defaultValue: "0.85", comment: "How fast a coast slows: fraction of speed lost per second, 0.01 (glides for ages) to 0.99 (stops at once); 0.7 long, 0.85 default, 0.95 short."),
            .init(section: id, key: "momentum", defaultValue: "true", comment: "Coast after releasing a held key, like a trackpad flick: true or false."),
            .init(section: id, key: "smooth", defaultValue: "true", comment: "Send trackpad-style continuous scroll events (smooth, apps animate); false sends mouse-wheel steps."),
            .init(section: id, key: "down", defaultValue: "\"j\"", comment: "Scroll down, e.g. \"j\", \"down\", [\"j\", \"down\"]."),
            .init(section: id, key: "up", defaultValue: "\"k\"", comment: "Scroll up, e.g. \"k\", \"up\"."),
            .init(section: id, key: "left", defaultValue: "\"h\"", comment: "Scroll left, e.g. \"h\", \"left\"."),
            .init(section: id, key: "right", defaultValue: "\"l\"", comment: "Scroll right, e.g. \"l\", \"right\"."),
            .init(section: id, key: "half_page_down", defaultValue: "\"d\"", comment: "Scroll half a screen down, e.g. \"d\", \"pagedown\"."),
            .init(section: id, key: "half_page_up", defaultValue: "\"u\"", comment: "Scroll half a screen up, e.g. \"u\", \"pageup\"."),
        ]
    }

    public func parseSettings(_ table: TOMLTable) throws -> ModeSettings {
        let r = ConfigReader(table, section: id)
        var s = Settings()
        if let v = try r.number("step") { s.step = v }
        if let v = try r.number("speed") { s.speed = max(50, v) }
        if let v = try r.number("acceleration") { s.acceleration = max(0.05, v) }
        if let v = try r.number("flick") { s.flick = max(0, v) }
        if let v = r.value("flick_double_tap") {
            if let b = v.bool { s.flickDoubleTap = b }
            else if v.string?.lowercased() == "auto" { s.flickDoubleTap = nil }
            else { throw r.fail("flick_double_tap", "expected true, false or \"auto\"") }
        }
        if let v = try r.string("flick_with") {
            if v.isEmpty { s.flickWith = nil }
            else if let m = Modifiers.parse(v) { s.flickWith = m }
            else { throw r.fail("flick_with", "expected modifiers like \"alt\", \"cmd+shift\" or \"\"") }
        }
        if let v = try r.number("friction") { s.friction = min(max(v, 0.01), 0.999) }
        if let v = try r.bool("momentum") { s.momentum = v }
        if let v = try r.bool("smooth") { s.smooth = v }
        if let v = try r.keys("toggle") { s.toggle = v }
        if let v = try r.keys("down") { s.down = v }
        if let v = try r.keys("up") { s.up = v }
        if let v = try r.keys("left") { s.left = v }
        if let v = try r.keys("right") { s.right = v }
        if let v = try r.keys("half_page_down") { s.halfDown = v }
        if let v = try r.keys("half_page_up") { s.halfUp = v }
        return s
    }

    public func apply(_ s: ModeSettings) {
        if let s = s as? Settings { settings = s }
    }

    public var toggle: Set<KeyPress> { settings.toggle }
    /// With smooth scrolling the platform drives a held key; with wheel steps, repeats scroll.
    public var acceptsKeyRepeat: Bool { !settings.smooth }

    public func handle(_ key: KeyPress, count: Int?, _ ctx: ModeContext) -> [Effect]? {
        let n = Double(count ?? 1)
        let s = settings
        let half = ctx.screen.height / 2
        // A scroll key with the flick modifier held flicks instead of scrolling.
        if let fm = s.flickWith, fm.matchesHeld(in: key.modifiers) {
            let bare = KeyPress(key.code, key.modifiers.subtracting(fm).subtracting(fm.generic))
            if s.down.has(bare) { return [.scrollFlick(dx: 0, dy: 1, multiplier: n)] }
            if s.up.has(bare) { return [.scrollFlick(dx: 0, dy: -1, multiplier: n)] }
            if s.left.has(bare) { return [.scrollFlick(dx: -1, dy: 0, multiplier: n)] }
            if s.right.has(bare) { return [.scrollFlick(dx: 1, dy: 0, multiplier: n)] }
        }
        if s.down.has(key) { return [.scrollStart(dx: 0, dy: 1, multiplier: n)] }
        if s.up.has(key) { return [.scrollStart(dx: 0, dy: -1, multiplier: n)] }
        if s.left.has(key) { return [.scrollStart(dx: -1, dy: 0, multiplier: n)] }
        if s.right.has(key) { return [.scrollStart(dx: 1, dy: 0, multiplier: n)] }
        if s.halfDown.has(key) { return [.scroll(dx: 0, dy: half * n)] }
        if s.halfUp.has(key) { return [.scroll(dx: 0, dy: -half * n)] }
        return nil
    }

    public func handleRelease(_ key: KeyPress, _ ctx: ModeContext) -> [Effect] {
        let bare = KeyPress(key.code)
        let keys = settings.down.union(settings.up).union(settings.left).union(settings.right)
        return keys.has(bare) || keys.has(key) ? [.scrollStop] : []
    }

    public func hints(_ ctx: ModeContext) -> [(key: String, action: String)] {
        let s = settings
        func l(_ set: Set<KeyPress>) -> String { KeyMap.label(of: set) }
        var h: [(key: String, action: String)] = [
            (l(s.down) + l(s.up) + " " + l(s.left) + l(s.right), "scroll"),
            (l(s.halfDown) + " " + l(s.halfUp), "half page"),
        ]
        if let fm = s.flickWith { h.append((KeyPress(.space, fm).label.replacingOccurrences(of: "␣", with: "") + "+" + l(s.down), "flick")) }
        return h
    }

    public func help(_ ctx: ModeContext) -> [(keys: String, action: String)] {
        func all(_ set: Set<KeyPress>) -> String { set.map(\.label).sorted().joined(separator: " ") }
        let s = settings
        return [
            (all(s.down) + " / " + all(s.up), "scroll down / up \(Int(s.step))px (count multiplies); hold to accelerate, release to coast, double tap to flick"),
            (all(s.left) + " / " + all(s.right), "scroll left / right"),
            (all(s.halfDown) + " / " + all(s.halfUp), "half a screen down / up"),
        ]
    }

    public func draw(_ ctx: ModeContext, active: Bool) -> [Drawable] {
        guard active else { return [] }
        // A ring around the pointer, which is where scrolling happens.
        return [.ring(ctx.target, radius: 18, colour: ctx.colour(of: id), alpha: 1, width: 3)]
    }

    public var manual: String {
        let s = Settings()
        func keys(_ set: Set<KeyPress>) -> String { set.map(\.label).sorted().joined(separator: ", ") }
        return "Scrolls the content under the pointer. \(keys(s.down)) / \(keys(s.up)) / \(keys(s.left)) / \(keys(s.right)) scroll: a tap is one step, a hold accelerates, release coasts, a double tap flicks, a tap during a coast stops it; \(keys(s.halfDown)) / \(keys(s.halfUp)) half a screen."
    }
}
