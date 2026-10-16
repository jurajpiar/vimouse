#if canImport(AppKit)
import AppKit
import VimouseCore

/// Wires the pure engine to the platform: event tap in, effects out.
final class Controller {
    private let engine = PointerEngine(keymap: .default)
    private let tap = InputTap()
    private let overlay = Overlay()

    func start() throws {
        tap.handler = { [weak self] key, isDown, isRepeat in
            guard let self else { return false }
            return self.handleKey(key, isDown: isDown, isRepeat: isRepeat)
        }
        try tap.start()
    }

    func stop() {
        apply(engine.deactivate())
        tap.stop()
    }

    func activateFromMenu() {
        activate()
    }

    // Runs on the event-tap callback (main run loop). Must be fast.
    private func handleKey(_ key: KeyPress, isDown: Bool, isRepeat: Bool) -> Bool {
        if !engine.isActive {
            guard key == engine.keymap.activate, isDown, !isRepeat else { return false }
            activate()
            return true
        }
        // Active: swallow everything so the focused app sees nothing, act on key-down only.
        guard isDown, !isRepeat else { return true }
        apply(engine.handle(key))
        return true
    }

    private func activate() {
        let mouse = NSEvent.mouseLocation
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        let index = screens.firstIndex { NSMouseInRect(mouse, $0.frame, false) } ?? 0
        apply(engine.activate(screens: screens.map { Coordinates.cgRect(fromAppKit: $0.frame) }, index: index))
    }

    private func apply(_ effects: [Effect]) {
        for effect in effects {
            switch effect {
            case .showOverlay:
                if let m = model() { overlay.show(m) }
            case .redraw:
                if let m = model() { overlay.update(m) }
            case .hideOverlay:
                overlay.hide()
            case .warp(let p):
                Pointer.warp(to: p)
            case .click(let button, let count):
                Pointer.click(button, count: count, at: Pointer.currentLocation)
            }
        }
    }

    private func model() -> OverlayModel? {
        guard let s = engine.session else { return nil }
        var labels: [Quadrant: String] = [:]
        for q in Quadrant.allCases { labels[q] = engine.keymap.label(for: q) }
        return OverlayModel(
            current: s.current,
            ancestors: Array(s.ancestors),
            labels: labels,
            screens: engine.screens,
            activeScreen: engine.screenIndex
        )
    }
}
#endif
