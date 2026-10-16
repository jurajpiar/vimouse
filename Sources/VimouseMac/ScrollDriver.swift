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

    /// A press shorter than this is a tap (one step); longer is a hold.
    private let tapWindow: TimeInterval = 0.15
    private let frame: TimeInterval = 1.0 / 60
    private let decayPerFrame = 0.94
    private let stopSpeed = 30.0

    private var timer: Timer?
    private var direction = (dx: 0.0, dy: 0.0)
    private var multiplier = 1.0
    private var held = false
    private var pressedAt = Date()
    private var velocity = 0.0
    private var coasting = false
    private var carry = (x: 0.0, y: 0.0)

    var isHeld: Bool { held }

    func start(dx: Double, dy: Double, multiplier: Double) {
        // A new press interrupts whatever gesture is running.
        if timer != nil {
            if coasting { post(0, 0, momentum: .end) } else { post(0, 0, phase: .ended) }
            finish()
        }
        direction = (dx, dy)
        self.multiplier = multiplier
        held = true
        pressedAt = Date()
        velocity = 0
        carry = (0, 0)
        if !smooth {
            Pointer.scroll(dx: dx * step * multiplier, dy: dy * step * multiplier)
            return
        }
        // The tap: one step straight away, as the gesture begins.
        post(dx * step * multiplier, dy * step * multiplier, phase: .began)
        timer = Timer.scheduledTimer(withTimeInterval: frame, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        guard held else { return }
        held = false
        if !smooth { return }
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
            let ramp = min(1, (t - tapWindow) / acceleration)
            velocity = speed * multiplier * (0.25 + 0.75 * ramp)
            post(direction.dx * velocity * frame, direction.dy * velocity * frame, phase: .changed)
        } else if coasting {
            velocity *= decayPerFrame
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
