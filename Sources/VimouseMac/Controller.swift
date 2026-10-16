#if canImport(AppKit)
import AppKit
import VimouseCore

/// Wires the pure engine to the platform: event tap in, effects out.
final class Controller {
    private let snapper = AXSnapper()
    private let engine: PointerEngine
    private let tap = InputTap()
    private let overlay = Overlay()
    private let scroller = ScrollDriver()
    private var rulerDim: Double = Config().rulerDim
    private var colours = Colours()
    private var dragRamp = false
    private var activateMode: Mode = .pointer
    private var holdMode: Mode = .pointer
    /// True while the help key is held.
    private var helpShown = false

    init() {
        engine = PointerEngine(keymap: .default, snapping: true, snapProvider: snapper)
    }

    /// Called on load and on every reload of config.toml.
    func apply(_ config: Config) {
        engine.apply(config)
        rulerDim = config.rulerDim
        scroller.step = config.scrollStep
        scroller.speed = config.scrollSpeed
        scroller.acceleration = config.scrollAcceleration
        scroller.momentum = config.scrollMomentum
        scroller.smooth = config.scrollSmooth
        scroller.flick = config.scrollFlick
        scroller.friction = config.scrollFriction
        scroller.doubleTapFlicks = config.flickDoubleTapEnabled
        colours = config.colours
        dragRamp = config.dragRamp
        activateMode = config.activateMode
        holdMode = config.holdMode
        overlay.render(model())
    }

    func start() throws {
        tap.handler = { [weak self] key, isDown, isRepeat, isModifier, bothSides in
            guard let self else { return false }
            if isModifier { return self.handleModifier(key, isDown: isDown) }
            return self.handleKey(key, isDown: isDown, isRepeat: isRepeat, bothSides: bothSides)
        }
        try tap.start()
    }

    func stop() {
        scroller.stop()
        apply(engine.deactivate())
        tap.stop()
    }

    func activateFromMenu() {
        activate()
    }

    /// Quasi-mode: the hold key enters Pointer mode on press and leaves on release.
    /// Other modifier changes pass through.
    private func handleModifier(_ key: KeyPress, isDown: Bool) -> Bool {
        // Releasing the flick modifier while the page coasts brakes it.
        if !isDown, scroller.isCoasting, let fm = engine.keymap.flickWith,
           let generic = key.code.modifierBit, let side = key.code.sideBit,
           !fm.intersection([generic, side]).isEmpty {
            scroller.brake()
        }
        guard let hold = engine.keymap.hold else { return false }
        // Is the trigger satisfied after this change? A specific key: that key's state.
        // A chord: every modifier of the chord present in the flags.
        let satisfied: Bool
        switch hold {
        case .key(let code):
            guard key.code == code else { return false }
            satisfied = isDown
        case .chord(let chord):
            satisfied = chord.matchesHeld(in: key.modifiers)
        }
        if satisfied {
            guard !engine.isActive else { return engine.heldActivation }
            engine.heldActivation = true
            activate()
            return true
        }
        guard engine.isActive, engine.heldActivation else { return false }
        engine.heldActivation = false
        apply(engine.deactivate())
        return true
    }

    // Runs on the event-tap callback (main run loop). Must be fast.
    private func handleKey(_ rawKey: KeyPress, isDown: Bool, isRepeat: Bool, bothSides: Modifiers) -> Bool {
        var key = rawKey
        if !engine.isActive {
            guard engine.keymap.activate.matches(event: key), isDown, !isRepeat else { return false }
            engine.heldActivation = false
            activate()
            return true
        }
        // The hotkey while active: pins a quasi-mode activation (it then survives the
        // release of the hold key), or leaves a pinned or hotkey-started one.
        if engine.keymap.activate.matches(event: rawKey), isDown, !isRepeat {
            if engine.heldActivation {
                // Pin, and take the hotkey's own start mode.
                engine.heldActivation = false
                apply(engine.enter(mode: activateMode))
                overlay.render(model())
            } else {
                apply(engine.deactivate())
            }
            return true
        }
        // While the hold key is down, its own modifiers are not part of what the user
        // typed, unless the other side of that modifier is down too: a hyper key on the
        // left plus right Shift still means Shift.
        if engine.heldActivation, let bits = engine.keymap.hold?.bits {
            // Strip the chord's modifiers (generic form) except those held on both sides.
            key = KeyPress(key.code, key.modifiers.subtracting(bits.generic.subtracting(bothSides)))
        }
        // Active: swallow everything so the focused app sees nothing.
        // The help key works on hold: shown on key down, hidden on key up.
        // On key up the modifier may already be released, so match the key code alone.
        let isHelp = engine.keymap.help.has(key) || (!isDown && engine.keymap.help.contains { $0.code == key.code })
        if isHelp {
            if isRepeat { return true }
            helpShown = isDown
            overlay.render(model())
            return true
        }
        guard isDown else {
            // A held scroll key must end its gesture whatever mode we are in by now.
            if scroller.isHeld { scroller.stop() }
            apply(engine.handleRelease(key))
            return true
        }
        // Key repeat is useful for nudging and moving the ruler, not for picking quadrants;
        // a held scroll key is driven by the scroller, not by repeats.
        if isRepeat, engine.mode == .pointer || (engine.mode == .scroll && scroller.smooth) { return true }
        apply(engine.handle(key))
        return true
    }

    private func activate() {
        helpShown = false
        let mouse = NSEvent.mouseLocation
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        let index = screens.firstIndex { NSMouseInRect(mouse, $0.frame, false) } ?? 0
        apply(engine.activate(
            screens: screens.map { Coordinates.cgRect(fromAppKit: $0.frame) },
            index: index,
            pointer: Coordinates.cgPoint(fromAppKit: mouse),
            mode: engine.heldActivation ? holdMode : activateMode
        ))
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
            case .mouseDown(.left):
                Pointer.startDrag(at: Pointer.currentLocation, ramp: dragRamp)
            case .mouseUp(.left):
                Pointer.endDrag(at: Pointer.currentLocation)
            case .mouseDown(let button):
                Pointer.mouseDown(button, at: Pointer.currentLocation)
            case .mouseUp(let button):
                Pointer.mouseUp(button, at: Pointer.currentLocation)
            case .cancelDrag(let origin):
                Pointer.cancelDrag(origin: origin)
            case .scroll(let dx, let dy):
                scroller.brake()
                Pointer.scroll(dx: dx, dy: dy)
            case .scrollStart(let dx, let dy, let multiplier):
                scroller.start(dx: dx, dy: dy, multiplier: multiplier)
            case .scrollStop:
                scroller.stop()
            case .scrollFlick(let dx, let dy, let multiplier):
                scroller.flickNow(dx: dx, dy: dy, multiplier: multiplier)
            }
        }
        if !engine.isActive, scroller.isHeld { scroller.stop() }
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
                dragOrigin: engine.dragOrigin,
                pendingCount: engine.pendingCount,
                target: engine.target,
                snapping: engine.snapping,
                hints: engine.hints,
                help: helpShown ? engine.help : nil
            )
        }
        let ruler = engine.ruler.map { RulerModel(screenIndex: $0.screenIndex, band: $0.band(on: engine.screens[$0.screenIndex]), dim: rulerDim) }
        return OverlayModel(pointer: pointer, ruler: ruler, colours: colours, screens: engine.screens, activeScreen: engine.screenIndex)
    }
}
#endif
