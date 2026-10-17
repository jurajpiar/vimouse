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
    /// Horizontal extent of the band and of the dimming: the window holding the text, or
    /// the line itself, when known; nil spans the screen.
    public var bounds: Rect?
    public var dimBounds: Rect?
    /// When the band has been extended over several lines: the last line taken in
    /// (centre and height), which a collapse returns to. nil for a single line.
    public var lastLine: (y: Double, height: Double)?
    public var isExtended: Bool { lastLine != nil }

    public static func == (a: Ruler, b: Ruler) -> Bool {
        a.screenIndex == b.screenIndex && a.x == b.x && a.y == b.y && a.height == b.height
            && a.bounds == b.bounds && a.dimBounds == b.dimBounds
            && a.lastLine?.y == b.lastLine?.y && a.lastLine?.height == b.lastLine?.height
    }

    public init(screenIndex: Int, x: Double = 0, y: Double, height: Double, bounds: Rect? = nil, dimBounds: Rect? = nil) {
        self.screenIndex = screenIndex
        self.x = x
        self.y = y
        self.height = height
        self.bounds = bounds
        self.dimBounds = dimBounds
    }

    public func band(on screen: Rect) -> Rect {
        let b = bounds.map { $0.intersection(screen) } ?? screen
        return Rect(x: b.x, y: y - height / 2, width: b.width, height: height)
    }

    /// The area darkened around the band.
    public func dimArea(on screen: Rect) -> Rect {
        dimBounds.map { $0.intersection(screen) } ?? screen
    }
}

/// How wide the band is.
public enum RulerWidth: String, Equatable {
    /// The window holding the text under the pointer (the screen when none is found).
    case window
    /// The whole display.
    case screen
    /// The line of text itself (its window when no line is found).
    case line
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
        public var snap = false
        /// Reconstruct lines in Chromium and Electron apps from character rectangles.
        public var snapTricks = false
        public var pad: Double = 2
        public var toggle: Set<KeyPress> = [KeyPress(.r)]
        public var remove: Set<KeyPress> = [KeyPress(.r, [.shift])]
        public var down: Set<KeyPress> = [KeyPress(.j)]
        public var up: Set<KeyPress> = [KeyPress(.k)]
        public var grow: Set<KeyPress> = [KeyPress(.rightBracket)]
        public var shrink: Set<KeyPress> = [KeyPress(.leftBracket)]
        public var snapToggle: Set<KeyPress> = [KeyPress(.a)]
        public var extend: Set<KeyPress> = [KeyPress(.e)]
        public var collapse: Set<KeyPress> = [KeyPress(.c)]
        public var width: RulerWidth = .window
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
    public private(set) var snapping = false
    /// Whether the band currently sits on a line of text found through accessibility.
    public private(set) var onLine = false

    public init() {}

    public var schema: [ConfigEntry] {
        [
            .init(section: id, key: "toggle", defaultValue: "\"r\"", comment: "Enter Ruler mode, creating the band; again removes it and returns to the previous mode, e.g. \"r\"."),
            .init(section: id, key: "remove", defaultValue: "\"shift+r\"", comment: "Remove a band left behind by switching to another mode (works in any mode), e.g. \"shift+r\"."),
            .init(section: id, key: "height", defaultValue: "32", comment: "Band height in pixels when created without a text line to size to; 20 to 40 covers one or two text lines."),
            .init(section: id, key: "move", defaultValue: "0", comment: "How far the band moves per press when not following text: 0 = its own height, otherwise pixels, e.g. 20. A count multiplies."),
            .init(section: id, key: "fine", defaultValue: "1", comment: "Pixels the band moves or resizes per press while Shift is held (micro-adjustment), e.g. 1, 2."),
            .init(section: id, key: "height_step", defaultValue: "4", comment: "Pixels added or removed from the band height per press, e.g. 2, 4, 8."),
            .init(section: id, key: "snap", defaultValue: "false", comment: "Follow lines of text: the band is created on the line under the pointer and down/up move it a line at a time (read via accessibility; falls back to `move` where no text is found). Reliable where the app reports its lines (AppKit text views, Safari and other WebKit views); off by default."),
            .init(section: id, key: "snap_tricks", defaultValue: "false", comment: "Also follow lines in apps that do not report them (Chromium browsers, Electron apps such as Claude or VS Code), reconstructed from character rectangles; works line by line but can pick the wrong line."),
            .init(section: id, key: "pad", defaultValue: "2", comment: "Pixels added above and below a line the band snapped to, e.g. 0, 2, 4."),
            .init(section: id, key: "snap_toggle", defaultValue: "\"a\"", comment: "Toggle following lines of text in Ruler mode, e.g. \"a\"."),
            .init(section: id, key: "extend", defaultValue: "\"e\"", comment: "Extend the band to take in the next line below (reading in blocks); again for another line, e.g. \"e\"."),
            .init(section: id, key: "collapse", defaultValue: "\"c\"", comment: "Collapse an extended band back to its last line, so reading continues from there, e.g. \"c\"."),
            .init(section: id, key: "width", defaultValue: "\"window\"", comment: "How wide the band and the dimming are: \"window\" (the window holding the text under the pointer), \"screen\", or \"line\" (the text line itself, dimming its window)."),
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
        if let v = try r.bool("snap_tricks") { s.snapTricks = v }
        if let v = try r.number("pad") { s.pad = max(0, v) }
        if let v = try r.keys("toggle") { s.toggle = v }
        if let v = try r.keys("remove") { s.remove = v }
        if let v = try r.keys("down") { s.down = v }
        if let v = try r.keys("up") { s.up = v }
        if let v = try r.keys("grow") { s.grow = v }
        if let v = try r.keys("shrink") { s.shrink = v }
        if let v = try r.keys("snap_toggle") { s.snapToggle = v }
        if let v = try r.keys("extend") { s.extend = v }
        if let v = try r.keys("collapse") { s.collapse = v }
        if let v = try r.string("width") {
            guard let w = RulerWidth(rawValue: v.lowercased()) else { throw r.fail("width", "expected \"window\", \"screen\" or \"line\"") }
            s.width = w
        }
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
        ctx.services.lines?.configure(tricks: settings.snapTricks)
        if ruler == nil {
            snapping = settings.snap
            var r = Ruler(screenIndex: ctx.screenIndex, x: ctx.target.x, y: ctx.target.y, height: settings.height)
            seat(&r, on: snappedLine(for: r, direction: 0, ctx), ctx)
            ruler = r
        }
        follow(ctx)
    }

    /// The pointer rides on the band's centre line so the marker, clicks and a switch to
    /// Scroll mode all act where the band is.
    private func follow(_ ctx: ModeContext) {
        guard let r = ruler, r.screenIndex == ctx.screenIndex else { return }
        ctx.target = ctx.clamped(Point(x: ctx.target.x, y: r.lastLine?.y ?? r.y))
    }

    /// The band survives only a deliberate switch to another mode; its own toggle and
    /// leaving altogether take it away.
    public func deactivate(_ ctx: ModeContext, reason: LeaveReason) {
        guard reason != .switched else { return }
        ruler = nil
        snapping = settings.snap
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
            onLine = false
            if snapping, var r = ruler, let line = snappedLine(for: r, direction: 0, ctx) {
                seat(&r, on: line, ctx)
                ruler = r
            }
            follow(ctx)
            return [.warp(ctx.target), .redraw]
        }
        guard var r = ruler else { return nil }
        let screen = ctx.screens[r.screenIndex]
        if s.extend.has(key) {
            for _ in 0..<Int(n) { extend(&r, ctx) }
            ruler = r
            follow(ctx)
            return [.warp(ctx.target), .redraw]
        }
        if s.collapse.has(key) {
            guard r.isExtended else { return [] }
            collapse(&r, ctx)
            ruler = r
            follow(ctx)
            return [.warp(ctx.target), .redraw]
        }
        // A move or resize of an extended band first collapses it to its last line.
        if r.isExtended, !s.grow.has(key), !s.shrink.has(key) { collapse(&r, ctx) }
        // Shift held with a move or resize key makes a fine (pixel) adjustment.
        let fine = key.modifiers.contains(.shift)
        let base = KeyPress(key.code, key.modifiers.subtracting(.shift))
        let move = fine ? s.fine : (s.move > 0 ? s.move : r.height)
        let resize = fine ? s.fine : s.heightStep
        // A coarse move follows the text lines when snapping is on and text is found;
        // otherwise it steps by the band height (or `move` pixels).
        func step(_ direction: Double) {
            if !fine, let line = snappedLine(for: r, direction: Int(direction), count: Int(n), ctx) {
                seat(&r, on: line, ctx)
            } else {
                r.y += direction * move * n
                seat(&r, on: nil, ctx)
            }
        }
        func hit(_ set: Set<KeyPress>) -> Bool { set.has(key) || (fine && set.has(base)) }
        if hit(s.down) { step(1) }
        else if hit(s.up) { step(-1) }
        // Resizing keeps the top edge where it is: the band grows or shrinks in the
        // direction of reading.
        else if hit(s.grow) { r.height += resize * n; r.y += resize * n / 2 }
        else if hit(s.shrink) { let d = min(resize * n, r.height - 8); r.height -= d; r.y -= d / 2 }
        else { return nil }
        r.height = max(8, r.height)
        r.y = min(max(r.y, screen.y), screen.maxY)
        ruler = r
        follow(ctx)
        return [.warp(ctx.target), .redraw]
    }

    /// Take in the next line below the band's bottom edge (or `move` pixels when no line
    /// is found); the band then spans from its top to that line's bottom.
    private func extend(_ r: inout Ruler, _ ctx: ModeContext) {
        let top = r.y - r.height / 2
        let bottomLine = r.lastLine ?? (y: r.y, height: r.height)
        let probe = Ruler(screenIndex: r.screenIndex, x: r.x, y: bottomLine.y, height: bottomLine.height)
        let next: (y: Double, height: Double)
        if let line = snappedLine(for: probe, direction: 1, ctx) {
            next = (line.y, line.height)
        } else {
            let step = settings.move > 0 ? settings.move : bottomLine.height
            next = (bottomLine.y + step, bottomLine.height)
        }
        let bottom = min(ctx.screens[r.screenIndex].maxY, next.y + next.height / 2)
        r.lastLine = next
        r.height = bottom - top
        r.y = top + r.height / 2
        seat(&r, on: nil, ctx)
    }

    /// Back to a single line: the last one taken in.
    private func collapse(_ r: inout Ruler, _ ctx: ModeContext) {
        guard let l = r.lastLine else { return }
        r.y = l.y
        r.height = l.height
        r.lastLine = nil
        seat(&r, on: nil, ctx)
    }

    /// Place the band on a found line (or keep its position when nil) and work out how
    /// wide it and its dimming are, per `[ruler] width`.
    private func seat(_ r: inout Ruler, on line: (y: Double, height: Double, rect: Rect)?, _ ctx: ModeContext) {
        onLine = line != nil
        if let line { r.y = line.y; r.height = line.height; r.lastLine = nil }
        let window = settings.width == .screen ? nil : ctx.services.lines?.window(at: r.x, y: r.y)
        r.dimBounds = window
        switch settings.width {
        case .screen: r.bounds = nil
        case .window: r.bounds = window
        case .line:
            if let line { r.bounds = Rect(x: line.rect.x - settings.pad, y: line.rect.y, width: line.rect.width + 2 * settings.pad, height: line.rect.height) }
            else { r.bounds = window }
        }
    }

    /// Centre and height for the band on the text line `count` lines from the current one
    /// (0: the line under it), padded; nil when snapping is off or no text is there.
    private func snappedLine(for r: Ruler, direction: Int, count: Int = 1, _ ctx: ModeContext) -> (y: Double, height: Double, rect: Rect)? {
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
        return (line.midY, line.height + 2 * settings.pad, line)
    }

    public let symbol = "☰"

    public func hints(_ ctx: ModeContext) -> [Hint] {
        let s = settings
        func l(_ set: Set<KeyPress>) -> String { KeyMap.label(of: set) }
        var h = [
            Hint(l(s.down) + l(s.up), "move", "↕"),
            Hint(l(s.shrink) + " " + l(s.grow), "height", "⬍"),
            Hint("⇧", "fine", "1px"),
            Hint(l(s.extend), "extend", "⤵"),
        ]
        if ruler?.isExtended == true { h.append(Hint(l(s.collapse), "collapse", "⤒")) }
        if ctx.services.lines != nil {
            // Greyed when following is on but no text is under the band: the band steps by its height.
            h.append(Hint(l(s.snapToggle), snapping ? "☑ lines" : "☐ lines", snapping ? "☑☰" : "☐☰", unavailable: snapping && !onLine))
        }
        h.append(Hint(l(s.remove), "remove", "☰✕"))
        return h
    }

    public func help(_ ctx: ModeContext) -> [(keys: String, action: String)] {
        func all(_ set: Set<KeyPress>) -> String { set.map(\.label).sorted().joined(separator: " ") }
        let s = settings
        return [
            (all(s.down) + " / " + all(s.up), "move band down / up a line of text, or by its height (⇧: 1px)"),
            (all(s.grow) + " / " + all(s.shrink), "taller / shorter by \(Int(s.heightStep))px (⇧: 1px)"),
            (all(s.extend), "extend the band over the next line below (read in blocks)"),
            (all(s.collapse), "collapse an extended band to its last line"),
            (all(s.snapToggle), "toggle following lines of text"),
            (all(s.remove), "remove band (any mode)"),
        ]
    }

    public func draw(_ ctx: ModeContext, active: Bool) -> [Drawable] {
        guard let r = ruler, ctx.screens.indices.contains(r.screenIndex) else { return [] }
        let band = r.band(on: ctx.screens[r.screenIndex])
        return [
            .dim(screen: r.screenIndex, area: r.dimArea(on: ctx.screens[r.screenIndex]), except: band, alpha: settings.dim),
            .outline(band, colour: ctx.colour(of: id), alpha: active ? 0.9 : 0.5, width: active ? 2 : 1),
        ]
    }

    public var manual: String {
        let s = Settings()
        func keys(_ set: Set<KeyPress>) -> String { set.map(\.label).sorted().joined(separator: ", ") }
        return "A reading band that dims everything except the line being read. Entering the mode creates it on the line of text under the pointer (sized to the line when the app exposes its text through accessibility, otherwise \(Int(s.height)) px tall); \(keys(s.down)) / \(keys(s.up)) move it a line at a time (or by its height); \(keys(s.shrink)) / \(keys(s.grow)) resize from the bottom edge (the top stays put); Shift held makes one-pixel changes; \(keys(s.extend)) extends the band over the next line below, for reading in blocks, and \(keys(s.collapse)) collapses it to the last line taken in; \(keys(s.snapToggle)) toggles following text. Leaving with the toggle or exiting removes the band; switching to another mode (Scroll, say, to scroll the text under a fixed band) keeps it, and \(keys(s.remove)) removes it from any mode."
    }
}
