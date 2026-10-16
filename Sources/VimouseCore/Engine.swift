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

    /// Enter Pointer mode over the given screen rectangle (CG coordinates).
    public func activate(screen: Rect) -> [Effect] {
        let s = BisectSession(root: screen)
        state = .bisect(s)
        return [.showOverlay, .warp(s.current.center)]
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
        return []
    }

    private func clickAndExit(_ button: MouseButton) -> [Effect] {
        state = .idle
        return [.click(button, count: 1), .hideOverlay]
    }
}
