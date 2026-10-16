#if canImport(AppKit)
import CoreGraphics
import Foundation
import VimouseCore

/// Moves the real cursor and posts synthetic mouse events.
enum Pointer {
    /// Stamped on every event we post, so our own event tap lets them through untouched.
    static let syntheticMarker: Int64 = 0x56_49_4D_4F // "VIMO"

    /// Press the left button. With `ramp`, also post a few small drag events and return
    /// to the origin, for apps that start a drag-and-drop session only after movement
    /// following the press. Off by default: Chromium-based apps treat the ramp as a new
    /// selection instead of a drag of the selected text.
    static func startDrag(at p: Point, ramp: Bool) {
        post(.left, down: true, clickState: 1, modifiers: [], at: p)
        guard ramp else { return }
        for i in 1...4 {
            usleep(12_000)
            postDragged(to: CGPoint(x: p.x + Double(i) * 2, y: p.y + Double(i) * 2))
        }
        usleep(12_000)
        postDragged(to: CGPoint(x: p.x, y: p.y))
    }

    /// Release at `p`, after a last drag event there so the drop target is up to date.
    static func endDrag(at p: Point) {
        postDragged(to: CGPoint(x: p.x, y: p.y))
        usleep(30_000)
        post(.left, down: false, clickState: 1, modifiers: [], at: p)
    }

    /// Abandon a drag: the Escape key cancels a drag-and-drop session system-wide, then
    /// the button is released back at the origin so nothing is dropped anywhere.
    static func cancelDrag(origin: Point) {
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: down) else { continue }
            e.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
            e.post(tap: .cghidEventTap)
        }
        usleep(30_000)
        let o = CGPoint(x: origin.x, y: origin.y)
        CGWarpMouseCursorPosition(o)
        postDragged(to: o)
        usleep(20_000)
        post(.left, down: false, clickState: 1, modifiers: [], at: origin)
    }

    private static func postDragged(to q: CGPoint) {
        CGWarpMouseCursorPosition(q)
        guard let e = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: q, mouseButton: .left) else { return }
        e.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
        e.post(tap: .cghidEventTap)
    }

    /// Warp the cursor. While a drag is held, apps must see a drag, not a move.
    static func warp(to p: Point, dragging: Bool) {
        let cg = CGPoint(x: p.x, y: p.y)
        CGWarpMouseCursorPosition(cg)
        let type: CGEventType = dragging ? .leftMouseDragged : .mouseMoved
        guard let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: cg, mouseButton: .left) else { return }
        e.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
        e.post(tap: .cghidEventTap)
    }

    static func click(_ button: MouseButton, count: Int, modifiers: Modifiers, at p: Point) {
        for n in 1...max(count, 1) {
            post(button, down: true, clickState: n, modifiers: modifiers, at: p)
            post(button, down: false, clickState: n, modifiers: modifiers, at: p)
        }
    }

    static func mouseDown(_ button: MouseButton, at p: Point) {
        post(button, down: true, clickState: 1, modifiers: [], at: p)
    }

    static func mouseUp(_ button: MouseButton, at p: Point) {
        post(button, down: false, clickState: 1, modifiers: [], at: p)
    }

    /// Positive dy reveals content below; positive dx content to the right.
    static func scroll(dx: Double, dy: Double) {
        // Wheel sign convention: positive wheel1 scrolls content down (reveals what is above).
        guard let e = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(-dy.rounded()),
            wheel2: Int32(-dx.rounded()),
            wheel3: 0
        ) else { return }
        e.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
        e.post(tap: .cghidEventTap)
    }

    static var currentLocation: Point {
        let loc = CGEvent(source: nil)?.location ?? .zero
        return Point(x: loc.x, y: loc.y)
    }

    private static func post(_ button: MouseButton, down: Bool, clickState: Int, modifiers: Modifiers, at p: Point) {
        let cg = CGPoint(x: p.x, y: p.y)
        let (type, cgButton): (CGEventType, CGMouseButton) = switch (button, down) {
        case (.left, true): (.leftMouseDown, .left)
        case (.left, false): (.leftMouseUp, .left)
        case (.right, true): (.rightMouseDown, .right)
        case (.right, false): (.rightMouseUp, .right)
        case (.middle, true): (.otherMouseDown, .center)
        case (.middle, false): (.otherMouseUp, .center)
        }
        guard let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: cg, mouseButton: cgButton) else { return }
        e.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
        e.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
        e.flags = cgFlags(modifiers)
        e.post(tap: .cghidEventTap)
    }

    private static func cgFlags(_ m: Modifiers) -> CGEventFlags {
        var f: CGEventFlags = []
        if m.contains(.shift) { f.insert(.maskShift) }
        if m.contains(.control) { f.insert(.maskControl) }
        if m.contains(.option) { f.insert(.maskAlternate) }
        if m.contains(.command) { f.insert(.maskCommand) }
        return f
    }
}
#endif
