import VimouseCore

/// A horizontal reading band that dims everything else. It follows lines of text when
/// `Services.lines` can find them, and persists after the engine goes idle until removed.
public struct Ruler: Equatable, Sendable {
    public var screenIndex: Int
    /// Where the pointer was when the band was created: the text column line snapping probes.
    public var x: Double
    /// Vertical centre of the band, CG coordinates.
    public var y: Double
    public var height: Double

    public init(screenIndex: Int, x: Double = 0, y: Double, height: Double) {
        self.screenIndex = screenIndex
        self.x = x
        self.y = y
        self.height = height
    }

    public func band(on screen: Rect) -> Rect {
        Rect(x: screen.x, y: y - height / 2, width: screen.width, height: height)
    }
}

public final class RulerMode: Mode {
    public struct Settings: ModeSettings, Equatable {
        public var height: Double = 32
        /// 0 means move by the band's own height.
        public var move: Double = 0
        public var heightStep: Double = 4
        /// Pixels per press with Shift held, for move and resize.
        public var fine: Double = 1
        public var dim: Double = 0.35
        /// The band follows lines of text found via accessibility; pixels added above and below.
        public var snap = true
        public var pad: Double = 2
        public var toggle: Set<KeyPress> = [KeyPress(.r)]
        public var remove: Set<KeyPress> = [KeyPress(.r, [.shift])]
        public var down: Set<KeyPress> = [KeyPress(.j)]
        public var up: Set<KeyPress> = [KeyPress(.k)]
        public var grow: Set<KeyPress> = [KeyPress(.rightBracket)]
        public var shrink: Set<KeyPress> = [KeyPress(.leftBracket)]
        public var snapToggle: Set<KeyPress> = [KeyPress(.a)]
        public init() {}
    }

    public let id = "ruler"
    public let name = "RULER"
    public let summary = "Ruler mode: the reading band that dims everything except the line being read."
    public let defaultColour = "#BF5AF2"
    public var settings = Settings()
    /// The band, if one is shown. Survives the engine going idle.
    public private(set) var ruler: Ruler?
    /// Following lines of text this session. Toggled with a key.
    public private(set) var snapping = true

    public init() {}

    public var schema: [ConfigEntry] {
        [
            .init(section: id, key: "toggle", defaultValue: "\"r\"", comment: "Create the reading band / enter or leave Ruler mode, e.g. \"r\"."),
            .init(section: id, key: "remove", defaultValue: "\"shift+r\"", comment: "Remove the reading band (works in any mode), e.g. \"shift+r\"."),
            .init(section: id, key: "height", defaultValue: "32", comment: "Band height in pixels when created without a text line to size to; 20 to 40 covers one or two text lines."),
            .init(section: id, key: "move", defaultValue: "0", comment: "How far the band moves per press when not following text: 0 = its own height, otherwise pixels, e.g. 20. A count multiplies."),
            .init(section: id, key: "fine", defaultValue: "1", comment: "Pixels the band moves or resizes per press while Shift is held (micro-adjustment), e.g. 1, 2."),
            .init(section: id, key: "height_step", defaultValue: "4", comment: "Pixels added or removed from the band height per press, e.g. 2, 4, 8."),
            .init(section: id, key: "snap", defaultValue: "true", comment: "Follow lines of text: the band is created on the line under the pointer and down/up move it a line at a time (read via accessibility; falls back to `move` where no text is found)."),
            .init(section: id, key: "pad", defaultValue: "2", comment: "Pixels added above and below a line the band snapped to, e.g. 0, 2, 4."),
            .init(section: id, key: "snap_toggle", defaultValue: "\"a\"", comment: "Toggle following lines of text in Ruler mode, e.g. \"a\"."),
            .init(section: id, key: "dim", defaultValue: "0.35", comment: "Darkening outside the band, 0 (none) to 1 (black); 0.2 subtle, 0.35 default, 0.6 strong."),
            .init(section: id, key: "down", defaultValue: "\"j\"", comment: "Move the band down, e.g. \"j\", \"down\"."),
            .init(section: id, key: "up", defaultValue: "\"k\"", comment: "Move the band up, e.g. \"k\", \"up\"."),
            .init(section: id, key: "grow", defaultValue: "\"rightbracket\"", comment: "Make the band taller, e.g. \"rightbracket\", \"equal\"."),
            .init(section: id, key: "shrink", defaultValue: "\"leftbracket\"", comment: "Make the band shorter, e.g. \"leftbracket\", \"minus\"."),
        ]
    }

    public func parseSettings(_ table: TOMLTable) throws -> ModeSettings {
        let r = ConfigReader(table, section: id)
        var s = Settings()
        if let v = try r.number("height") { s.height = v }
        if let v = try r.number("move") { s.move = max(0, v) }
        if let v = try r.number("height_step") { s.heightStep = v }
        if let v = try r.number("fine") { s.fine = max(0.5, v) }
        if let v = try r.number("dim") { s.dim = min(max(v, 0), 1) }
        if let v = try r.bool("snap") { s.snap = v }
        if let v = try r.number("pad") { s.pad = max(0, v) }
        if let v = try r.keys("toggle") { s.toggle = v }
        if let v = try r.keys("remove") { s.remove = v }
        if let v = try r.keys("down") { s.down = v }
        if let v = try r.keys("up") { s.up = v }
        if let v = try r.keys("grow") { s.grow = v }
        if let v = try r.keys("shrink") { s.shrink = v }
        if let v = try r.keys("snap_toggle") { s.snapToggle = v }
        return s
    }

    public func apply(_ s: ModeSettings) {
        guard let s = s as? Settings else { return }
        settings = s
        if ruler == nil { snapping = s.snap }
    }

    public var toggle: Set<KeyPress> { settings.toggle }
    public var drawsWhileIdle: Bool { ruler != nil }

    public func activate(_ ctx: ModeContext) {
        if ruler == nil {
            var r = Ruler(screenIndex: ctx.screenIndex, x: ctx.target.x, y: ctx.target.y, height: settings.height)
            if let line = snappedLine(for: r, direction: 0, ctx) { r.y = line.y; r.height = line.height }
            ruler = r
        }
        follow(ctx)
    }

    /// The pointer rides on the band's centre line so the marker, clicks and a switch to
    /// Scroll mode all act where the band is.
    private func follow(_ ctx: ModeContext) {
        guard let r = ruler, r.screenIndex == ctx.screenIndex else { return }
        ctx.target = ctx.clamped(Point(x: ctx.target.x, y: r.y))
    }

    public func handleAnywhere(_ key: KeyPress, count: Int?, _ ctx: ModeContext) -> [Effect]? {
        guard settings.remove.has(key) else { return nil }
        ruler = nil
        snapping = settings.snap
        // Removing the band while in Ruler mode: nothing left to adjust, so hand back.
        if ctx.activeMode == id { ctx.switchMode(to: nil) }
        return [.redraw]
    }

    public func handle(_ key: KeyPress, count: Int?, _ ctx: ModeContext) -> [Effect]? {
        let n = Double(count ?? 1)
        let s = settings
        if s.snapToggle.has(key) {
            snapping.toggle()
            if snapping, var r = ruler, let line = snappedLine(for: r, direction: 0, ctx) {
                r.y = line.y; r.height = line.height
                ruler = r
            }
            follow(ctx)
            return [.warp(ctx.target), .redraw]
        }
        guard var r = ruler else { return nil }
        let screen = ctx.screens[r.screenIndex]
        // Shift held with a move or resize key makes a fine (pixel) adjustment.
        let fine = key.modifiers.contains(.shift)
        let base = KeyPress(key.code, key.modifiers.subtracting(.shift))
        let move = fine ? s.fine : (s.move > 0 ? s.move : r.height)
        let resize = fine ? s.fine : s.heightStep
        // A coarse move follows the text lines when snapping is on and text is found;
        // otherwise it steps by the band height (or `move` pixels).
        func step(_ direction: Double) {
            if !fine, let line = snappedLine(for: r, direction: Int(direction), count: Int(n), ctx) {
                r.y = line.y; r.height = line.height
            } else {
                r.y += direction * move * n
            }
        }
        func hit(_ set: Set<KeyPress>) -> Bool { set.has(key) || (fine && set.has(base)) }
        if hit(s.down) { step(1) }
        else if hit(s.up) { step(-1) }
        else if hit(s.grow) { r.height += resize * n }
        else if hit(s.shrink) { r.height -= resize * n }
        else { return nil }
        r.height = max(8, r.height)
        r.y = min(max(r.y, screen.y), screen.maxY)
        ruler = r
        follow(ctx)
        return [.warp(ctx.target), .redraw]
    }

    /// Centre and height for the band on the text line `count` lines from the current one
    /// (0: the line under it), padded; nil when snapping is off or no text is there.
    private func snappedLine(for r: Ruler, direction: Int, count: Int = 1, _ ctx: ModeContext) -> (y: Double, height: Double)? {
        guard snapping, let provider = ctx.services.lines else { return nil }
        let screen = ctx.screens[r.screenIndex]
        var y = r.y
        var found: Rect?
        for _ in 0..<max(1, count) {
            guard let line = provider.textLine(at: r.x, y: y, direction: direction, on: screen) else { break }
            found = line
            y = line.midY
            if direction == 0 { break }
        }
        guard let line = found else { return nil }
        return (line.midY, line.height + 2 * settings.pad)
    }

    public func hints(_ ctx: ModeContext) -> [(key: String, action: String)] {
        let s = settings
        func l(_ set: Set<KeyPress>) -> String { KeyMap.label(of: set) }
        var h: [(key: String, action: String)] = [
            (l(s.down) + l(s.up), "move"),
            (l(s.shrink) + " " + l(s.grow), "height"),
            ("⇧", "fine"),
        ]
        if ctx.services.lines != nil { h.append((l(s.snapToggle), snapping ? "lines on" : "lines off")) }
        h.append((l(s.remove), "remove"))
        return h
    }

    public func help(_ ctx: ModeContext) -> [(keys: String, action: String)] {
        func all(_ set: Set<KeyPress>) -> String { set.map(\.label).sorted().joined(separator: " ") }
        let s = settings
        return [
            (all(s.down) + " / " + all(s.up), "move band down / up a line of text, or by its height (⇧: 1px)"),
            (all(s.grow) + " / " + all(s.shrink), "taller / shorter by \(Int(s.heightStep))px (⇧: 1px)"),
            (all(s.snapToggle), "toggle following lines of text"),
            (all(s.remove), "remove band (any mode)"),
        ]
    }

    public func draw(_ ctx: ModeContext, active: Bool) -> [Drawable] {
        guard let r = ruler, ctx.screens.indices.contains(r.screenIndex) else { return [] }
        let band = r.band(on: ctx.screens[r.screenIndex])
        return [
            .dim(screen: r.screenIndex, except: band, alpha: settings.dim),
            .outline(band, colour: ctx.colour(of: id), alpha: active ? 0.9 : 0.5, width: active ? 2 : 1),
        ]
    }

    public var manual: String {
        let s = Settings()
        func keys(_ set: Set<KeyPress>) -> String { set.map(\.label).sorted().joined(separator: ", ") }
        return "A reading band that dims everything except the line being read. Entering the mode creates it on the line of text under the pointer (sized to the line when the app exposes its text through accessibility, otherwise \(Int(s.height)) px tall); \(keys(s.down)) / \(keys(s.up)) move it a line at a time (or by its height); \(keys(s.shrink)) / \(keys(s.grow)) resize; Shift held makes one-pixel changes; \(keys(s.snapToggle)) toggles following text; \(keys(s.remove)) removes the band from any mode. The band stays when the mode is left."
    }
}
