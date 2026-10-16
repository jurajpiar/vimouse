#if canImport(AppKit)
import AppKit
import VimouseCore

/// Turns "scroll key down ... up" into trackpad-like scrolling: a quick tap scrolls one
/// step, a hold ramps to full speed, release coasts to a stop. Events carry the scroll
/// and momentum phases trackpads use, so apps animate them as their own.
final class ScrollDriver {
    var step: Double = 60
    var speed: Double = 1500
    var acceleration: Double = 0.5
    var momentum = true
    var smooth = true
    /// Speed launched by a double tap, px/s; 0 disables.
    var flick: Double = 4000
    /// Fraction of speed lost per second while coasting, 0 to 1.
    var friction: Double = 0.85
    /// Double tap of a scroll key flicks.
    var doubleTapFlicks = true

    /// A press shorter than this is a tap (one step); longer is a hold.
    private let tapWindow: TimeInterval = 0.15
    private let frame: TimeInterval = 1.0 / 60
    private let stopSpeed = 30.0

    private var timer: Timer?
    private var direction = (dx: 0.0, dy: 0.0)
    private var multiplier = 1.0
    private var held = false
    private var pressedAt = Date()
    private var velocity = 0.0
    private var coasting = false
    private var carry = (x: 0.0, y: 0.0)
    /// The gesture has posted its `began`. False during a brake tap, which scrolls nothing.
    private var begun = false
    /// Two taps of the same key within this interval are a flick.
    private let flickWindow: TimeInterval = 0.25
    private var lastTap: (at: Date, dx: Double, dy: Double)?

    var isHeld: Bool { held }
    var isCoasting: Bool { coasting }

    func start(dx: Double, dy: Double, multiplier: Double) {
        // A press while coasting is a brake, like touching the trackpad: it stops the
        // scroll and nothing else, unless the key is then held, which starts a new gesture.
        let braking = coasting
        if timer != nil {
            if coasting { post(0, 0, momentum: .end) } else { post(0, 0, phase: .ended) }
            finish()
        }
        // A second tap of the same key within the window is a flick: launch and coast.
        if doubleTapFlicks, !braking, let last = lastTap,
           last.dx == dx, last.dy == dy, Date().timeIntervalSince(last.at) < flickWindow {
            lastTap = nil
            launch(dx: dx, dy: dy, multiplier: multiplier)
            return
        }
        direction = (dx, dy)
        self.multiplier = multiplier
        held = true
        pressedAt = Date()
        velocity = 0
        carry = (0, 0)
        begun = false
        if !smooth {
            Pointer.scroll(dx: dx * step * multiplier, dy: dy * step * multiplier)
            return
        }
        if !braking {
            // The tap: one step straight away, as the gesture begins.
            post(dx * step * multiplier, dy * step * multiplier, phase: .began)
            begun = true
        }
        timer = Timer.scheduledTimer(withTimeInterval: frame, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    /// Flick on request (the flick modifier): launch a coast from a standing start.
    func flickNow(dx: Double, dy: Double, multiplier: Double) {
        if timer != nil {
            if coasting { post(0, 0, momentum: .end) } else { post(0, 0, phase: .ended) }
            finish()
        }
        launch(dx: dx, dy: dy, multiplier: multiplier)
    }

    private func launch(dx: Double, dy: Double, multiplier: Double) {
        guard smooth, momentum, flick > 0 else {
            Pointer.scroll(dx: dx * step * multiplier * 4, dy: dy * step * multiplier * 4)
            return
        }
        direction = (dx, dy)
        carry = (0, 0)
        post(0, 0, phase: .began)
        post(0, 0, phase: .ended)
        velocity = flick * multiplier
        coasting = true
        post(0, 0, momentum: .begin)
        timer = Timer.scheduledTimer(withTimeInterval: frame, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    /// Stop a coast without starting anything (used before a half-page jump).
    func brake() {
        guard coasting else { return }
        post(0, 0, momentum: .end)
        finish()
    }

    func stop() {
        guard held else { return }
        held = false
        if !smooth { return }
        guard begun else { finish(); return } // a brake tap: nothing to end
        // Remember a tap (no ramp happened) so a second one can become a flick.
        lastTap = velocity == 0 ? (Date(), direction.dx, direction.dy) : nil
        post(0, 0, phase: .ended)
        if momentum, velocity > stopSpeed {
            coasting = true
            post(0, 0, momentum: .begin)
        } else {
            finish()
        }
    }

    private func tick() {
        if held {
            let t = Date().timeIntervalSince(pressedAt)
            guard t > tapWindow else { return }
            // Ramp from a quarter of full speed to full speed over `acceleration` seconds.
            if !begun {
                post(0, 0, phase: .began)
                begun = true
            }
            let ramp = min(1, (t - tapWindow) / acceleration)
            velocity = speed * multiplier * (0.25 + 0.75 * ramp)
            post(direction.dx * velocity * frame, direction.dy * velocity * frame, phase: .changed)
        } else if coasting {
            velocity *= pow(1 - min(max(friction, 0.01), 0.999), frame)
            if velocity < stopSpeed {
                post(0, 0, momentum: .end)
                finish()
                return
            }
            post(direction.dx * velocity * frame, direction.dy * velocity * frame, momentum: .continuous)
        } else {
            finish()
        }
    }

    /// Clears the gesture state; the closing event has been posted by the caller.
    private func finish() {
        timer?.invalidate()
        timer = nil
        held = false
        coasting = false
        velocity = 0
        begun = false
    }

    private enum Phase: Int64 { case began = 1, changed = 2, ended = 4 }
    private enum Momentum: Int64 { case begin = 1, continuous = 2, end = 3 }

    private func post(_ dx: Double, _ dy: Double, phase: Phase? = nil, momentum: Momentum? = nil) {
        // Whole pixels per event; keep the remainder so slow speeds still move.
        carry.x += dx
        carry.y += dy
        let ix = carry.x.rounded(.towardZero), iy = carry.y.rounded(.towardZero)
        carry.x -= ix
        carry.y -= iy
        Pointer.scrollContinuous(dx: ix, dy: iy, phase: phase?.rawValue ?? 0, momentum: momentum?.rawValue ?? 0)
    }
}
#endif
