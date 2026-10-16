#if canImport(AppKit)
import AppKit
import VimouseCore

/// Wires the pure engine to the platform: event tap in, effects out.
final class Controller {
    private let snapper = AXSnapper()
    private let lines = AXLineProvider()
    private let engine: PointerEngine
    private let tap = InputTap()
    private let overlay = Overlay()
    private let scroller = ScrollDriver()
    private let nudger = NudgeDriver()
    private var dragRamp = false
    private var activateMode: String
    private var holdMode: String
    /// Modifiers that flick in Scroll mode; releasing them brakes a coast.
    private var flickWith: Modifiers?
    /// True while the help key is held.
    private var helpShown = false

    enum Health: Equatable { case ok, noPermission, secureInput }
    private(set) var health: Health = .ok
    /// Called whenever `health` changes (menu bar shows it).
    var onHealthChange: ((Health) -> Void)?
    private var healthTimer: Timer?
    private var tapRunning = false

    init(modes: [Mode], cursors: [CursorStyle]) {
        engine = PointerEngine(modes: modes, cursors: cursors)
        engine.context.services.snap = snapper
        engine.context.services.lines = lines
        activateMode = engine.defaultMode
        holdMode = engine.defaultMode
    }

    /// Called on load and on every reload of config.toml.
    func apply(_ config: Config) {
        engine.apply(config)
        // The drivers take their tunables from whichever mode provides them.
        if let s = config.modeSettings.values.first(where: { $0 is ScrollTunables }) as? ScrollTunables {
            scroller.step = s.step
            scroller.speed = s.speed
            scroller.acceleration = s.acceleration
            scroller.momentum = s.momentum
            scroller.smooth = s.smooth
            scroller.flick = s.flick
            scroller.friction = s.friction
            scroller.doubleTapFlicks = s.flickDoubleTapEnabled
            flickWith = s.flickWith
        }
        if let n = config.modeSettings.values.first(where: { $0 is NudgeTunables }) as? NudgeTunables {
            nudger.step = n.step
            nudger.speed = n.speed
            nudger.acceleration = n.acceleration
        }
        dragRamp = config.dragRamp
        activateMode = config.activateMode
        holdMode = config.holdMode
        overlay.render(model())
    }

    /// Starts the event tap if allowed; either way the health monitor runs and will
    /// start (or restart) the tap once Accessibility access is there.
    func start() {
        nudger.onMove = { [weak self] p in
            guard let self else { return }
            engine.pointerMoved(to: p)
            overlay.render(model())
        }
        tap.handler = { [weak self] key, isDown, isRepeat, isModifier, bothSides in
            guard let self else { return false }
            if isModifier { return self.handleModifier(key, isDown: isDown) }
            return self.handleKey(key, isDown: isDown, isRepeat: isRepeat, bothSides: bothSides)
        }
        do {
            try tap.start()
            tapRunning = true
            NSLog("vimouse: ready")
        } catch {
            tapRunning = false
            health = .noPermission
            onHealthChange?(health)
            NSLog("vimouse: waiting for Accessibility access (System Settings > Privacy & Security > Accessibility)")
        }
        startHealthMonitor()
    }

    func stop() {
        healthTimer?.invalidate()
        scroller.stop()
        apply(engine.deactivate())
        tap.stop()
        tapRunning = false
    }

    /// Every second: secure input state; every third tick: can we still filter events?
    /// Losing Accessibility access with a live filtering tap can leave the whole system
    /// unable to click, so the tap comes down the moment the probe fails and goes back
    /// up when access returns.
    private func startHealthMonitor() {
        var tick = 0
        healthTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            tick += 1
            if tick % 3 == 0 {
                let allowed = Permissions.canFilterEvents()
                if tapRunning, !allowed {
                    NSLog("vimouse: Accessibility access lost; stopping the event tap")
                    scroller.stop()
                    apply(engine.deactivate())
                    tap.stop()
                    tapRunning = false
                } else if !tapRunning, allowed, (try? tap.start()) != nil {
                    NSLog("vimouse: Accessibility access back; event tap restarted")
                    tapRunning = true
                }
            }
            let secure = Permissions.secureInputActive
            if secure, engine.isActive {
                scroller.stop()
                apply(engine.deactivate()) // keys would never reach us; do not leave the overlay stuck
            }
            let now: Health = !tapRunning ? .noPermission : (secure ? .secureInput : .ok)
            if now != health {
                health = now
                onHealthChange?(now)
            }
        }
    }

    func activateFromMenu() {
        activate()
    }

    /// Quasi-mode: the hold key enters Pointer mode on press and leaves on release.
    /// Other modifier changes pass through.
    private func handleModifier(_ key: KeyPress, isDown: Bool) -> Bool {
        // Releasing the flick modifier while the page coasts brakes it.
        if !isDown, scroller.isCoasting, let fm = flickWith,
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
            // A held scroll or nudge key must end its movement whatever mode we are in by now.
            if scroller.isHeld { scroller.stop() }
            if nudger.isHeld { nudger.stop() }
            apply(engine.handleRelease(key))
            return true
        }
        // Key repeat is useful for some modes (moving the ruler), not for others (picking
        // quadrants); a key the drivers hold is theirs, not the repeat's.
        if isRepeat, !(engine.activeMode?.acceptsKeyRepeat ?? true) || nudger.isHeld || scroller.isHeld { return true }
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
            case .nudgeStart(let dx, let dy, let multiplier):
                nudger.start(dx: dx, dy: dy, multiplier: multiplier, from: engine.target,
                             within: engine.screens[engine.screenIndex], dragging: engine.dragging)
            case .nudgeStop:
                nudger.stop()
            }
        }
        if !engine.isActive { if scroller.isHeld { scroller.stop() }; nudger.stop() }
    }

    /// nil when there is nothing to draw.
    private func model() -> Scene? {
        engine.scene(showHelp: helpShown)
    }
}
#endif
