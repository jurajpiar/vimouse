#if canImport(AppKit)
import CoreGraphics
import Foundation
import VimouseCore

/// Moves the real cursor and posts synthetic mouse events.
enum Pointer {
    static func warp(to p: Point) {
        let cg = CGPoint(x: p.x, y: p.y)
        CGWarpMouseCursorPosition(cg)
        // A warp alone does not tell apps the pointer moved; post a move so hover states update.
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: cg, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    static func click(_ button: MouseButton, count: Int, at p: Point) {
        let cg = CGPoint(x: p.x, y: p.y)
        let (down, up, cgButton): (CGEventType, CGEventType, CGMouseButton) = switch button {
        case .left: (.leftMouseDown, .leftMouseUp, .left)
        case .right: (.rightMouseDown, .rightMouseUp, .right)
        case .middle: (.otherMouseDown, .otherMouseUp, .center)
        }
        for n in 1...max(count, 1) {
            for type in [down, up] {
                guard let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: cg, mouseButton: cgButton) else { continue }
                e.setIntegerValueField(.mouseEventClickState, value: Int64(n))
                e.post(tap: .cghidEventTap)
            }
        }
    }

    static var currentLocation: Point {
        let loc = CGEvent(source: nil)?.location ?? .zero
        return Point(x: loc.x, y: loc.y)
    }
}
#endif
