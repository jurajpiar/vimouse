#if canImport(AppKit)
import AppKit
import VimouseCore

/// What the overlay draws, in Core (CG) coordinates.
struct OverlayModel {
    var current: Rect
    var ancestors: [Rect]
    var labels: [Quadrant: String]
}

/// One transparent, click-through panel per display, above everything including
/// full-screen apps. Each panel draws only the part of the model on its display.
final class Overlay {
    private var panels: [OverlayPanel] = []

    func show(_ model: OverlayModel) {
        if panels.isEmpty || panels.count != NSScreen.screens.count { rebuild() }
        update(model)
        panels.forEach { $0.orderFrontRegardless() }
    }

    func update(_ model: OverlayModel) {
        panels.forEach { $0.view.model = model; $0.view.needsDisplay = true }
    }

    func hide() {
        panels.forEach { $0.orderOut(nil) }
    }

    private func rebuild() {
        panels.forEach { $0.close() }
        panels = NSScreen.screens.map { OverlayPanel(screen: $0) }
    }
}

final class OverlayPanel: NSPanel {
    let view = OverlayView()

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class OverlayView: NSView {
    var model: OverlayModel?

    override func draw(_ dirtyRect: NSRect) {
        guard let model, let windowFrame = window?.frame else { return }
        let toLocal = { (r: Rect) in Coordinates.localRect(r, inWindow: windowFrame) }

        // Ancestors: faint outlines so the descent stays visible.
        NSColor.systemBlue.withAlphaComponent(0.25).setStroke()
        for (i, a) in model.ancestors.enumerated() where i > 0 {
            let path = NSBezierPath(rect: toLocal(a))
            path.lineWidth = 1
            path.stroke()
        }

        // Current rectangle: strong outline, light fill.
        let cur = toLocal(model.current)
        NSColor.systemBlue.withAlphaComponent(0.08).setFill()
        cur.fill()
        NSColor.systemBlue.setStroke()
        let curPath = NSBezierPath(rect: cur)
        curPath.lineWidth = 2
        curPath.stroke()

        // Next choices: the four quadrants, each with its key drawn in the middle.
        let subs = model.current.subdivided()
        NSColor.systemBlue.withAlphaComponent(0.6).setStroke()
        for (q, r) in subs {
            let local = toLocal(r)
            let p = NSBezierPath(rect: local)
            p.lineWidth = 1
            p.stroke()
            if let label = model.labels[q] {
                drawLabel(label, centredIn: local)
            }
        }
    }

    private func drawLabel(_ text: String, centredIn rect: NSRect) {
        let size = min(max(rect.height * 0.35, 10), 72)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: size, weight: .semibold),
            .foregroundColor: NSColor.systemBlue.withAlphaComponent(0.85),
        ]
        let s = NSAttributedString(string: text, attributes: attrs)
        let sz = s.size()
        s.draw(at: NSPoint(x: rect.midX - sz.width / 2, y: rect.midY - sz.height / 2))
    }
}
#endif
