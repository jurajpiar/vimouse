#if canImport(AppKit)
import AppKit
import VimouseCore

/// One transparent, click-through panel per display, above everything including
/// full-screen apps. Each panel draws only the part of the model on its display.
final class Overlay {
    private var panels: [OverlayPanel] = []

    /// Show the model, or hide everything when it is nil.
    func render(_ model: Scene?) {
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
    var model: Scene?
    let screenIndex: Int

    init(screenIndex: Int) {
        self.screenIndex = screenIndex
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        guard let model, let windowFrame = window?.frame, model.screens.indices.contains(screenIndex) else { return }
        let toLocal = { (r: Rect) in Coordinates.localRect(r, inWindow: windowFrame) }
        let point = { (p: Point) in Coordinates.localRect(Rect(x: p.x, y: p.y, width: 0, height: 0), inWindow: windowFrame).origin }
        let screen = model.screens[screenIndex]
        let colour = NSColor(hex: model.modeColour)

        for d in model.drawables {
            switch d {
            case .fill(let r, let c, let a):
                guard r.intersects(screen) else { continue }
                NSColor(hex: c).withAlphaComponent(a).setFill()
                toLocal(r).fill()
            case .outline(let r, let c, let a, let w):
                guard r.intersects(screen) else { continue }
                let path = NSBezierPath(rect: toLocal(r))
                path.lineWidth = w
                NSColor(hex: c).withAlphaComponent(a).setStroke()
                path.stroke()
            case .ring(let p, let radius, let c, let a, let w):
                guard screen.contains(p) else { continue }
                let o = point(p)
                let ring = NSBezierPath(ovalIn: NSRect(x: o.x - radius, y: o.y - radius, width: radius * 2, height: radius * 2))
                ring.lineWidth = w
                NSColor(hex: c).withAlphaComponent(a).setStroke()
                ring.stroke()
            case .dot(let p, let radius, let c, let a):
                guard screen.contains(p) else { continue }
                let o = point(p)
                NSColor(hex: c).withAlphaComponent(a).setFill()
                NSBezierPath(ovalIn: NSRect(x: o.x - radius, y: o.y - radius, width: radius * 2, height: radius * 2)).fill()
            case .line(let p1, let p2, let c, let a, let w, let dashed):
                guard screen.contains(p1) || screen.contains(p2) else { continue }
                let line = NSBezierPath()
                line.move(to: point(p1)); line.line(to: point(p2))
                line.lineWidth = w
                if dashed { line.setLineDash([4, 4], count: 2, phase: 0) }
                NSColor(hex: c).withAlphaComponent(a).setStroke()
                line.stroke()
            case .crosshair(let p, let size, let c, let a, let w):
                guard screen.contains(p) else { continue }
                let t = toLocal(Rect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size))
                let path = NSBezierPath()
                path.move(to: NSPoint(x: t.minX, y: t.midY)); path.line(to: NSPoint(x: t.maxX, y: t.midY))
                path.move(to: NSPoint(x: t.midX, y: t.minY)); path.line(to: NSPoint(x: t.midX, y: t.maxY))
                path.lineWidth = w
                NSColor(hex: c).withAlphaComponent(a).setStroke()
                path.stroke()
            case .label(let text, let r, let c, let a):
                guard r.intersects(screen) else { continue }
                drawLabel(text, centredIn: toLocal(r), colour: NSColor(hex: c).withAlphaComponent(a))
            case .dim(let index, let except, let a):
                guard index == screenIndex else { continue }
                let above = Rect(x: screen.x, y: screen.y, width: screen.width, height: max(0, except.y - screen.y))
                let below = Rect(x: screen.x, y: except.maxY, width: screen.width, height: max(0, screen.maxY - except.maxY))
                let left = Rect(x: screen.x, y: except.y, width: max(0, except.x - screen.x), height: except.height)
                let right = Rect(x: except.maxX, y: except.y, width: max(0, screen.maxX - except.maxX), height: except.height)
                NSColor.black.withAlphaComponent(CGFloat(a)).setFill()
                for r in [above, below, left, right] where r.width > 0 && r.height > 0 { toLocal(r).fill() }
            }
        }

        guard let name = model.modeName else { return }
        // Inactive displays: only a faint screen number (Tab or n⇥ switches).
        if screenIndex != model.activeScreen {
            drawScreenBadge(screenIndex + 1, in: bounds, colour: colour)
            return
        }
        drawStatusStrip(model, name: name, colour: colour, awayFrom: point(model.focus))
        if let help = model.help { drawHelp(help, colour: colour) }
    }

    private func drawScreenBadge(_ number: Int, in rect: NSRect, colour: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: min(rect.height * 0.3, 200), weight: .bold),
            .foregroundColor: colour.withAlphaComponent(0.25),
        ]
        let s = NSAttributedString(string: "\(number)", attributes: attrs)
        let sz = s.size()
        s.draw(at: NSPoint(x: rect.midX - sz.width / 2, y: rect.midY - sz.height / 2))
    }

    private func drawLabel(_ text: String, centredIn rect: NSRect, colour: NSColor) {
        let size = min(max(rect.height * 0.35, 10), 72)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: size, weight: .semibold),
            .foregroundColor: colour,
        ]
        let s = NSAttributedString(string: text, attributes: attrs)
        let sz = s.size()
        s.draw(at: NSPoint(x: rect.midX - sz.width / 2, y: rect.midY - sz.height / 2))
    }

    /// Full key map in the middle of the screen while the help key is held.
    private func drawHelp(_ help: [Scene.HelpGroup], colour: NSColor) {
        let title: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .bold), .foregroundColor: NSColor.white]
        let keys: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold), .foregroundColor: NSColor.white]
        let action: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.white.withAlphaComponent(0.8)]
        let keyColumn: CGFloat = 170
        let lineH: CGFloat = 18
        var lines: [(NSAttributedString, NSAttributedString?)] = []
        for (i, g) in help.enumerated() {
            if i > 0 { lines.append((NSAttributedString(string: ""), nil)) }
            lines.append((NSAttributedString(string: g.title, attributes: title), nil))
            for r in g.rows {
                lines.append((NSAttributedString(string: r.keys, attributes: keys), NSAttributedString(string: r.action, attributes: action)))
            }
        }
        let width: CGFloat = 720
        let height = CGFloat(lines.count) * lineH + 24
        let box = NSRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height)
        NSColor.black.withAlphaComponent(0.85).setFill()
        NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10).fill()
        colour.setStroke()
        let border = NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10)
        border.lineWidth = 2
        border.stroke()
        var y = box.maxY - 12 - lineH
        for (left, right) in lines {
            left.draw(at: NSPoint(x: box.minX + 16, y: y))
            right?.draw(at: NSPoint(x: box.minX + 16 + keyColumn, y: y))
            y -= lineH
        }
    }

    /// One line: mode name, then "key action" pairs. Placed at the bottom edge unless
    /// the pointer is in the lower half, then at the top, so it never covers the target.
    private func drawStatusStrip(_ m: Scene, name: String, colour: NSColor, awayFrom focus: NSPoint) {
        let dragColour = NSColor(hex: m.colours.drag)
        let text = NSMutableAttributedString()
        let keyAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold), .foregroundColor: NSColor.white,
        ]
        let actionAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.white.withAlphaComponent(0.75),
        ]
        if m.dragging {
            text.append(NSAttributedString(string: "DRAG · ", attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold), .foregroundColor: dragColour,
            ]))
        }
        text.append(NSAttributedString(string: name, attributes: keyAttrs))
        if let c = m.pendingCount {
            text.append(NSAttributedString(string: " \(c)", attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold), .foregroundColor: NSColor.yellow,
            ]))
        }
        text.append(NSAttributedString(string: "   ", attributes: keyAttrs))
        for (i, h) in m.hints.enumerated() {
            text.append(NSAttributedString(string: h.key + " ", attributes: keyAttrs))
            text.append(NSAttributedString(string: h.action + (i == m.hints.count - 1 ? "" : "   "), attributes: actionAttrs))
        }

        let sz = text.size()
        let pad: CGFloat = 10
        let w = sz.width + pad * 2
        let h = sz.height + pad
        // View coordinates: y up. Pointer in lower half -> strip at top.
        let atTop = focus.y < bounds.midY
        let y = atTop ? bounds.maxY - h - 40 : bounds.minY + 40
        let box = NSRect(x: bounds.midX - w / 2, y: y, width: w, height: h)
        let bg = NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8)
        colour.withAlphaComponent(0.85).setFill()
        bg.fill()
        text.draw(at: NSPoint(x: box.minX + pad, y: box.minY + pad / 2))
    }
}

extension NSColor {
    /// "#RRGGBB"; falls back to grey on bad input.
    convenience init(hex: String) {
        var v: UInt64 = 0
        guard hex.count == 7, Scanner(string: String(hex.dropFirst())).scanHexInt64(&v) else {
            self.init(white: 0.5, alpha: 1)
            return
        }
        self.init(
            red: CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255,
            alpha: 1
        )
    }
}
#endif
