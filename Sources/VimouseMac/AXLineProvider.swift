#if canImport(AppKit)
import AppKit
import ApplicationServices
import VimouseCore

/// Finds lines of text through the Accessibility API, so the reading band can sit on
/// real lines. A text element (AppKit, WebKit, Chromium/Electron) answers the
/// parameterised attributes RangeForPosition, LineForIndex, RangeForLine and
/// BoundsForRange, so once a line is found its neighbours come straight from the
/// element: two calls, no searching. Only at the edge of an element (the next paragraph
/// in Chromium, where each paragraph is its own node) is the screen probed, starting
/// just past the element's frame. A short single-line element (a label, a menu item)
/// counts as a line too. Everything is bounded by a small time budget.
final class AXLineProvider: LineProvider {
    var timeBudget: TimeInterval = 0.12
    /// Vertical probe spacing and reach when looking past an element's edge.
    var probeStep: Double = 6
    var probeReach: Double = 300

    private let systemWide = AXUIElementCreateSystemWide()
    /// `VIMOUSE_DEBUG=1` in the environment logs each lookup to the console.
    private let debug = ProcessInfo.processInfo.environment["VIMOUSE_DEBUG"] != nil
    private func log(_ s: @autoclosure () -> String) { if debug { NSLog("vimouse ruler: %@", s()) } }

    private struct Found {
        var element: AXUIElement
        /// The line's index within the element, when the element exposes lines.
        var line: Int?
        var rect: Rect
        /// The element answers RangeForPosition / BoundsForRange (a text node), as opposed
        /// to a plain single-line element matched by role.
        var textAPI = true
        /// Text-marker based lines (WebKit, Chromium): the line's marker range and the
        /// element that answers marker queries.
        var markerRange: AnyObject?
        var markerHost: AXUIElement?
    }

    /// Text-marker parameterised attributes (WebKit and Chromium web content).
    private enum Marker {
        static let forPosition = "AXTextMarkerForPosition"
        static let lineRange = "AXLineTextMarkerRangeForTextMarker"
        static let bounds = "AXBoundsForTextMarkerRange"
        static let next = "AXNextTextMarkerForTextMarker"
        static let previous = "AXPreviousTextMarkerForTextMarker"
        static let rangeStart = "AXStartTextMarkerForTextMarkerRange"
        static let rangeEnd = "AXEndTextMarkerForTextMarkerRange"
    }
    /// The last line handed out, so a move from it needs no fresh hit test.
    private var last: Found?

    init() {
        AXUIElementSetMessagingTimeout(systemWide, 0.05)
    }

    func textLine(at x: Double, y: Double, direction: Int, on screen: Rect) -> Rect? {
        let deadline = Date().addingTimeInterval(timeBudget)
        // The caller moves from the line we last returned; reuse it rather than hit-testing.
        let current: Found?
        if let l = last, abs(l.rect.midY - y) < 1, x >= l.rect.x - 2, x <= l.rect.maxX + 2 {
            current = l
        } else {
            current = locate(x: x, y: y, deadline: deadline)
        }
        if direction == 0 {
            last = current
            log("at (\(Int(x)),\(Int(y))): \(current.map { "\($0.rect) line \($0.line.map(String.init) ?? "?")" } ?? "no text")")
            return current?.rect
        }
        let sign = Double(direction)
        if let cur = current {
            // Inside an element that exposes lines: the neighbouring line by index, skipping blank ones.
            if let li = cur.line {
                var i = li + direction
                for _ in 0..<4 {
                    guard Date() < deadline, let r = lineBounds(of: cur.element, line: i) else { break }
                    if r.width > 0, r.height > 0, sign > 0 ? r.midY > cur.rect.midY : r.midY < cur.rect.midY {
                        last = Found(element: cur.element, line: i, rect: r)
                        log("line \(i): \(r)")
                        return r
                    }
                    i += direction
                }
            } else if let host = cur.markerHost, let range = cur.markerRange {
                // Web content: walk the text markers to the neighbouring line.
                var r: AnyObject = range
                for _ in 0..<6 {
                    guard Date() < deadline,
                          let edgeMarker = markerValue(host, sign > 0 ? Marker.rangeEnd : Marker.rangeStart, r),
                          let step = markerValue(host, sign > 0 ? Marker.next : Marker.previous, edgeMarker),
                          let nextRange = markerValue(host, Marker.lineRange, step)
                    else { break }
                    r = nextRange
                    if let b = markerBounds(host, nextRange), b.width > 0, b.height > 0,
                       sign > 0 ? b.midY > cur.rect.midY : b.midY < cur.rect.midY {
                        last = Found(element: cur.element, line: nil, rect: b, markerRange: nextRange, markerHost: host)
                        log("next by marker: \(b)")
                        return b
                    }
                }
            } else if cur.textAPI {
                // Lines not indexed (Chromium text nodes): ask the same element for the
                // position just past the current line, staying inside its frame.
                let edge = frame(of: cur.element) ?? cur.rect
                var py = sign > 0 ? cur.rect.maxY + 1 : cur.rect.y - 1
                for _ in 0..<6 {
                    guard Date() < deadline, py >= edge.y - 1, py <= edge.maxY + 1 else { break }
                    if let f = lineFromTextElement(cur.element, x: x, y: py), sign > 0 ? f.rect.midY > cur.rect.midY : f.rect.midY < cur.rect.midY {
                        last = f
                        log("next by position (\(Int(py))): \(f.rect)")
                        return f.rect
                    }
                    py += sign * max(4, cur.rect.height / 2)
                }
            }
            // At the element's edge: look just beyond its frame for the next one.
            let edge = frame(of: cur.element) ?? cur.rect
            let start = sign > 0 ? max(edge.maxY, cur.rect.maxY) : min(edge.y, cur.rect.y)
            let r = probe(x: x, from: start, sign: sign, avoiding: cur.rect, on: screen, deadline: deadline)
            log("past element edge (\(Int(start))): \(r.map { "\($0)" } ?? "nothing (fallback step)")")
            return r
        }
        let r = probe(x: x, from: y, sign: sign, avoiding: nil, on: screen, deadline: deadline)
        log("no current line at (\(Int(x)),\(Int(y))); probe: \(r.map { "\($0)" } ?? "nothing (fallback step)")")
        return r
    }

    func window(at x: Double, y: Double) -> Rect? {
        var ref: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(x), Float(y), &ref) == .success, let element = ref else { return nil }
        var w: AXUIElement? = attribute(element, kAXWindowAttribute)
        if w == nil, (attribute(element, kAXRoleAttribute) as String?) == kAXWindowRole { w = element }
        guard let win = w else { return nil }
        return frame(of: win)
    }

    // MARK: Searching

    private func probe(x: Double, from start: Double, sign: Double, avoiding: Rect?, on screen: Rect, deadline: Date) -> Rect? {
        var py = start
        let limit = sign > 0 ? min(screen.maxY, start + probeReach) : max(screen.y, start - probeReach)
        while Date() < deadline {
            py += sign * probeStep
            if sign > 0 ? py > limit : py < limit { return nil }
            guard let found = locate(x: x, y: py, deadline: deadline) else { continue }
            if let a = avoiding, found.rect.intersects(a) { continue }
            if sign > 0 ? found.rect.midY <= start : found.rect.midY >= start { continue }
            last = found
            return found.rect
        }
        return nil
    }

    private func locate(x: Double, y: Double, deadline: Date) -> Found? {
        var ref: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(x), Float(y), &ref) == .success, let hit = ref else { return nil }
        AXUIElementSetMessagingTimeout(hit, 0.05)
        // The hit element may be a run inside the text view; climb a little to find the view.
        var element = hit
        for _ in 0..<4 {
            if Date() > deadline { return nil }
            if let f = lineFromTextElement(element, x: x, y: y) { return f }
            guard let parent: AXUIElement = attribute(element, kAXParentAttribute) else { break }
            element = parent
        }
        // Web content (WebKit, Chromium): lines through text markers, answered by the
        // hit element or one of its ancestors (the web area at the latest).
        element = hit
        for _ in 0..<40 {
            if Date() > deadline { return nil }
            if let f = lineFromMarkers(element, x: x, y: y) { return f }
            guard let parent: AXUIElement = attribute(element, kAXParentAttribute) else { break }
            element = parent
        }
        if debug { dump(hit) }
        // No text API: a short element of a text-like role is itself one line.
        let role: String = attribute(hit, kAXRoleAttribute) ?? ""
        if ["AXStaticText", "AXMenuItem", "AXLink", "AXCell", "AXRow"].contains(role),
           let f = frame(of: hit), f.height > 0, f.height <= 40, f.contains(Point(x: x, y: y)) {
            return Found(element: hit, line: nil, rect: f, textAPI: false)
        }
        return nil
    }

    private func lineFromTextElement(_ element: AXUIElement, x: Double, y: Double) -> Found? {
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
        var lineNo: Int?
        // Whole line when the view can say which line the index is on.
        if names.contains(kAXLineForIndexParameterizedAttribute), names.contains(kAXRangeForLineParameterizedAttribute),
           let n: Int = parameterisedNumber(element, kAXLineForIndexParameterizedAttribute, hit.location),
           let lineRange: CFRange = parameterisedRange(element, kAXRangeForLineParameterizedAttribute, n) {
            range = lineRange
            lineNo = n
        }
        guard var r = bounds(of: element, range: range), r.width > 0 else { return nil }
        // The view answered with a line; make sure it is the one under the point (some views
        // return the nearest line for a point in the margin, which is fine; a far one is not).
        guard abs(r.midY - y) <= r.height * 1.5 + 4 else { return nil }
        // Without line indexing the bounds are one character's; take the element's width.
        if lineNo == nil, let f = frame(of: element) { r.x = f.x; r.width = f.width }
        return Found(element: element, line: lineNo, rect: r)
    }

    /// Debug: the hit element and its ancestors, with the parameterised attributes each offers.
    private func dump(_ hit: AXUIElement) {
        var element = hit
        for depth in 0..<40 {
            let role: String = attribute(element, kAXRoleAttribute) ?? "?"
            var namesRef: CFArray?
            let names = AXUIElementCopyParameterizedAttributeNames(element, &namesRef) == .success ? (namesRef as? [String] ?? []) : []
            let f = frame(of: element).map { "\(Int($0.x)),\(Int($0.y)) \(Int($0.width))x\(Int($0.height))" } ?? "no frame"
            NSLog("vimouse ruler:   [%d] %@ %@ params: %@", depth, role, f, names.joined(separator: " "))
            guard let parent: AXUIElement = attribute(element, kAXParentAttribute) else { break }
            element = parent
        }
    }

    private func lineFromMarkers(_ element: AXUIElement, x: Double, y: Double) -> Found? {
        var point = CGPoint(x: x, y: y)
        guard let pointValue = AXValueCreate(.cgPoint, &point),
              let marker = markerValue(element, Marker.forPosition, pointValue),
              let range = markerValue(element, Marker.lineRange, marker),
              let b = markerBounds(element, range), b.width > 0
        else { return nil }
        guard abs(b.midY - y) <= b.height * 1.5 + 4 else { return nil }
        return Found(element: element, line: nil, rect: b, markerRange: range, markerHost: element)
    }

    /// A parameterised attribute whose value is an opaque text marker or marker range.
    private func markerValue(_ element: AXUIElement, _ name: String, _ param: AnyObject) -> AnyObject? {
        var out: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, name as CFString, param, &out) == .success else { return nil }
        return out
    }

    private func markerBounds(_ element: AXUIElement, _ range: AnyObject) -> Rect? {
        var out: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, Marker.bounds as CFString, range, &out) == .success,
              let v = out, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var r = CGRect.zero
        // swiftlint:disable:next force_cast
        guard AXValueGetValue(v as! AXValue, .cgRect, &r), r.height > 0, r.height <= 120 else { return nil }
        return Rect(x: r.minX, y: r.minY, width: r.width, height: r.height)
    }

    /// Bounds of line `n` of an element that exposes lines; nil past the last line.
    private func lineBounds(of element: AXUIElement, line n: Int) -> Rect? {
        guard n >= 0, let range: CFRange = parameterisedRange(element, kAXRangeForLineParameterizedAttribute, n) else { return nil }
        return bounds(of: element, range: range)
    }

    private func bounds(of element: AXUIElement, range: CFRange) -> Rect? {
        var r = range
        guard let rangeValue = AXValueCreate(.cfRange, &r),
              let b: CGRect = parameterised(element, kAXBoundsForRangeParameterizedAttribute, rangeValue, .cgRect),
              b.height > 0, b.height <= 120
        else { return nil }
        return Rect(x: b.minX, y: b.minY, width: b.width, height: b.height)
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
