#if canImport(AppKit)
import AppKit
import VimouseCore

/// AppKit: global space, origin bottom-left of the primary display, y up.
/// Core Graphics (and VimouseCore): origin top-left of the primary display, y down.
/// The two agree on x. Only y is flipped, using the primary display's height.
enum Coordinates {
    static var primaryHeight: CGFloat {
        // NSScreen.screens.first is the primary display (its frame origin is 0,0).
        NSScreen.screens.first?.frame.height ?? 0
    }

    static func cgRect(fromAppKit r: NSRect) -> Rect {
        Rect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    static func cgPoint(fromAppKit p: NSPoint) -> Point {
        Point(x: p.x, y: primaryHeight - p.y)
    }

    static func appKitPoint(fromCG p: Point) -> NSPoint {
        NSPoint(x: p.x, y: primaryHeight - p.y)
    }

    /// A Core rect expressed in the local, non-flipped coordinates of a window
    /// whose frame (AppKit) is `windowFrame`.
    static func localRect(_ r: Rect, inWindow windowFrame: NSRect) -> NSRect {
        NSRect(
            x: r.x - windowFrame.minX,
            y: (primaryHeight - r.maxY) - windowFrame.minY,
            width: r.width,
            height: r.height
        )
    }

    static func screen(containing appKitPoint: NSPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(appKitPoint, $0.frame, false) } ?? NSScreen.main
    }
}
#endif
