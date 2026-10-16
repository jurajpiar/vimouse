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
    case click(MouseButton, count: Int)
}

/// Modal state machine for Pointer mode. Pure: no platform calls, fully testable.
public final class PointerEngine {
    public enum State: Equatable {
        case idle
        case bisect(BisectSession)
    }

    /// All displays (CG coordinates) and which one the session is on.
    public private(set) var screens: [Rect] = []
    public private(set) var screenIndex: Int = 0

    public private(set) var state: State = .idle
    public let keymap: KeyMap

    public init(keymap: KeyMap = .default) {
        self.keymap = keymap
    }

    public var isActive: Bool {
        if case .idle = state { return false }
        return true
    }

    public var session: BisectSession? {
        if case .bisect(let s) = state { return s }
        return nil
    }

    /// Enter Pointer mode over `screens[index]` (CG coordinates).
    public func activate(screens: [Rect], index: Int) -> [Effect] {
        precondition(!screens.isEmpty && screens.indices.contains(index))
        self.screens = screens
        screenIndex = index
        let s = BisectSession(root: screens[index])
        state = .bisect(s)
        return [.showOverlay, .warp(s.current.center)]
    }

    /// Convenience for a single screen.
    public func activate(screen: Rect) -> [Effect] {
        activate(screens: [screen], index: 0)
    }

    /// Restart the bisect at another screen's root. No-op for an invalid index.
    private func switchScreen(to index: Int) -> [Effect] {
        guard screens.indices.contains(index), index != screenIndex else { return [] }
        screenIndex = index
        let s = BisectSession(root: screens[index])
        state = .bisect(s)
        return [.warp(s.current.center), .redraw]
    }

    public func deactivate() -> [Effect] {
        state = .idle
        return [.hideOverlay]
    }

    /// Handle a key press while active. Returns the effects to apply.
    /// Unbound keys are swallowed and produce no effects.
    public func handle(_ key: KeyPress) -> [Effect] {
        guard case .bisect(var s) = state else { return [] }

        if let q = keymap.quadrants[key] {
            s.select(q)
            state = .bisect(s)
            return [.warp(s.current.center), .redraw]
        }
        if keymap.up.contains(key) {
            guard s.up() else { return [] }
            state = .bisect(s)
            return [.warp(s.current.center), .redraw]
        }
        if keymap.leftClick.contains(key) {
            return clickAndExit(.left)
        }
        if keymap.rightClick.contains(key) {
            return clickAndExit(.right)
        }
        if keymap.middleClick.contains(key) {
            return clickAndExit(.middle)
        }
        if keymap.exit.contains(key) {
            return deactivate()
        }
        if keymap.nextScreen.contains(key) {
            return switchScreen(to: (screenIndex + 1) % screens.count)
        }
        if keymap.previousScreen.contains(key) {
            return switchScreen(to: (screenIndex - 1 + screens.count) % screens.count)
        }
        if let i = keymap.screens[key] {
            return switchScreen(to: i)
        }
        return []
    }

    private func clickAndExit(_ button: MouseButton) -> [Effect] {
        state = .idle
        return [.click(button, count: 1), .hideOverlay]
    }
}
