public enum MouseButton: Equatable, Sendable {
    case left, right, middle
}

/// What the platform layer must do after the engine handles a key.
/// Effects are applied in order.
public enum Effect: Equatable, Sendable {
    case showOverlay
    case redraw
    case hideOverlay
    case warp(Point)
    case click(MouseButton, count: Int, modifiers: Modifiers)
    case mouseDown(MouseButton)
    case mouseUp(MouseButton)
    /// Abandon a drag: tell the system to cancel it and release the button back at the origin.
    case cancelDrag(origin: Point)
    /// Pixels. Positive dy reveals content below (like vim's j), positive dx content to the right.
    case scroll(dx: Double, dy: Double)
    /// A scroll key went down: direction (unit components) and multiplier (count prefix).
    /// The platform taps, accelerates while held and coasts after release.
    case scrollStart(dx: Double, dy: Double, multiplier: Double)
    /// The scroll key went up.
    case scrollStop
    /// Flick: launch a coast in this direction without a hold.
    case scrollFlick(dx: Double, dy: Double, multiplier: Double)
    /// The held nudge keys changed: the combined unit direction (diagonal when a horizontal
    /// and a vertical key are both down) and count multiplier. The platform moves one step
    /// on the first press, accelerates while any key is held, steers on later changes and
    /// stops on `nudgeStop`.
    case nudgeStart(dx: Double, dy: Double, multiplier: Double)
    case nudgeStop
}

public enum Mode: String, Equatable, Sendable, CaseIterable {
    case pointer, scroll, ruler, nudge
}

/// A horizontal reading band. Persists after Pointer mode exits until removed.
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

/// Supplies a better pointer target inside a rectangle (for example the centre of
/// the nearest clickable UI element). Return nil to use the rectangle's centre.
public protocol SnapProvider: AnyObject {
    /// Called once when Pointer mode starts on a screen; a chance to cache.
    func prepare(screen: Rect)
    func snapPoint(in rect: Rect) -> Point?
}

/// Supplies the bounds of lines of text (from the accessibility API) so the reading band
/// can follow real lines instead of a fixed step.
public protocol LineProvider: AnyObject {
    /// The line containing (x, y) when `direction` is 0, the first line below it when 1,
    /// the first line above it when -1. nil when no text is found there.
    func textLine(at x: Double, y: Double, direction: Int, on screen: Rect) -> Rect?
}

/// Modal state machine for Pointer mode. Pure: no platform calls, fully testable.
public final class PointerEngine {
    public enum State: Equatable {
        case idle
        case active(mode: Mode, session: BisectSession)
    }

    public private(set) var state: State = .idle
    public var keymap: KeyMap

    /// All displays (CG coordinates) and which one the session is on.
    public private(set) var screens: [Rect] = []
    public private(set) var screenIndex: Int = 0
    /// Left button currently held by a `v` drag, and where it was pressed.
    public private(set) var dragging = false
    public private(set) var dragOrigin: Point?
    /// vi-style count prefix typed so far; nil when none. Consumed by the next command.
    public private(set) var pendingCount: Int?
    /// True when the current activation came from the hold key (quasi-mode).
    public var heldActivation = false
    /// The reading band, if one is shown. Survives deactivation.
    public private(set) var ruler: Ruler?

    /// Vertical/horizontal scroll per j/k/h/l press, in pixels.
    public var scrollStep: Double = 60
    /// Ruler movement per j/k press (0 = the band's own height), its height change per [ ] press, and its initial height.
    public var rulerMove: Double = 0
    public var rulerHeightStep: Double = 4
    public var rulerFine: Double = 1
    /// Pointer movement per press in Nudge mode (Shift: one pixel).
    public var nudgeStep: Double = 5
    /// Whether starting a drag restarts the quadrant search from the whole screen.
    public var dragRestartsSearch = true
    public var rulerDefaultHeight: Double = 32

    /// Snap the pointer to UI elements (needs a `snapProvider`). Toggled in Pointer mode.
    public var snapping: Bool
    public weak var snapProvider: SnapProvider?
    /// The reading band follows lines of text (needs a `lineProvider`). Toggled in Ruler mode.
    public var rulerSnap = true
    /// Pixels added above and below a snapped line.
    public var rulerPad: Double = 2
    public weak var lineProvider: LineProvider?
    /// Where the pointer was last sent (the snap target or the rectangle centre).
    public private(set) var target: Point = Point(x: 0, y: 0)
    /// Nudge keys currently held, by key code, with the direction each contributes.
    private var heldNudges: [KeyCode: (dx: Double, dy: Double)] = [:]

    public init(keymap: KeyMap = .default, snapping: Bool = true, snapProvider: SnapProvider? = nil) {
        self.keymap = keymap
        self.snapping = snapping
        self.snapProvider = snapProvider
    }

    /// Apply a (re)loaded configuration. Safe at any time; an existing ruler keeps its size.
    public func apply(_ c: Config) {
        keymap = c.keymap
        scrollStep = c.scrollStep
        rulerDefaultHeight = c.rulerHeight
        rulerMove = c.rulerMove
        rulerHeightStep = c.rulerHeightStep
        rulerFine = c.rulerFine
        rulerSnap = c.rulerSnap
        rulerPad = c.rulerPad
        nudgeStep = c.nudgeStep
        dragRestartsSearch = c.dragRestartsSearch
        if !isActive { snapping = c.snapEnabled }
    }

    public var isActive: Bool {
        if case .idle = state { return false }
        return true
    }

    public var mode: Mode? {
        if case .active(let m, _) = state { return m }
        return nil
    }

    public var session: BisectSession? {
        if case .active(_, let s) = state { return s }
        return nil
    }

    /// True when the overlay has anything to draw (an active mode or a ruler).
    public var needsOverlay: Bool { isActive || ruler != nil }

    // MARK: Activation

    /// Enter Pointer mode over `screens[index]` (CG coordinates). The pointer stays
    /// where it is (`pointer`); the first quadrant pick moves it.
    public func activate(screens: [Rect], index: Int, pointer: Point? = nil, mode: Mode = .pointer) -> [Effect] {
        precondition(!screens.isEmpty && screens.indices.contains(index))
        self.screens = screens
        screenIndex = index
        let s = BisectSession(root: screens[index])
        pendingCount = nil
        snapProvider?.prepare(screen: screens[index])
        target = pointer ?? s.current.center
        if mode == .ruler, ruler == nil { ruler = makeRuler() }
        state = .active(mode: mode, session: s)
        return [.showOverlay]
    }

    /// Convenience for a single screen.
    public func activate(screen: Rect, pointer: Point? = nil, mode: Mode = .pointer) -> [Effect] {
        activate(screens: [screen], index: 0, pointer: pointer, mode: mode)
    }

    /// Switch the active mode (for example when a held activation is pinned by the
    /// hotkey, which carries its own start mode). Ruler mode creates a band if none exists.
    public func enter(mode: Mode) -> [Effect] {
        guard case .active(let current, let s) = state, current != mode else { return [] }
        if mode == .ruler, ruler == nil { ruler = makeRuler() }
        state = .active(mode: mode, session: s)
        heldNudges = [:]
        return [.redraw]
    }

    /// Leave the active mode, releasing a held drag first. A ruler stays on screen.
    public func deactivate() -> [Effect] {
        state = .idle
        pendingCount = nil
        heldNudges = [:]
        var fx: [Effect] = []
        if dragging {
            dragging = false
            dragOrigin = nil
            fx.append(.mouseUp(.left))
        }
        fx.append(ruler == nil ? .hideOverlay : .redraw)
        return fx
    }

    /// The point to send the pointer to for a rectangle: a snapped element if enabled and
    /// available, otherwise the centre.
    private func aim(_ r: Rect) -> Point {
        if snapping, let p = snapProvider?.snapPoint(in: r), r.contains(p) {
            target = p
        } else {
            target = r.center
        }
        return target
    }

    // MARK: Keys

    /// Handle a key press while active. Returns the effects to apply.
    /// Unbound keys are swallowed and produce no effects.
    public func handle(_ key: KeyPress) -> [Effect] {
        guard case .active(let mode, var s) = state else { return [] }

        // Count prefix: digits accumulate until a command consumes them.
        if let d = keymap.digit(for: key) {
            pendingCount = min((pendingCount ?? 0) * 10 + d, 9999)
            return [.redraw]
        }
        let count = pendingCount
        pendingCount = nil
        let n = Double(count ?? 1)

        // Shared across modes.
        if keymap.exit.has(key) {
            // As in vi, Escape with a count pending only cancels the count.
            if count != nil { return [.redraw] }
            // During a drag, Escape abandons the drag and stays in the mode.
            if dragging, let origin = dragOrigin {
                dragging = false
                dragOrigin = nil
                target = origin
                return [.cancelDrag(origin: origin), .redraw]
            }
            return deactivate()
        }
        if keymap.scrollToggle.has(key) {
            state = .active(mode: mode == .scroll ? .pointer : .scroll, session: s)
            return [.redraw]
        }
        if keymap.rulerToggle.has(key) {
            if mode == .ruler {
                state = .active(mode: .pointer, session: s)
            } else {
                if ruler == nil { ruler = makeRuler() }
                state = .active(mode: .ruler, session: s)
            }
            return [.redraw]
        }
        if keymap.rulerRemove.has(key) {
            ruler = nil
            if mode == .ruler { state = .active(mode: .pointer, session: s) }
            return [.redraw]
        }
        if keymap.nudgeToggle.has(key), mode == .pointer || mode == .nudge {
            state = .active(mode: mode == .nudge ? .pointer : .nudge, session: s)
            return [.redraw]
        }
        if keymap.dragToggle.has(key) {
            dragging.toggle()
            if dragging {
                dragOrigin = target
                // The task is now "where to drop": restart the quadrant search from the whole
                // screen, pointer staying where it is.
                if mode == .pointer, dragRestartsSearch { state = .active(mode: .pointer, session: BisectSession(root: screens[screenIndex])) }
                return [.mouseDown(.left), .redraw]
            }
            dragOrigin = nil
            return [.mouseUp(.left), .redraw]
        }
        if let fx = clickEffects(for: key, count: count) { return fx }
        if keymap.rulerSnapToggle.has(key), mode == .ruler {
            rulerSnap.toggle()
            if rulerSnap, var r = ruler, let line = snappedLine(for: r, direction: 0) {
                r.y = line.y; r.height = line.height
                ruler = r
            }
            return [.redraw]
        }
        if keymap.snapToggle.has(key), mode == .pointer {
            snapping.toggle()
            return [.warp(aim(s.current)), .redraw]
        }
        if keymap.nextScreen.has(key) {
            // With a count, Tab jumps to that screen (1-based); without, to the next one.
            if let c = count { return switchScreen(to: c - 1) }
            return switchScreen(to: (screenIndex + 1) % screens.count)
        }
        if keymap.previousScreen.has(key) {
            if let c = count { return switchScreen(to: c - 1) }
            return switchScreen(to: (screenIndex - 1 + screens.count) % screens.count)
        }

        switch mode {
        case .pointer:
            if let q = keymap.quadrant(for: key) {
                for _ in 0..<(count ?? 1) { s.select(q) }
                state = .active(mode: .pointer, session: s)
                return [.warp(aim(s.current)), .redraw]
            }
            if keymap.top.has(key) {
                guard s.depth > 0 else { return count == nil ? [] : [.redraw] }
                s.reset()
                state = .active(mode: .pointer, session: s)
                return [.warp(aim(s.current)), .redraw]
            }
            if keymap.up.has(key) {
                guard s.up() else { return count == nil ? [] : [.redraw] }
                for _ in 1..<(count ?? 1) { s.up() }
                state = .active(mode: .pointer, session: s)
                return [.warp(aim(s.current)), .redraw]
            }
        case .scroll:
            let half = screens[screenIndex].height / 2
            // A scroll key with the flick modifier held flicks instead of scrolling.
            if let fm = keymap.flickWith, fm.matchesHeld(in: key.modifiers) {
                let bare = KeyPress(key.code, key.modifiers.subtracting(fm).subtracting(fm.generic))
                if keymap.scrollDown.has(bare) { return [.scrollFlick(dx: 0, dy: 1, multiplier: n)] }
                if keymap.scrollUp.has(bare) { return [.scrollFlick(dx: 0, dy: -1, multiplier: n)] }
                if keymap.scrollLeft.has(bare) { return [.scrollFlick(dx: -1, dy: 0, multiplier: n)] }
                if keymap.scrollRight.has(bare) { return [.scrollFlick(dx: 1, dy: 0, multiplier: n)] }
            }
            if keymap.scrollDown.has(key) { return [.scrollStart(dx: 0, dy: 1, multiplier: n)] }
            if keymap.scrollUp.has(key) { return [.scrollStart(dx: 0, dy: -1, multiplier: n)] }
            if keymap.scrollLeft.has(key) { return [.scrollStart(dx: -1, dy: 0, multiplier: n)] }
            if keymap.scrollRight.has(key) { return [.scrollStart(dx: 1, dy: 0, multiplier: n)] }
            if keymap.scrollHalfDown.has(key) { return [.scroll(dx: 0, dy: half * n)] }
            if keymap.scrollHalfUp.has(key) { return [.scroll(dx: 0, dy: -half * n)] }
        case .nudge:
            let fine = key.modifiers.contains(.shift)
            let base = KeyPress(key.code, key.modifiers.subtracting(.shift))
            func hit(_ set: Set<KeyPress>) -> Bool { set.has(key) || (fine && set.has(base)) }
            var dir = (dx: 0.0, dy: 0.0)
            if hit(keymap.nudgeLeft) { dir.dx = -1 }
            else if hit(keymap.nudgeRight) { dir.dx = 1 }
            else if hit(keymap.nudgeUp) { dir.dy = -1 }
            else if hit(keymap.nudgeDown) { dir.dy = 1 }
            else { break }
            if fine {
                // One pixel per press (key repeat gives a slow, exact crawl).
                var p = target
                p.x += dir.dx * n
                p.y += dir.dy * n
                let screen = screens[screenIndex]
                p.x = min(max(p.x, screen.x), screen.maxX - 1)
                p.y = min(max(p.y, screen.y), screen.maxY - 1)
                target = p
                return [.warp(p), .redraw]
            }
            heldNudges[key.code] = dir
            return [nudgeEffect(multiplier: n)]
        case .ruler:
            guard var r = ruler else { break }
            let screen = screens[r.screenIndex]
            // Shift held with a move or resize key makes a fine (pixel) adjustment.
            let fine = key.modifiers.contains(.shift)
            let base = KeyPress(key.code, key.modifiers.subtracting(.shift))
            let move = fine ? rulerFine : (rulerMove > 0 ? rulerMove : r.height)
            let resize = fine ? rulerFine : rulerHeightStep
            // A coarse move follows the text lines when snapping is on and text is found;
            // otherwise it steps by the band height (or `move` pixels).
            func step(_ direction: Double) {
                if !fine, let line = snappedLine(for: r, direction: Int(direction), count: Int(n)) {
                    r.y = line.y; r.height = line.height
                } else {
                    r.y += direction * move * n
                }
            }
            if keymap.rulerDown.has(key) || (fine && keymap.rulerDown.has(base)) { step(1) }
            else if keymap.rulerUp.has(key) || (fine && keymap.rulerUp.has(base)) { step(-1) }
            else if keymap.rulerGrow.has(key) || (fine && keymap.rulerGrow.has(base)) { r.height += resize * n }
            else if keymap.rulerShrink.has(key) || (fine && keymap.rulerShrink.has(base)) { r.height -= resize * n }
            else { break }
            r.height = max(8, r.height)
            r.y = min(max(r.y, screen.y), screen.maxY)
            ruler = r
            return [.redraw]
        }
        return count == nil ? [] : [.redraw]
    }

    /// A key went up. Scroll and nudge keys end their held movement; everything else is ignored.
    public func handleRelease(_ key: KeyPress) -> [Effect] {
        let bare = KeyPress(key.code)
        switch state {
        case .active(.scroll, _):
            let keys = keymap.scrollDown.union(keymap.scrollUp).union(keymap.scrollLeft).union(keymap.scrollRight)
            return keys.has(bare) || keys.has(key) ? [.scrollStop] : []
        case .active(.nudge, _):
            guard heldNudges.removeValue(forKey: key.code) != nil else { return [] }
            return [heldNudges.isEmpty ? .nudgeStop : nudgeEffect(multiplier: 1)]
        default:
            return []
        }
    }

    private func makeRuler() -> Ruler {
        var r = Ruler(screenIndex: screenIndex, x: target.x, y: target.y, height: rulerDefaultHeight)
        if let line = snappedLine(for: r, direction: 0) { r.y = line.y; r.height = line.height }
        return r
    }

    /// Centre and height for the band on the text line `count` lines from the current one
    /// (0: the line under it), padded; nil when snapping is off or no text is there.
    private func snappedLine(for r: Ruler, direction: Int, count: Int = 1) -> (y: Double, height: Double)? {
        guard rulerSnap, let provider = lineProvider else { return nil }
        let screen = screens[r.screenIndex]
        var y = r.y
        var found: Rect?
        for _ in 0..<max(1, count) {
            guard let line = provider.textLine(at: r.x, y: y, direction: direction, on: screen) else { break }
            found = line
            y = line.midY
            if direction == 0 { break }
        }
        guard let line = found else { return nil }
        return (line.midY, line.height + 2 * rulerPad)
    }

    /// Combined direction of the held nudge keys, normalised so a diagonal is no faster.
    private func nudgeEffect(multiplier: Double) -> Effect {
        var dx = 0.0, dy = 0.0
        for d in heldNudges.values { dx += d.dx; dy += d.dy }
        let len = (dx * dx + dy * dy).squareRoot()
        if len > 0 { dx /= len; dy /= len }
        return .nudgeStart(dx: dx, dy: dy, multiplier: multiplier)
    }

    /// The platform moved the pointer on its own (a held nudge); keep the target in step.
    public func pointerMoved(to p: Point) {
        target = p
    }

    /// Click keys match on key code only; held modifiers are passed into the click.
    /// A count prefix sets the click count (3⏎ triple-clicks); it is capped at 3.
    private func clickEffects(for key: KeyPress, count: Int?) -> [Effect]? {
        let bare = KeyPress(key.code)
        let mods = key.modifiers
        let clicks = min(count ?? 1, 3)
        if keymap.leftClick.has(bare) { return clickAndExit(.left, count: clicks, mods) }
        if keymap.doubleClick.has(bare) { return clickAndExit(.left, count: 2, mods) }
        if keymap.rightClick.has(bare) { return clickAndExit(.right, count: 1, mods) }
        if keymap.middleClick.has(bare) { return clickAndExit(.middle, count: 1, mods) }
        if keymap.clickStay.has(bare) { return [.click(.left, count: clicks, modifiers: mods)] }
        return nil
    }

    private func clickAndExit(_ button: MouseButton, count: Int, _ mods: Modifiers) -> [Effect] {
        var fx: [Effect] = []
        if dragging {
            // A click while dragging ends the drag at the current spot.
            dragging = false
            dragOrigin = nil
            fx.append(.mouseUp(.left))
        } else {
            fx.append(.click(button, count: count, modifiers: mods))
        }
        state = .idle
        fx.append(ruler == nil ? .hideOverlay : .redraw)
        return fx
    }

    /// Restart the bisect at another screen's root. No-op for an invalid index.
    private func switchScreen(to index: Int) -> [Effect] {
        guard screens.indices.contains(index), index != screenIndex, case .active(let mode, _) = state else { return [] }
        screenIndex = index
        let s = BisectSession(root: screens[index])
        state = .active(mode: mode, session: s)
        snapProvider?.prepare(screen: screens[index])
        return [.warp(aim(s.current)), .redraw]
    }

    // MARK: Discoverability

    /// The keys valid right now, for the status strip. Labels come from the bindings,
    /// so a rebind (j -> down arrow) shows as "↓" here and inside the rectangles.
    public var hints: [(key: String, action: String)] {
        guard case .active(let mode, let s) = state else { return [] }
        let k = keymap
        func l(_ set: Set<KeyPress>) -> String { KeyMap.label(of: set) }
        var h: [(key: String, action: String)] = []
        switch mode {
        case .pointer:
            let quads = [Quadrant.topLeft, .topRight, .bottomLeft, .bottomRight].map { k.label(for: $0) }.joined()
            h.append((quads, "pick"))
            if s.depth > 0 { h.append((l(k.up), "up")); h.append((l(k.top), "top")) }
            h.append((l(k.leftClick), "click"))
            h.append((l(k.clickStay), "click+stay"))
            h.append((l(k.rightClick), "right"))
            h.append((l(k.doubleClick), "double"))
            h.append((l(k.dragToggle), dragging ? "drop" : "drag"))
            h.append((l(k.nudgeToggle), "nudge"))
            h.append((l(k.scrollToggle), "scroll"))
            h.append((l(k.rulerToggle), "ruler"))
            if snapProvider != nil { h.append((l(k.snapToggle), snapping ? "snap on" : "snap off")) }
        case .nudge:
            h.append((l(k.nudgeLeft) + l(k.nudgeDown) + l(k.nudgeUp) + l(k.nudgeRight), "move (hold: faster, two: diagonal)"))
            h.append(("⇧", "1px"))
            h.append((l(k.leftClick), "click"))
            h.append((l(k.clickStay), "click+stay"))
            h.append((l(k.dragToggle), dragging ? "drop" : "drag"))
            h.append((l(k.nudgeToggle), "quadrants"))
        case .scroll:
            h.append((l(k.scrollDown) + l(k.scrollUp) + " " + l(k.scrollLeft) + l(k.scrollRight), "scroll"))
            h.append((l(k.scrollHalfDown) + " " + l(k.scrollHalfUp), "half page"))
            if let fm = k.flickWith { h.append((KeyPress(.space, fm).label.replacingOccurrences(of: "␣", with: "") + "+" + l(k.scrollDown), "flick")) }
            h.append((l(k.leftClick), "click"))
            h.append((l(k.scrollToggle), "pointer"))
            h.append((l(k.rulerToggle), "ruler"))
        case .ruler:
            h.append((l(k.rulerDown) + l(k.rulerUp), "move"))
            h.append((l(k.rulerShrink) + " " + l(k.rulerGrow), "height"))
            h.append(("⇧", "fine"))
            if lineProvider != nil { h.append((l(k.rulerSnapToggle), rulerSnap ? "lines on" : "lines off")) }
            h.append((l(k.scrollToggle), "scroll"))
            h.append((l(k.rulerToggle), "pointer"))
            h.append((l(k.rulerRemove), "remove"))
        }
        if screens.count > 1 { h.append((l(k.nextScreen) + " / n" + l(k.nextScreen), "screen")) }
        h.append((l(k.help), "help"))
        if let hold = k.hold, heldActivation {
            h.append(("release " + hold.label, dragging ? "drop+exit" : "exit"))
            h.append((k.activate.label, "pin"))
            h.append((l(k.exit), pendingCount != nil ? "cancel count" : (dragging ? "cancel drag" : "exit")))
        } else {
            h.append((l(k.exit), pendingCount != nil ? "cancel count" : (dragging ? "cancel drag" : "exit")))
        }
        return h
    }

    /// Every binding, grouped, for the hold-? help panel. The current mode's group comes first.
    public var help: [(title: String, rows: [(keys: String, action: String)])] {
        let k = keymap
        func all(_ set: Set<KeyPress>) -> String {
            set.map(\.label).sorted().joined(separator: " ")
        }
        let pointer: [(String, String)] = [
            ([Quadrant.topLeft, .topRight, .bottomLeft, .bottomRight].map { k.label(for: $0) }.joined(separator: " "), "pick top-left, top-right, bottom-left, bottom-right quadrant"),
            (all(k.up), "up one level (count: several)"),
            (all(k.top), "back to the whole screen"),
            (all(k.leftClick), "left click and exit (count: double/triple)"),
            (all(k.clickStay), "left click and stay"),
            (all(k.doubleClick), "double click and exit"),
            (all(k.rightClick), "right click and exit"),
            (all(k.middleClick), "middle click and exit"),
            ("⇧ ⌘ ⌥ + click key", "modifier click"),
            (all(k.dragToggle), "press / release left button (drag, select)"),
            (all(k.snapToggle), "toggle snapping to UI elements"),
            (all(k.rulerSnapToggle), "ruler: toggle following lines of text"),
            (all(k.nudgeToggle), "nudge mode"),
            (all(k.scrollToggle), "scroll mode"),
            (all(k.rulerToggle), "ruler mode"),
        ]
        let nudge: [(String, String)] = [
            (all(k.nudgeLeft) + " / " + all(k.nudgeRight), "move left / right \(Int(nudgeStep))px (⇧: 1px, count multiplies)"),
            (all(k.nudgeUp) + " / " + all(k.nudgeDown), "move up / down"),
            (all(k.nudgeToggle), "back to quadrants"),
        ]
        let scroll: [(String, String)] = [
            (all(k.scrollDown) + " / " + all(k.scrollUp), "scroll down / up \(Int(scrollStep))px (count multiplies)"),
            (all(k.scrollLeft) + " / " + all(k.scrollRight), "scroll left / right"),
            (all(k.scrollHalfDown) + " / " + all(k.scrollHalfUp), "half a screen down / up"),
            (all(k.scrollToggle), "back to pointer"),
        ]
        let rulerRows: [(String, String)] = [
            (all(k.rulerDown) + " / " + all(k.rulerUp), "move band down / up by its height (⇧: 1px)"),
            (all(k.rulerGrow) + " / " + all(k.rulerShrink), "taller / shorter by \(Int(rulerHeightStep))px (⇧: 1px)"),
            (all(k.rulerToggle), "back to pointer (band stays)"),
            (all(k.rulerRemove), "remove band"),
        ]
        let shared: [(String, String)] = [
            ("0-9", "count prefix for the next command"),
            (all(k.nextScreen) + " / " + all(k.previousScreen), "next / previous display (count: that display)"),
            (all(k.help), "hold for this help"),
            (all(k.exit), "exit (cancels a pending count first)"),
        ]
        var groups: [(String, [(String, String)])] = [
            ("POINTER", pointer), ("NUDGE", nudge), ("SCROLL", scroll), ("RULER", rulerRows), ("ANY MODE", shared),
        ]
        let name: String? = {
            switch mode {
            case .pointer?: return "POINTER"
            case .nudge?: return "NUDGE"
            case .scroll?: return "SCROLL"
            case .ruler?: return "RULER"
            case nil: return nil
            }
        }()
        if let name, let i = groups.firstIndex(where: { $0.0 == name }) { groups.insert(groups.remove(at: i), at: 0) }
        return groups.map { (title: $0.0, rows: $0.1.map { (keys: $0.0, action: $0.1) }) }
    }
}
