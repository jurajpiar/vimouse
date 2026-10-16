#if canImport(AppKit)
import AppKit
import VimouseCore

/// Turns "nudge key down ... up" into pointer movement: a tap moves one step, a hold
/// ramps to full speed, release stops at once (no coasting; the pointer must stay put).
final class NudgeDriver {
    var step: Double = 5
    var speed: Double = 600
    var acceleration: Double = 0.6

    /// Called with the new pointer position on every move.
    var onMove: ((Point) -> Void)?

    private let tapWindow: TimeInterval = 0.15
    private let frame: TimeInterval = 1.0 / 60

    private var timer: Timer?
    private var direction = (dx: 0.0, dy: 0.0)
    private var multiplier = 1.0
    private var pressedAt = Date()
    private var position = Point(x: 0, y: 0)
    private var bounds = Rect(x: 0, y: 0, width: 0, height: 0)
    private var dragging = false

    var isHeld: Bool { timer != nil }

    func start(dx: Double, dy: Double, multiplier: Double, from p: Point, within screen: Rect, dragging: Bool) {
        if isHeld {
            // Another key joined or left: change course, keep the ramp going.
            direction = (dx, dy)
            self.multiplier = max(self.multiplier, multiplier)
            return
        }
        direction = (dx, dy)
        self.multiplier = multiplier
        pressedAt = Date()
        position = p
        bounds = screen
        self.dragging = dragging
        move(by: step * multiplier) // the tap
        timer = Timer.scheduledTimer(withTimeInterval: frame, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let t = Date().timeIntervalSince(pressedAt)
        guard t > tapWindow else { return }
        let ramp = min(1, (t - tapWindow) / acceleration)
        let velocity = speed * multiplier * (0.25 + 0.75 * ramp)
        move(by: velocity * frame)
    }

    private func move(by distance: Double) {
        position.x = min(max(position.x + direction.dx * distance, bounds.x), bounds.maxX - 1)
        position.y = min(max(position.y + direction.dy * distance, bounds.y), bounds.maxY - 1)
        Pointer.warp(to: position, dragging: dragging)
        onMove?(position)
    }
}
#endif
