#if canImport(AppKit)
import AppKit
import VimouseCore

/// What the overlay draws, in Core (CG) coordinates.
struct PointerModel {
    var mode: Mode
    var current: Rect
    var ancestors: [Rect]
    var labels: [Quadrant: String]
    var dragging: Bool
    var pendingCount: Int?
    /// Where the pointer was sent; drawn when it differs from the rectangle centre (a snap).
    var target: Point
    var snapping: Bool
    var hints: [(key: String, action: String)]
}

struct RulerModel {
    var screenIndex: Int
    var band: Rect
}

struct OverlayModel {
    /// nil when no mode is active (only a ruler is shown).
    var pointer: PointerModel?
    var ruler: RulerModel?
    /// All displays (CG coordinates) and the active one, for the screen-number badges.
    var screens: [Rect]
    var activeScreen: Int
}

/// One transparent, click-through panel per display, above everything including
/// full-screen apps. Each panel draws only the part of the model on its display.
final class Overlay {
    private var panels: [OverlayPanel] = []

    /// Show the model, or hide everything when it is nil.
    func render(_ model: OverlayModel?) {
        guard let model else {
            panels.forEach { $0.orderOut(nil) }
            return
        }
        if panels.isEmpty || panels.count != NSScreen.screens.count { rebuild() }
        panels.forEach {
            $0.view.model = model
            $0.view.needsDisplay = true
            $0.orderFrontRegardless()
        }
    }

    private func rebuild() {
        panels.forEach { $0.close() }
        panels = NSScreen.screens.enumerated().map { OverlayPanel(screen: $1, index: $0) }
    }
}

final class OverlayPanel: NSPanel {
    let view: OverlayView

    init(screen: NSScreen, index: Int) {
        view = OverlayView(screenIndex: index)
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
    let screenIndex: Int

    /// Dimming outside the ruler band.
    var rulerDimAlpha: CGFloat = 0.35

    init(screenIndex: Int) {
        self.screenIndex = screenIndex
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func tint(_ p: PointerModel) -> NSColor {
        switch p.mode {
        case .scroll: return .systemOrange
        case .ruler: return .systemPurple
        case .pointer: return p.dragging ? .systemGreen : .systemBlue
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let model, let windowFrame = window?.frame else { return }
        let toLocal = { (r: Rect) in Coordinates.localRect(r, inWindow: windowFrame) }

        if let ruler = model.ruler, ruler.screenIndex == screenIndex {
            drawRuler(ruler.band, screen: model.screens[screenIndex], toLocal: toLocal, adjusting: model.pointer?.mode == .ruler)
        }

        guard let p = model.pointer else { return }
        let colour = tint(p)

        // Inactive displays: only a faint screen number (Tab or n⇥ switches).
        if screenIndex != model.activeScreen {
            drawScreenBadge(screenIndex + 1, in: bounds)
            return
        }

        let cur = toLocal(p.current)

        switch p.mode {
        case .pointer:
            // Ancestors: faint outlines so the descent stays visible.
            colour.withAlphaComponent(0.25).setStroke()
            for (i, a) in p.ancestors.enumerated() where i > 0 {
                let path = NSBezierPath(rect: toLocal(a))
                path.lineWidth = 1
                path.stroke()
            }

            // Current rectangle: strong outline, light fill.
            colour.withAlphaComponent(0.08).setFill()
            cur.fill()
            colour.setStroke()
            let curPath = NSBezierPath(rect: cur)
            curPath.lineWidth = 2
            curPath.stroke()

            // Next choices: the four quadrants, each with its key drawn in the middle.
            colour.withAlphaComponent(0.6).setStroke()
            for (q, r) in p.current.subdivided() {
                let local = toLocal(r)
                let path = NSBezierPath(rect: local)
                path.lineWidth = 1
                path.stroke()
                if let label = p.labels[q] {
                    drawLabel(label, centredIn: local, colour: colour)
                }
            }

            // Snap target, when it is not simply the centre.
            if p.snapping, p.target != p.current.center {
                let t = toLocal(Rect(x: p.target.x - 7, y: p.target.y - 7, width: 14, height: 14))
                let ring = NSBezierPath(ovalIn: t)
                ring.lineWidth = 2
                NSColor.systemPink.setStroke()
                ring.stroke()
            }
        case .scroll:
            // A ring around the pointer, which is where scrolling happens.
            let c = NSPoint(x: cur.midX, y: cur.midY)
            let ring = NSBezierPath(ovalIn: NSRect(x: c.x - 18, y: c.y - 18, width: 36, height: 36))
            ring.lineWidth = 3
            colour.setStroke()
            ring.stroke()
        case .ruler:
            break // the band itself is the feedback
        }

        drawStatusStrip(p, colour: colour, awayFrom: cur)
    }

    private func drawRuler(_ band: Rect, screen: Rect, toLocal: (Rect) -> NSRect, adjusting: Bool) {
        let above = Rect(x: screen.x, y: screen.y, width: screen.width, height: max(0, band.y - screen.y))
        let below = Rect(x: screen.x, y: band.maxY, width: screen.width, height: max(0, screen.maxY - band.maxY))
        NSColor.black.withAlphaComponent(rulerDimAlpha).setFill()
        toLocal(above).fill()
        toLocal(below).fill()
        let edge = NSBezierPath(rect: toLocal(band))
        edge.lineWidth = adjusting ? 2 : 1
        NSColor.systemPurple.withAlphaComponent(adjusting ? 0.9 : 0.5).setStroke()
        edge.stroke()
    }

    private func drawScreenBadge(_ number: Int, in rect: NSRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: min(rect.height * 0.3, 200), weight: .bold),
            .foregroundColor: NSColor.systemBlue.withAlphaComponent(0.25),
        ]
        let s = NSAttributedString(string: "\(number)", attributes: attrs)
        let sz = s.size()
        s.draw(at: NSPoint(x: rect.midX - sz.width / 2, y: rect.midY - sz.height / 2))
    }

    private func drawLabel(_ text: String, centredIn rect: NSRect, colour: NSColor) {
        let size = min(max(rect.height * 0.35, 10), 72)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: size, weight: .semibold),
            .foregroundColor: colour.withAlphaComponent(0.85),
        ]
        let s = NSAttributedString(string: text, attributes: attrs)
        let sz = s.size()
        s.draw(at: NSPoint(x: rect.midX - sz.width / 2, y: rect.midY - sz.height / 2))
    }

    /// One line: mode name, then "key action" pairs. Placed at the bottom edge unless
    /// the current rectangle is in the lower half, then at the top, so it never covers the target.
    private func drawStatusStrip(_ p: PointerModel, colour: NSColor, awayFrom target: NSRect) {
        let modeName: String
        switch p.mode {
        case .scroll: modeName = "SCROLL"
        case .ruler: modeName = "RULER"
        case .pointer: modeName = p.dragging ? "DRAG" : "POINTER"
        }
        let text = NSMutableAttributedString()
        let keyAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold), .foregroundColor: NSColor.white,
        ]
        let actionAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.white.withAlphaComponent(0.75),
        ]
        text.append(NSAttributedString(string: modeName, attributes: keyAttrs))
        if let c = p.pendingCount {
            text.append(NSAttributedString(string: " \(c)", attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold), .foregroundColor: NSColor.yellow,
            ]))
        }
        text.append(NSAttributedString(string: "   ", attributes: keyAttrs))
        for (i, h) in p.hints.enumerated() {
            text.append(NSAttributedString(string: h.key + " ", attributes: keyAttrs))
            text.append(NSAttributedString(string: h.action + (i == p.hints.count - 1 ? "" : "   "), attributes: actionAttrs))
        }

        let sz = text.size()
        let pad: CGFloat = 10
        let w = sz.width + pad * 2
        let h = sz.height + pad
        // View coordinates: y up. Target in lower half -> strip at top.
        let atTop = target.midY < bounds.midY
        let y = atTop ? bounds.maxY - h - 40 : bounds.minY + 40
        let box = NSRect(x: bounds.midX - w / 2, y: y, width: w, height: h)
        let bg = NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8)
        colour.withAlphaComponent(0.85).setFill()
        bg.fill()
        text.draw(at: NSPoint(x: box.minX + pad, y: box.minY + pad / 2))
    }
}
#endif
