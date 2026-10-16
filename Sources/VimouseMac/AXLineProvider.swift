#if canImport(AppKit)
import AppKit
import ApplicationServices
import VimouseCore

/// Finds lines of text under a point through the Accessibility API, so the reading band
/// can sit on real lines. Text views (AppKit, WebKit, Chromium/Electron) answer the
/// parameterised attributes RangeForPosition, LineForIndex, RangeForLine and
/// BoundsForRange; a short single-line element (a label, a menu item) counts as a line
/// too. Every call is bounded by a small time budget so a slow app cannot stall a key.
final class AXLineProvider: LineProvider {
    var timeBudget: TimeInterval = 0.08
    /// Vertical probe spacing and reach when looking for the next line.
    var probeStep: Double = 4
    var probeReach: Double = 240

    private let systemWide = AXUIElementCreateSystemWide()

    init() {
        AXUIElementSetMessagingTimeout(systemWide, 0.05)
    }

    func textLine(at x: Double, y: Double, direction: Int, on screen: Rect) -> Rect? {
        let deadline = Date().addingTimeInterval(timeBudget)
        let current = line(at: x, y: y, deadline: deadline)
        if direction == 0 { return current }
        // Step away from the current line (or the point) until a different line turns up.
        let sign = Double(direction)
        var py = current.map { sign > 0 ? $0.maxY : $0.y } ?? y
        let limit = sign > 0 ? min(screen.maxY, y + probeReach) : max(screen.y, y - probeReach)
        while Date() < deadline {
            py += sign * probeStep
            if sign > 0 ? py > limit : py < limit { return nil }
            guard let found = line(at: x, y: py, deadline: deadline) else { continue }
            if let c = current, found.intersects(c) { continue } // still the same line
            if sign > 0 ? found.midY <= y : found.midY >= y { continue }
            return found
        }
        return nil
    }

    func window(at x: Double, y: Double) -> Rect? {
        var ref: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(x), Float(y), &ref) == .success, let element = ref else { return nil }
        var w: AXUIElement? = attribute(element, kAXWindowAttribute)
        if w == nil, (attribute(element, kAXRoleAttribute) as String?) == kAXWindowRole { w = element }
        guard let win = w else { return nil }
        return frame(of: win)
    }

    // MARK: One line

    private func line(at x: Double, y: Double, deadline: Date) -> Rect? {
        var ref: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(x), Float(y), &ref) == .success, var element = ref else { return nil }
        // The hit element may be a run inside the text view; climb a little to find the view.
        for _ in 0..<4 {
            if Date() > deadline { return nil }
            if let r = lineFromTextElement(element, x: x, y: y) { return r }
            guard let parent: AXUIElement = attribute(element, kAXParentAttribute) else { break }
            element = parent
        }
        // No text API: a short element of a text-like role is itself one line.
        let role: String = attribute(ref!, kAXRoleAttribute) ?? ""
        if ["AXStaticText", "AXMenuItem", "AXLink", "AXCell", "AXRow"].contains(role),
           let f = frame(of: ref!), f.height > 0, f.height <= 40, f.contains(Point(x: x, y: y)) {
            return f
        }
        return nil
    }

    private func lineFromTextElement(_ element: AXUIElement, x: Double, y: Double) -> Rect? {
        var namesRef: CFArray?
        guard AXUIElementCopyParameterizedAttributeNames(element, &namesRef) == .success,
              let names = namesRef as? [String],
              names.contains(kAXRangeForPositionParameterizedAttribute),
              names.contains(kAXBoundsForRangeParameterizedAttribute)
        else { return nil }
        var point = CGPoint(x: x, y: y)
        guard let pointValue = AXValueCreate(.cgPoint, &point),
              let hit: CFRange = parameterised(element, kAXRangeForPositionParameterizedAttribute, pointValue, .cfRange)
        else { return nil }
        var range = CFRange(location: hit.location, length: 1)
        // Whole line when the view can say which line the index is on.
        if names.contains(kAXLineForIndexParameterizedAttribute), names.contains(kAXRangeForLineParameterizedAttribute),
           let lineNo: Int = parameterisedNumber(element, kAXLineForIndexParameterizedAttribute, hit.location),
           let lineRange: CFRange = parameterisedRange(element, kAXRangeForLineParameterizedAttribute, lineNo) {
            range = lineRange
        }
        guard let rangeValue = AXValueCreate(.cfRange, &range),
              let bounds: CGRect = parameterised(element, kAXBoundsForRangeParameterizedAttribute, rangeValue, .cgRect),
              bounds.height > 0, bounds.height <= 120, bounds.width > 0
        else { return nil }
        let r = Rect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height)
        // The view answered with a line; make sure it is the one under the point (some views
        // return the nearest line for a point in the margin, which is fine; a far one is not).
        guard abs(r.midY - y) <= r.height * 1.5 + 4 else { return nil }
        return r
    }

    // MARK: AX helpers

    private func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    private func parameterisedNumber(_ element: AXUIElement, _ name: String, _ n: Int) -> Int? {
        var out: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, name as CFString, n as CFNumber, &out) == .success else { return nil }
        return out as? Int
    }

    private func parameterisedRange(_ element: AXUIElement, _ name: String, _ n: Int) -> CFRange? {
        var out: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, name as CFString, n as CFNumber, &out) == .success,
              let v = out, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var r = CFRange()
        // swiftlint:disable:next force_cast
        return AXValueGetValue(v as! AXValue, .cfRange, &r) ? r : nil
    }

    private func parameterised<T>(_ element: AXUIElement, _ name: String, _ param: AXValue, _ type: AXValueType) -> T? {
        var out: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, name as CFString, param, &out) == .success,
              let v = out, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        // swiftlint:disable force_cast
        switch type {
        case .cfRange:
            var r = CFRange()
            return AXValueGetValue(v as! AXValue, .cfRange, &r) ? (r as? T) : nil
        case .cgRect:
            var r = CGRect.zero
            return AXValueGetValue(v as! AXValue, .cgRect, &r) ? (r as? T) : nil
        default:
            return nil
        }
        // swiftlint:enable force_cast
    }

    private func frame(of element: AXUIElement) -> Rect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posValue = posRef, let sizeValue = sizeRef,
              CFGetTypeID(posValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }
        var p = CGPoint.zero
        var sz = CGSize.zero
        // swiftlint:disable force_cast
        guard AXValueGetValue(posValue as! AXValue, .cgPoint, &p), AXValueGetValue(sizeValue as! AXValue, .cgSize, &sz) else { return nil }
        // swiftlint:enable force_cast
        return Rect(x: p.x, y: p.y, width: sz.width, height: sz.height)
    }
}
#endif
