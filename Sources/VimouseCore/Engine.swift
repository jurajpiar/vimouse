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
    /// Pixels. Positive dy reveals content below (like vim's j), positive dx content to the right.
    case scroll(dx: Double, dy: Double)
}

public enum Mode: Equatable, Sendable {
    case pointer, scroll
}

/// Modal state machine for Pointer mode. Pure: no platform calls, fully testable.
public final class PointerEngine {
    public enum State: Equatable {
        case idle
        case active(mode: Mode, session: BisectSession)
    }

    public private(set) var state: State = .idle
    public let keymap: KeyMap

    /// All displays (CG coordinates) and which one the session is on.
    public private(set) var screens: [Rect] = []
    public private(set) var screenIndex: Int = 0
    /// Left button currently held by a `v` drag.
    public private(set) var dragging = false

    /// Vertical/horizontal scroll per j/k/h/l press, in pixels.
    public var scrollStep: Double = 60

    public init(keymap: KeyMap = .default) {
        self.keymap = keymap
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

    // MARK: Activation

    /// Enter Pointer mode over `screens[index]` (CG coordinates).
    public func activate(screens: [Rect], index: Int) -> [Effect] {
        precondition(!screens.isEmpty && screens.indices.contains(index))
        self.screens = screens
        screenIndex = index
        let s = BisectSession(root: screens[index])
        state = .active(mode: .pointer, session: s)
        return [.showOverlay, .warp(s.current.center)]
    }

    /// Convenience for a single screen.
    public func activate(screen: Rect) -> [Effect] {
        activate(screens: [screen], index: 0)
    }

    /// Leave Pointer mode, releasing a held drag first.
    public func deactivate() -> [Effect] {
        state = .idle
        var fx: [Effect] = []
        if dragging {
            dragging = false
            fx.append(.mouseUp(.left))
        }
        fx.append(.hideOverlay)
        return fx
    }

    // MARK: Keys

    /// Handle a key press while active. Returns the effects to apply.
    /// Unbound keys are swallowed and produce no effects.
    public func handle(_ key: KeyPress) -> [Effect] {
        guard case .active(let mode, var s) = state else { return [] }

        // Shared across modes.
        if keymap.exit.contains(key) { return deactivate() }
        if keymap.scrollToggle.contains(key) {
            state = .active(mode: mode == .scroll ? .pointer : .scroll, session: s)
            return [.redraw]
        }
        if keymap.dragToggle.contains(key) {
            dragging.toggle()
            return [dragging ? .mouseDown(.left) : .mouseUp(.left), .redraw]
        }
        if let fx = clickEffects(for: key) { return fx }
        if keymap.nextScreen.contains(key) {
            return switchScreen(to: (screenIndex + 1) % screens.count)
        }
        if keymap.previousScreen.contains(key) {
            return switchScreen(to: (screenIndex - 1 + screens.count) % screens.count)
        }
        if let i = keymap.screens[key] {
            return switchScreen(to: i)
        }

        switch mode {
        case .pointer:
            if let q = keymap.quadrants[key] {
                s.select(q)
                state = .active(mode: .pointer, session: s)
                return [.warp(s.current.center), .redraw]
            }
            if keymap.up.contains(key) {
                guard s.up() else { return [] }
                state = .active(mode: .pointer, session: s)
                return [.warp(s.current.center), .redraw]
            }
        case .scroll:
            let half = screens[screenIndex].height / 2
            if keymap.scrollDown.contains(key) { return [.scroll(dx: 0, dy: scrollStep)] }
            if keymap.scrollUp.contains(key) { return [.scroll(dx: 0, dy: -scrollStep)] }
            if keymap.scrollLeft.contains(key) { return [.scroll(dx: -scrollStep, dy: 0)] }
            if keymap.scrollRight.contains(key) { return [.scroll(dx: scrollStep, dy: 0)] }
            if keymap.scrollHalfDown.contains(key) { return [.scroll(dx: 0, dy: half)] }
            if keymap.scrollHalfUp.contains(key) { return [.scroll(dx: 0, dy: -half)] }
        }
        return []
    }

    /// Click keys match on key code only; held modifiers are passed into the click.
    private func clickEffects(for key: KeyPress) -> [Effect]? {
        let bare = KeyPress(key.code)
        let mods = key.modifiers
        if keymap.leftClick.contains(bare) { return clickAndExit(.left, count: 1, mods) }
        if keymap.doubleClick.contains(bare) { return clickAndExit(.left, count: 2, mods) }
        if keymap.rightClick.contains(bare) { return clickAndExit(.right, count: 1, mods) }
        if keymap.middleClick.contains(bare) { return clickAndExit(.middle, count: 1, mods) }
        if keymap.clickStay.contains(bare) { return [.click(.left, count: 1, modifiers: mods)] }
        return nil
    }

    private func clickAndExit(_ button: MouseButton, count: Int, _ mods: Modifiers) -> [Effect] {
        var fx: [Effect] = []
        if dragging {
            // A click while dragging ends the drag at the current spot.
            dragging = false
            fx.append(.mouseUp(.left))
        } else {
            fx.append(.click(button, count: count, modifiers: mods))
        }
        state = .idle
        fx.append(.hideOverlay)
        return fx
    }

    /// Restart the bisect at another screen's root. No-op for an invalid index.
    private func switchScreen(to index: Int) -> [Effect] {
        guard screens.indices.contains(index), index != screenIndex, case .active(let mode, _) = state else { return [] }
        screenIndex = index
        let s = BisectSession(root: screens[index])
        state = .active(mode: mode, session: s)
        return [.warp(s.current.center), .redraw]
    }

    // MARK: Discoverability

    /// The keys valid right now, for the status strip.
    public var hints: [(key: String, action: String)] {
        guard case .active(let mode, let s) = state else { return [] }
        var h: [(key: String, action: String)] = []
        switch mode {
        case .pointer:
            h.append(("iojk", "pick"))
            if s.depth > 0 { h.append(("⌫", "up")) }
            h.append(("⏎", "click"))
            h.append(("␣", "click+stay"))
            h.append((".", "right"))
            h.append(("x", "double"))
            h.append(("v", dragging ? "drop" : "drag"))
            h.append(("s", "scroll"))
        case .scroll:
            h.append(("jk hl", "scroll"))
            h.append(("d u", "half page"))
            h.append(("⏎", "click"))
            h.append(("s", "pointer"))
        }
        if screens.count > 1 { h.append(("⇥ 1-\(screens.count)", "screen")) }
        h.append(("esc", "exit"))
        return h
    }
}
