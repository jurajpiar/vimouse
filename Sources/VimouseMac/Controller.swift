#if canImport(AppKit)
import AppKit
import VimouseCore

/// Wires the pure engine to the platform: event tap in, effects out.
final class Controller {
    private let snapper = AXSnapper()
    private let engine: PointerEngine
    private let tap = InputTap()
    private let overlay = Overlay()
    private var rulerDim: Double = Config().rulerDim
    /// True while the help key is held.
    private var helpShown = false

    init() {
        engine = PointerEngine(keymap: .default, snapping: true, snapProvider: snapper)
    }

    /// Called on load and on every reload of config.toml.
    func apply(_ config: Config) {
        engine.apply(config)
        rulerDim = config.rulerDim
        overlay.render(model())
    }

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
        // Active: swallow everything so the focused app sees nothing.
        // The help key works on hold: shown on key down, hidden on key up.
        // On key up the modifier may already be released, so match the key code alone.
        let isHelp = engine.keymap.help.contains(key) || (!isDown && engine.keymap.help.contains { $0.code == key.code })
        if isHelp {
            if isRepeat { return true }
            helpShown = isDown
            overlay.render(model())
            return true
        }
        guard isDown else { return true }
        // Key repeat is useful for scrolling, nudging and moving the ruler, not for picking quadrants.
        if isRepeat, engine.mode == .pointer { return true }
        apply(engine.handle(key))
        return true
    }

    private func activate() {
        helpShown = false
        let mouse = NSEvent.mouseLocation
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        let index = screens.firstIndex { NSMouseInRect(mouse, $0.frame, false) } ?? 0
        apply(engine.activate(screens: screens.map { Coordinates.cgRect(fromAppKit: $0.frame) }, index: index))
    }

    private func apply(_ effects: [Effect]) {
        for effect in effects {
            switch effect {
            case .showOverlay, .redraw, .hideOverlay:
                overlay.render(model())
            case .warp(let p):
                Pointer.warp(to: p, dragging: engine.dragging)
            case .click(let button, let count, let modifiers):
                Pointer.click(button, count: count, modifiers: modifiers, at: Pointer.currentLocation)
            case .mouseDown(let button):
                Pointer.mouseDown(button, at: Pointer.currentLocation)
            case .mouseUp(let button):
                Pointer.mouseUp(button, at: Pointer.currentLocation)
            case .scroll(let dx, let dy):
                Pointer.scroll(dx: dx, dy: dy)
            }
        }
    }

    /// nil when there is nothing to draw.
    private func model() -> OverlayModel? {
        guard engine.needsOverlay else { return nil }
        var pointer: PointerModel?
        if let s = engine.session, let mode = engine.mode {
            var labels: [Quadrant: String] = [:]
            for q in Quadrant.allCases { labels[q] = engine.keymap.label(for: q) }
            pointer = PointerModel(
                mode: mode,
                current: s.current,
                ancestors: Array(s.ancestors),
                labels: labels,
                dragging: engine.dragging,
                pendingCount: engine.pendingCount,
                target: engine.target,
                snapping: engine.snapping,
                hints: engine.hints,
                help: helpShown ? engine.help : nil
            )
        }
        let ruler = engine.ruler.map { RulerModel(screenIndex: $0.screenIndex, band: $0.band(on: engine.screens[$0.screenIndex]), dim: rulerDim) }
        return OverlayModel(pointer: pointer, ruler: ruler, screens: engine.screens, activeScreen: engine.screenIndex)
    }
}
#endif
