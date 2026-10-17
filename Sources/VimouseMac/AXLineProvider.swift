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
    var timeBudget: TimeInterval = 0.25
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
        /// Line number within the web area (Chromium), for stepping by index.
        var webLine: Int?
        /// A marker at the start of this line, for walking line by line (Chromium, WebKit).
        var lineStart: AnyObject?
        /// Lines derived from character rectangles (Chromium text nodes without line APIs):
        /// the row's first and last character indices and the text length.
        var charBounds = false
        var rowStart = 0
        var rowEnd = 0
        var textLength = 0
        /// Character rectangles sampled through the text (index, rect), for finding rows.
        var samples: [(Int, Rect)] = []
        /// Whether the web area's marker bounds come flipped (Cocoa) or not.
        var flipped = true
    }

    /// Text-marker parameterised attributes (WebKit and Chromium web content).
    private enum Marker {
        static let forPosition = "AXTextMarkerForPosition"
        static let lineRange = "AXLineTextMarkerRangeForTextMarker"
        static let bounds = "AXBoundsForTextMarkerRange"
        static let indexForChild = "AXIndexForChildUIElement"
        static let forIndex = "AXTextMarkerForIndex"
        static let lineForMarker = "AXLineForTextMarker"
        static let rangeForLine = "AXTextMarkerRangeForLine"
        static let startOfElement = "AXStartTextMarker"
        static let nextLineEnd = "AXNextLineEndTextMarkerForTextMarker"
        static let previousLineStart = "AXPreviousLineStartTextMarkerForTextMarker"
        static let next = "AXNextTextMarkerForTextMarker"
        static let previous = "AXPreviousTextMarkerForTextMarker"
    }
    /// The last line handed out, so a move from it needs no fresh hit test.
    private var last: Found?
    /// The web area (WebKit, Chromium) that answered last time; reused while the point is inside it.
    private var webArea: (element: AXUIElement, frame: Rect)?
    /// Processes whose text-marker line ranges turned out to span the whole document
    /// (Chromium without a screen reader): the marker routes are skipped for them.
    private var hollowMarkers: Set<pid_t> = []

    init() {
        AXUIElementSetMessagingTimeout(systemWide, 0.05)
    }

    func textLine(at x: Double, y: Double, direction: Int, on screen: Rect) -> Rect? {
        guard let r = line(at: x, y: y, direction: direction, on: screen) else { return nil }
        // Text scrolled out of view still has bounds; a line outside its window (or the
        // screen) is no line.
        let bounds = last.flatMap { windowFrame(of: $0.element) } ?? screen
        guard r.midY >= max(bounds.y, screen.y), r.midY <= min(bounds.maxY, screen.maxY) else {
            log("line \(r) is outside its window \(bounds)")
            last = nil
            return nil
        }
        return r
    }

    private func windowFrame(of element: AXUIElement) -> Rect? {
        guard let w: AXUIElement = attribute(element, kAXWindowAttribute) else { return nil }
        return frame(of: w)
    }

    private func line(at x: Double, y: Double, direction: Int, on screen: Rect) -> Rect? {
        let deadline = Date().addingTimeInterval(timeBudget)
        // The caller moves from the line we last returned; reuse it rather than hit-testing.
        // Matched by y alone: the pointer's x may lie past the end of a short line.
        let current: Found?
        if let l = last, abs(l.rect.midY - y) < 1 {
            current = l
        } else if let f = locate(x: x, y: y, deadline: deadline) {
            current = f
        } else if let l = last, abs(l.rect.midY - y) < l.rect.height * 3 {
            // Nothing under the pointer's column (a short line); try inside the text.
            current = locate(x: l.rect.x + min(12, l.rect.width / 2), y: y, deadline: deadline)
        } else {
            current = nil
        }
        if direction == 0 {
            last = current.map { widened($0, deadline: deadline) }
            log("at (\(Int(x)),\(Int(y))): \(last.map { "\($0.rect) line \($0.line.map(String.init) ?? "?")" } ?? "no text")")
            return last?.rect
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
            } else if cur.charBounds {
                // Chromium text node: the nearest sampled row past this one.
                if let f = rowBeyond(cur.rect, in: cur, sign: sign, deadline: deadline) {
                    last = widened(f, deadline: deadline)
                    log("next by character rows [\(f.rowStart)..\(f.rowEnd)]: \(last!.rect)")
                    return last!.rect
                }
                // The node's text is exhausted: the next text node in document order. Frames
                // and hit tests are unreliable in Chromium here; the tree order is what a
                // reader wants anyway.
                var from = cur.element
                let window = windowFrame(of: cur.element) ?? screen
                for _ in 0..<4 {
                    guard let f = edgeRow(ofTextNodeAfter: from, direction: direction, deadline: deadline) else { break }
                    // Scrolled out of the window: nothing further this way.
                    if f.rect.midY < window.y || f.rect.midY > window.maxY { break }
                    // The next node starts on this row (text after inline code, or the code
                    // exposed twice) or the wrong way: its own further rows come first, else
                    // keep going.
                    if abs(f.rect.midY - cur.rect.midY) < cur.rect.height / 2 || (sign > 0 ? f.rect.midY < cur.rect.midY : f.rect.midY > cur.rect.midY) {
                        if let n = rowBeyond(cur.rect, in: f, sign: sign, deadline: deadline) {
                            last = widened(n, deadline: deadline)
                            log("next text node continues past this row: \(last!.rect)")
                            return last!.rect
                        }
                        from = f.element
                        continue
                    }
                    last = widened(f, deadline: deadline)
                    log("next text node in document order: \(last!.rect)")
                    return last!.rect
                }
            } else if let host = cur.markerHost, let start = cur.lineStart {
                // Walk the lines by marker. Up: WebKit's "previous line start" from the start
                // of a line is the line above; from a block's end it is the block's first
                // line, so that is only the fallback.
                let candidates: [AnyObject?] = sign > 0
                    ? [nextLineStart(host, from: start)]
                    : [markerValue(host, Marker.previousLineStart, start), previousLineStart(host, from: start)]
                for case let m? in candidates {
                    if let range = markerValue(host, Marker.lineRange, m),
                       let b = normalisedBounds(host, range, flipped: cur.flipped), b.width > 0,
                       abs(b.midY - cur.rect.midY) >= cur.rect.height / 2,
                       sign > 0 ? b.midY > cur.rect.midY : b.midY < cur.rect.midY {
                        last = Found(element: cur.element, line: nil, rect: b, markerHost: host, lineStart: m, flipped: cur.flipped)
                        log("next by line marker: \(b)")
                        return b
                    }
                }
                log("no further line marker in the element")
            } else if let host = cur.markerHost, let n = cur.webLine {
                // Chromium: lines are numbered across the web area; take the neighbour.
                var i = n + direction
                for _ in 0..<6 {
                    guard Date() < deadline, i >= 0, let b = webLineBounds(host, line: i, flipped: cur.flipped) else { break }
                    if b.width > 0, sign > 0 ? b.midY > cur.rect.midY : b.midY < cur.rect.midY {
                        last = Found(element: cur.element, line: nil, rect: b, markerHost: host, webLine: i, flipped: cur.flipped)
                        log("web line \(i): \(b)")
                        return b
                    }
                    i += direction
                }
            } else if let host = cur.markerHost {
                // Web content: the line at a point just past the current one, from the web area.
                let hostFrame = frame(of: host) ?? screen
                var py = sign > 0 ? cur.rect.maxY + 2 : cur.rect.y - 2
                let limit = sign > 0 ? min(hostFrame.maxY, cur.rect.maxY + probeReach) : max(hostFrame.y, cur.rect.y - probeReach)
                while Date() < deadline, sign > 0 ? py <= limit : py >= limit {
                    if let f = lineFromMarkers(host, x: x, y: py), !f.rect.intersects(cur.rect),
                       sign > 0 ? f.rect.midY > cur.rect.midY : f.rect.midY < cur.rect.midY {
                        last = f
                        log("next by marker at \(Int(py)): \(f.rect)")
                        return f.rect
                    }
                    py += sign * max(4, cur.rect.height / 2)
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
            // Past the element's own text: look just beyond this row for the next node. Not
            // beyond the element's frame: a parent may hold nested blocks whose text is not
            // its own (a list inside a paragraph), and those rows must not be skipped.
            let start = sign > 0 ? cur.rect.maxY : cur.rect.y
            let r = probe(x: x, from: start, sign: sign, avoiding: cur.rect, on: screen, deadline: deadline)
            log("past the row (\(Int(start))): \(r.map { "\($0)" } ?? "nothing (fallback step)")")
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
        // Probe in the pointer's column and, when a line is known, near its left edge too,
        // so a short line is not stepped over.
        let columns = [x] + (avoiding.map { [$0.x + min(12, $0.width / 2)] } ?? []).filter { abs($0 - x) > 20 }
        while Date() < deadline {
            py += sign * probeStep
            if sign > 0 ? py > limit : py < limit { return nil }
            guard let found = columns.lazy.compactMap({ self.locate(x: $0, y: py, deadline: deadline) }).first else { continue }
            if let a = avoiding, found.rect.intersects(a) { continue }
            if sign > 0 ? found.rect.midY <= start : found.rect.midY >= start { continue }
            last = widened(found, deadline: deadline)
            return last!.rect
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
        // Web content (WebKit, Chromium): lines through text markers, answered by the web
        // area. It is found once by climbing (deep in Electron apps) and reused after.
        if let wa = webArea, !wa.frame.contains(Point(x: x, y: y)) { webArea = nil }
        if webArea == nil {
            element = hit
            for _ in 0..<40 {
                if Date() > deadline { log("out of time climbing to the web area"); return nil }
                if (attribute(element, kAXRoleAttribute) as String?) == "AXWebArea" {
                    AXUIElementSetMessagingTimeout(element, 0.1)
                    webArea = (element, frame(of: element) ?? Rect(x: 0, y: 0, width: 0, height: 0))
                    break
                }
                guard let parent: AXUIElement = attribute(element, kAXParentAttribute) else { break }
                element = parent
            }
        }
        // Chromium text nodes: no line API, but character rectangles by index.
        if let f = lineFromCharBounds(hit, x: x, y: y, deadline: deadline) { return f }
        // The hit test may answer with a parent whose own text is elsewhere while a nested
        // block (a list inside a paragraph) holds the row under the point: look inside.
        var container = hit
        for _ in 0..<4 {
            guard Date() < deadline, let child = child(of: container, containing: Point(x: x, y: y)) else { break }
            if let f = lineFromCharBounds(child, x: x, y: y, deadline: deadline) { return f }
            container = child
        }
        // Chromium containers whose children carry useless frames: try their text by rows.
        var budget = 300
        if let f = rowInDescendants(of: hit, x: x, y: y, depth: 0, budget: &budget, deadline: deadline) { return f }
        if debug {
            let role: String = attribute(hit, kAXRoleAttribute) ?? "?"
            let n = (attribute(hit, kAXChildrenAttribute) as [AXUIElement]?)?.count ?? 0
            log("no row at (\(Int(x)),\(Int(y))): hit \(role) \(frame(of: hit).map { "\($0)" } ?? "no frame"), \(n) children, \(300 - budget) descendants searched")
        }
        if debug, dumpedChildren < 3 {
            dumpedChildren += 1
            let role: String = attribute(hit, kAXRoleAttribute) ?? "?"
            let v: String = attribute(hit, kAXValueAttribute) ?? ""
            log("no row at (\(Int(x)),\(Int(y))) in hit \(role) \(frame(of: hit).map { "\($0)" } ?? "") value \(v.count) chars; children:")
            if let children: [AXUIElement] = attribute(hit, kAXChildrenAttribute) {
                for c in children.prefix(12) {
                    let r: String = attribute(c, kAXRoleAttribute) ?? "?"
                    let cv: String = attribute(c, kAXValueAttribute) ?? ""
                    log("   \(r) \(frame(of: c).map { "\($0)" } ?? "no frame") \(cv.count) chars \"\(cv.prefix(30))\"")
                }
            } else {
                log("   (none)")
            }
            if let parent: AXUIElement = attribute(hit, kAXParentAttribute), let children: [AXUIElement] = attribute(parent, kAXChildrenAttribute) {
                log("   parent's children:")
                for c in children.prefix(12) {
                    let r: String = attribute(c, kAXRoleAttribute) ?? "?"
                    let cv: String = attribute(c, kAXValueAttribute) ?? ""
                    log("   \(r) \(frame(of: c).map { "\($0)" } ?? "no frame") \(cv.count) chars \"\(cv.prefix(30))\"")
                }
            }
        }
        // WebKit text nodes: walk the lines from the element's own start marker.
        var pid: pid_t = 0
        AXUIElementGetPid(hit, &pid)
        if hollowMarkers.contains(pid) {
            if debug, dumped == false { dumped = true; dump(hit, levels: 4) }
            return nil
        }
        element = hit
        for _ in 0..<3 {
            if Date() > deadline { return nil }
            if let f = lineFromStartMarker(element, x: x, y: y, deadline: deadline) { return f }
            guard let parent: AXUIElement = attribute(element, kAXParentAttribute) else { break }
            element = parent
        }
        if let wa = webArea, !hollowMarkers.contains(pid) {
            if let f = lineFromMarkers(wa.element, x: x, y: y) { return f }
            if let f = lineFromWebIndex(wa.element, hit: hit, x: x, y: y, deadline: deadline) { return f }
            log("web area answered no line at (\(Int(x)),\(Int(y)))")
            if debug, dumped == false { dumped = true; dump(hit, levels: 4) }
        } else if debug {
            dump(hit, levels: 40)
        }
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

    /// The first (direction 1) or last (direction -1) row of the next text node after
    /// `element` in document order: siblings first, descending into their text, then the
    /// parent's siblings, a few levels up.
    /// The nearest sampled row of a character-addressed node past `rect` in the given direction.
    private func rowBeyond(_ rect: Rect, in node: Found, sign: Double, deadline: Date) -> Found? {
        let text = CharText(element: node.element, length: node.textLength)
        let beyond = node.samples.filter { sign > 0 ? $0.1.y > rect.maxY - 2 : $0.1.maxY < rect.y + 2 }
        let pick = sign > 0 ? beyond.min { $0.1.y < $1.1.y || ($0.1.y == $1.1.y && $0.0 < $1.0) }
                            : beyond.max { $0.1.y < $1.1.y || ($0.1.y == $1.1.y && $0.0 > $1.0) }
        guard let s = pick, Date() < deadline, let row = text.row(around: s.0, deadline: deadline),
              sign > 0 ? row.rect.midY > rect.midY : row.rect.midY < rect.midY else { return nil }
        var f = Found(element: node.element, line: nil, rect: row.rect, charBounds: true, rowStart: row.start, rowEnd: row.end, textLength: node.textLength)
        f.samples = node.samples
        return f
    }

    private func edgeRow(ofTextNodeAfter element: AXUIElement, direction: Int, deadline: Date) -> Found? {
        var node = element
        for _ in 0..<6 {
            guard Date() < deadline, let parent: AXUIElement = attribute(node, kAXParentAttribute),
                  let siblings: [AXUIElement] = attribute(parent, kAXChildrenAttribute),
                  let i = siblings.firstIndex(where: { CFEqual($0, node) }) else { return nil }
            let rest = direction > 0 ? Array(siblings[(i + 1)...]) : Array(siblings[..<i].reversed())
            for s in rest {
                if let t = firstTextNode(in: s, direction: direction, depth: 0, deadline: deadline),
                   let f = edgeRow(of: t, direction: direction, deadline: deadline) { return f }
            }
            node = parent
        }
        return nil
    }

    /// Depth-first: the first (or last) descendant with text and a character rectangle.
    private func firstTextNode(in element: AXUIElement, direction: Int, depth: Int, deadline: Date) -> AXUIElement? {
        guard depth < 8, Date() < deadline else { return nil }
        let role: String = attribute(element, kAXRoleAttribute) ?? ""
        if role != "AXListMarker", let v: String = attribute(element, kAXValueAttribute), !v.isEmpty,
           CharText(element: element, length: v.utf16.count).charRect(0) != nil {
            return element
        }
        guard let children: [AXUIElement] = attribute(element, kAXChildrenAttribute) else { return nil }
        for c in (direction > 0 ? children : children.reversed()).prefix(40) {
            if let t = firstTextNode(in: c, direction: direction, depth: depth + 1, deadline: deadline) { return t }
        }
        return nil
    }

    /// The topmost (direction 1) or bottommost (direction -1) row of a text node.
    private func edgeRow(of element: AXUIElement, direction: Int, deadline: Date) -> Found? {
        guard let v: String = attribute(element, kAXValueAttribute) else { return nil }
        let text = CharText(element: element, length: v.utf16.count)
        let samples = text.samples(step: 12, deadline: deadline)
        guard let s = direction > 0 ? samples.min(by: { $0.1.y < $1.1.y }) : samples.max(by: { $0.1.y < $1.1.y }),
              let row = text.row(around: s.0, deadline: deadline) else { return nil }
        var f = Found(element: element, line: nil, rect: row.rect, charBounds: true, rowStart: row.start, rowEnd: row.end, textLength: text.length)
        f.samples = samples
        return f
    }

    /// A row under the point in a descendant text node, found without trusting frames
    /// (Chromium reports frames that do not match the drawn text): text nodes in document
    /// order run down the page, so the children are binary-searched by the y of their
    /// first character, then the chosen child is tried and entered.
    private func rowInDescendants(of element: AXUIElement, x: Double, y: Double, depth: Int, budget: inout Int, deadline: Date) -> Found? {
        guard depth < 8, budget > 0, Date() < deadline,
              let children: [AXUIElement] = attribute(element, kAXChildrenAttribute), !children.isEmpty else { return nil }
        func top(_ i: Int) -> Double? {
            budget -= 1
            guard let t = firstTextNode(in: children[i], direction: 1, depth: 0, deadline: deadline),
                  let v: String = attribute(t, kAXValueAttribute) else { return nil }
            let ty = CharText(element: t, length: v.utf16.count).charRect(0)?.y
            return ty
        }
        // The last child starting at or above y; children without text are stepped over.
        var lo = 0, hi = children.count - 1, pick = -1
        while lo <= hi, budget > 0, Date() < deadline {
            let mid = (lo + hi) / 2
            var m = mid
            var t = top(m)
            while t == nil, m > lo { m -= 1; t = top(m) }
            guard let ty = t else { lo = mid + 1; continue }
            if ty <= y + 1 { pick = m; lo = mid + 1 } else { hi = m - 1 }
        }
        guard pick >= 0 else { return nil }
        for i in [pick, pick - 1] where i >= 0 {
            let c = children[i]
            if let v: String = attribute(c, kAXValueAttribute), !v.isEmpty {
                budget -= 1
                if let r = lineFromCharBounds(c, x: x, y: y, trustFrame: false, deadline: deadline), x >= r.rect.x - 2, x <= r.rect.maxX + 2 { return r }
            }
            if let r = rowInDescendants(of: c, x: x, y: y, depth: depth + 1, budget: &budget, deadline: deadline) { return r }
        }
        return nil
    }

    /// The child of `element` whose frame contains `p`, if any.
    private func child(of element: AXUIElement, containing p: Point) -> AXUIElement? {
        guard let children: [AXUIElement] = attribute(element, kAXChildrenAttribute) else { return nil }
        for c in children.prefix(60) {
            if let f = frame(of: c), f.contains(p) { return c }
        }
        return nil
    }

    /// Debug: the hit element and its ancestors, with the parameterised attributes each offers.
    private var dumped = false
    private var dumpedChildren = 0
    private func dump(_ hit: AXUIElement, levels: Int) {
        var element = hit
        for depth in 0..<levels {
            let role: String = attribute(element, kAXRoleAttribute) ?? "?"
            var namesRef: CFArray?
            let names = AXUIElementCopyParameterizedAttributeNames(element, &namesRef) == .success ? (namesRef as? [String] ?? []) : []
            let f = frame(of: element).map { "\(Int($0.x)),\(Int($0.y)) \(Int($0.width))x\(Int($0.height))" } ?? "no frame"
            var attrsRef: CFArray?
            let attrs = AXUIElementCopyAttributeNames(element, &attrsRef) == .success ? (attrsRef as? [String] ?? []) : []
            let value: String = attribute(element, kAXValueAttribute) ?? ""
            NSLog("vimouse ruler:   [%d] %@ %@ value: %@ attrs: %@ params: %@", depth, role, f, String(value.prefix(40)), attrs.joined(separator: " "), names.joined(separator: " "))
            guard let parent: AXUIElement = attribute(element, kAXParentAttribute) else { break }
            element = parent
        }
    }

    /// The text-marker attributes are WebKit/Chromium extensions: the accessibility
    /// server passes their values through, so points and rectangles are in Cocoa screen
    /// coordinates (origin at the bottom left of the primary display), unlike the
    /// standard attributes, which it flips for us.
    private func lineFromMarkers(_ element: AXUIElement, x: Double, y: Double) -> Found? {
        let p = Coordinates.appKitPoint(fromCG: Point(x: x, y: y))
        var point = CGPoint(x: p.x, y: p.y)
        guard let pointValue = AXValueCreate(.cgPoint, &point) else { return nil }
        guard let marker = markerValue(element, Marker.forPosition, pointValue) else { log("no marker at (\(Int(x)),\(Int(y)))"); return nil }
        guard let range = markerValue(element, Marker.lineRange, marker) else { log("no line range for the marker"); return nil }
        guard let b = markerBounds(element, range), b.width > 0 else { log("no bounds for the line range"); return nil }
        guard abs(b.midY - y) <= b.height * 1.5 + 4 else { log("marker line \(b) is not under y \(Int(y))"); return nil }
        return Found(element: element, line: nil, rect: b, markerRange: range, markerHost: element)
    }

    /// The marker at the start of the line after the one starting at `m`: its end, then one
    /// character on.
    private func nextLineStart(_ host: AXUIElement, from m: AnyObject) -> AnyObject? {
        guard let end = markerValue(host, Marker.nextLineEnd, m) else { return nil }
        return markerValue(host, Marker.next, end)
    }

    /// The marker at the start of the line before the one starting at `m`.
    private func previousLineStart(_ host: AXUIElement, from m: AnyObject) -> AnyObject? {
        guard let before = markerValue(host, Marker.previous, m) else { return nil }
        return markerValue(host, Marker.previousLineStart, before) ?? before
    }

    private func normalisedBounds(_ host: AXUIElement, _ range: AnyObject, flipped: Bool) -> Rect? {
        var out: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(host, Marker.bounds as CFString, range, &out) == .success,
              let v = out, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var r = CGRect.zero
        // swiftlint:disable:next force_cast
        guard AXValueGetValue(v as! AXValue, .cgRect, &r), r.height > 0, r.height <= 120 else { return nil }
        let raw = NSRect(x: r.minX, y: r.minY, width: r.width, height: r.height)
        return flipped ? Coordinates.cgRect(fromAppKit: raw) : Rect(x: raw.minX, y: raw.minY, width: raw.width, height: raw.height)
    }

    /// Chromium and WebKit text nodes: from the element's own start marker, walk its lines
    /// until the one under the point.
    private func lineFromStartMarker(_ element: AXUIElement, x: Double, y: Double, deadline: Date) -> Found? {
        guard let frame = frame(of: element), frame.contains(Point(x: x, y: y)) || abs(frame.midY - y) < frame.height else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, Marker.startOfElement as CFString, &value) == .success, var m = value else { return nil }
        guard let firstRange = markerValue(element, Marker.lineRange, m) else { log("start marker but no line range"); return nil }
        // Which way the bounds come: the reading that lands inside the element's frame.
        guard let asCocoa = normalisedBounds(element, firstRange, flipped: true) else {
            // A "line" as tall as a page is the whole document: no inline text boxes here.
            var out: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(element, Marker.bounds as CFString, firstRange, &out) == .success,
               let v = out, CFGetTypeID(v) == AXValueGetTypeID() {
                var r = CGRect.zero
                // swiftlint:disable:next force_cast
                if AXValueGetValue(v as! AXValue, .cgRect, &r), r.height > 120 {
                    var pid: pid_t = 0
                    AXUIElementGetPid(element, &pid)
                    hollowMarkers.insert(pid)
                    log("text markers are hollow in process \(pid); skipping them from now on")
                }
            }
            if debug { diagnoseBounds(element, firstRange) }
            return nil
        }
        let asCG = normalisedBounds(element, firstRange, flipped: false)
        // Prefer the unflipped reading when it fits the element: a tall web area intersects both.
        let flipped = !(asCG.map { frame.intersects($0) } ?? false) && frame.intersects(asCocoa)
        log("marker route: first line \(asCocoa) (flipped) / \(asCG.map { "\($0)" } ?? "nil") (unflipped), frame \(frame)")
        var range: AnyObject = firstRange
        var lastMid = -Double.infinity
        for i in 0..<80 {
            guard Date() < deadline else { log("out of time walking lines"); return nil }
            if let b = normalisedBounds(element, range, flipped: flipped), b.width > 0 {
                if i < 4 { log("marker route: line \(i) \(b)") }
                if y >= b.y - 1, y < b.maxY + 1 {
                    log("line by start marker (\(flipped ? "flipped" : "unflipped")): \(b)")
                    return Found(element: element, line: nil, rect: b, markerHost: element, lineStart: m, flipped: flipped)
                }
                if b.y > y || b.midY <= lastMid { break }
                lastMid = b.midY
            }
            guard let nm = nextLineStart(element, from: m), let nr = markerValue(element, Marker.lineRange, nm) else { break }
            m = nm
            range = nr
        }
        log("no line under y \(Int(y)) by start marker")
        return nil
    }

    /// A row can be shared by several text nodes (a link in a sentence): take in the
    /// segments found just left and right of this one at the same height.
    private func widened(_ f: Found, deadline: Date) -> Found {
        guard f.charBounds || f.textAPI, f.line == nil else { return f }
        var out = f
        // Rows split across nodes (inline code, links): take in document-order neighbours
        // on the same row, a couple each way.
        if f.charBounds {
            for dir in [1, -1] {
                var from = f.element
                for _ in 0..<2 {
                    guard Date() < deadline, let n = edgeRow(ofTextNodeAfter: from, direction: dir, deadline: deadline),
                          abs(n.rect.midY - f.rect.midY) < f.rect.height / 2 else { break }
                    let minX = min(out.rect.x, n.rect.x), maxX = max(out.rect.maxX, n.rect.maxX)
                    let minY = min(out.rect.y, n.rect.y), maxY = max(out.rect.maxY, n.rect.maxY)
                    out.rect = Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                    from = n.element
                }
            }
        }
        // A row already spanning most of its element has nothing to gain from hit tests.
        if let ef = frame(of: f.element), out.rect.width >= ef.width * 0.7 { return out }
        for sign in [-1.0, 1.0] {
            for _ in 0..<4 {
                guard Date() < deadline else { return out }
                let px = sign < 0 ? out.rect.x - 6 : out.rect.maxX + 6
                guard let seg = locate(x: px, y: out.rect.midY, deadline: deadline),
                      abs(seg.rect.midY - out.rect.midY) < 3, !seg.rect.intersects(out.rect) || seg.rect != out.rect
                else { break }
                let minX = min(out.rect.x, seg.rect.x), maxX = max(out.rect.maxX, seg.rect.maxX)
                guard maxX - minX > out.rect.width else { break }
                out.rect = Rect(x: minX, y: out.rect.y, width: maxX - minX, height: out.rect.height)
            }
        }
        return out
    }

    /// A text node addressed by character index: `AXBoundsForRange` over single characters,
    /// whose y is monotonic through the text (Chromium).
    private struct CharText {
        let element: AXUIElement
        let length: Int

        func rect(_ i: Int, _ len: Int = 1) -> Rect? {
            var cf = CFRange(location: i, length: len)
            guard let rv = AXValueCreate(.cfRange, &cf) else { return nil }
            var out: CFTypeRef?
            guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, rv, &out) == .success,
                  let v = out, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
            var r = CGRect.zero
            // swiftlint:disable:next force_cast
            guard AXValueGetValue(v as! AXValue, .cgRect, &r), r.height > 0, r.height <= 120 else { return nil }
            return Rect(x: r.minX, y: r.minY, width: r.width, height: r.height)
        }

        /// The rectangle of character `i`, or of the next one with a rectangle (whitespace may have none).
        func charRect(_ i: Int) -> Rect? {
            for j in i..<min(length, i + 4) { if let r = rect(j) { return r } }
            return nil
        }

        /// Rectangles at every `step`th character; characters without one drop out.
        func samples(step: Int, deadline: Date) -> [(Int, Rect)] {
            var out: [(Int, Rect)] = []
            var i = 0
            while i < length, Date() < deadline {
                if let r = rect(i) { out.append((i, r)) }
                i += step
            }
            if (length - 1) % step != 0, let r = rect(length - 1) { out.append((length - 1, r)) }
            return out
        }

        /// The row containing character `i`: its first and last indices and its rectangle.
        /// Characters without a rectangle (inline children, whitespace) are stepped over.
        func row(around i: Int, deadline: Date) -> (start: Int, end: Int, rect: Rect)? {
            guard let on = charRect(i) else { return nil }
            func sameRow(_ r: Rect) -> Bool { abs(r.y - on.y) <= 2 }
            // Gallop outwards in shrinking strides; a character without a rectangle is
            // read from its neighbours. The search stays local, so a hole costs a few
            // calls rather than a wrong row.
            func rectNear(_ j: Int, _ dir: Int) -> Rect? {
                for k in 0..<4 {
                    let idx = j + dir * k
                    guard idx >= 0, idx < length else { return nil }
                    if let r = rect(idx) { return r }
                }
                return nil
            }
            func extend(from i: Int, _ dir: Int) -> Int {
                var pos = i
                var stride = 16
                while stride >= 1, Date() < deadline {
                    let cand = pos + dir * stride
                    if cand >= 0, cand < length, let r = rectNear(cand, dir), sameRow(r) {
                        pos = cand
                    } else {
                        stride /= 2
                    }
                }
                return pos
            }
            let start = extend(from: i, -1)
            let end = extend(from: i, 1)
            let line = rect(start, end - start + 1) ?? Rect(x: on.x, y: on.y, width: on.width, height: on.height)
            return (start, end, line)
        }
    }

    /// Lines from character rectangles: a binary search finds the character under `y`,
    /// then its row.
    private func lineFromCharBounds(_ element: AXUIElement, x: Double, y: Double, trustFrame: Bool = true, deadline: Date) -> Found? {
        // The frame is only a cheap filter, and not when it is plainly wrong (Chromium
        // reports one-pixel frames for some text nodes while their characters have bounds,
        // and frames elsewhere than the text when a container is being searched).
        guard let frame = frame(of: element), let value: String = attribute(element, kAXValueAttribute) else { return nil }
        if trustFrame, frame.height >= 4, y < frame.y - 2 || y > frame.maxY + 2 { return nil }
        let n = value.utf16.count
        guard n > 0 else { return nil }
        let text = CharText(element: element, length: n)
        guard let first = text.charRect(0) else { log("char route: no rectangle for character 0 of \(n)"); return nil }
        guard y >= first.y - 1 else { return nil }
        // WebKit answers index ranges with one glyph's geometry whatever the range; Chromium
        // returns the union. Twenty characters narrower than seven glyphs is a lie.
        if n >= 20, let span = text.rect(0, 20), span.width < first.width * 7 {
            log("char route: not trustworthy here (20 characters span \(Int(span.width)) px)")
            return nil
        }
        // Sample the text, then take the sample on the row under y (holes drop out).
        let samples = text.samples(step: 12, deadline: deadline)
        guard let s = samples.first(where: { y >= $0.1.y - 1 && y < $0.1.maxY + 1 })
                ?? samples.filter({ abs($0.1.midY - y) < $0.1.height }).min(by: { abs($0.1.midY - y) < abs($1.1.midY - y) })
        else {
            log("char route: no sampled row under y \(Int(y)) (\(samples.count) samples of \(n))")
            return nil
        }
        guard let row = text.row(around: s.0, deadline: deadline) else { return nil }
        // The whole text on one row inside an element several rows tall: also a lie.
        if row.start == 0, row.end == n - 1, frame.height > row.rect.height * 1.8 {
            log("char route: not trustworthy here (all \(n) characters on one row of a \(Int(frame.height)) px element)")
            return nil
        }
        log("line by character rows [\(row.start)..\(row.end)] of \(n): \(row.rect)")
        var f = Found(element: element, line: nil, rect: row.rect, charBounds: true, rowStart: row.start, rowEnd: row.end, textLength: n)
        f.samples = samples
        return f
    }

    /// Debug: what the bounds calls return for a line range and for an index range.
    private func diagnoseBounds(_ element: AXUIElement, _ range: AnyObject) {
        var out: CFTypeRef?
        let err = AXUIElementCopyParameterizedAttributeValue(element, Marker.bounds as CFString, range, &out)
        var desc = "err \(err.rawValue)"
        if let v = out {
            desc += " type \(CFGetTypeID(v)) (AXValue is \(AXValueGetTypeID()))"
            if CFGetTypeID(v) == AXValueGetTypeID() {
                var r = CGRect.zero
                // swiftlint:disable:next force_cast
                if AXValueGetValue(v as! AXValue, .cgRect, &r) { desc += " rect \(r)" } else { desc += " AXValue kind \(AXValueGetType(v as! AXValue).rawValue)" }
            } else {
                desc += " \(v)"
            }
        }
        log("marker-range bounds: \(desc)")
        let n: Int = attribute(element, kAXNumberOfCharactersAttribute) ?? -1
        var cf = CFRange(location: 0, length: min(5, max(n, 1)))
        if let rv = AXValueCreate(.cfRange, &cf) {
            var out2: CFTypeRef?
            let err2 = AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, rv, &out2)
            var d2 = "err \(err2.rawValue)"
            if let v = out2, CFGetTypeID(v) == AXValueGetTypeID() {
                var r = CGRect.zero
                // swiftlint:disable:next force_cast
                if AXValueGetValue(v as! AXValue, .cgRect, &r) { d2 += " rect \(r)" }
            }
            log("index-range bounds (0..<\(cf.length) of \(n)): \(d2)")
            var out3: CFTypeRef?
            let err3 = AXUIElementCopyParameterizedAttributeValue(element, kAXLineForIndexParameterizedAttribute as CFString, 3 as CFNumber, &out3)
            log("line for index 3: err \(err3.rawValue) \(out3.map { "\($0)" } ?? "nil")")
        }
    }

    /// Chromium: the hit element's start as a text index, its line number, then the
    /// numbered lines from there until the one under the point.
    private func lineFromWebIndex(_ wa: AXUIElement, hit: AXUIElement, x: Double, y: Double, deadline: Date) -> Found? {
        guard let hitFrame = frame(of: hit) else { return nil }
        guard let idx = markerValue(wa, Marker.indexForChild, hit) as? Int else { log("no text index for the hit element"); return nil }
        guard let marker = markerValue(wa, Marker.forIndex, idx as CFNumber) else { log("no marker for index \(idx)"); return nil }
        guard let first = markerValue(wa, Marker.lineForMarker, marker) as? Int else { log("no line for the marker"); return nil }
        // Which way the bounds come: the reading that lands inside the hit element's frame.
        var flipped = true
        if let raw = rawMarkerBounds(wa, line: first) {
            let asCocoa = Coordinates.cgRect(fromAppKit: raw)
            let asCG = Rect(x: raw.minX, y: raw.minY, width: raw.width, height: raw.height)
            flipped = hitFrame.intersects(asCocoa) || !hitFrame.intersects(asCG)
            log("web lines from \(first) at index \(idx); bounds \(flipped ? "flipped" : "unflipped")")
        }
        for n in first..<(first + 60) {
            guard Date() < deadline, let b = webLineBounds(wa, line: n, flipped: flipped) else { break }
            if b.y > hitFrame.maxY + 2 { break }
            if y >= b.y - 2, y < b.maxY + 2, b.width > 0 {
                return Found(element: hit, line: nil, rect: b, markerHost: wa, webLine: n, flipped: flipped)
            }
        }
        log("no numbered web line under y \(Int(y)) from line \(first)")
        return nil
    }

    private func rawMarkerBounds(_ wa: AXUIElement, line n: Int) -> NSRect? {
        guard let range = markerValue(wa, Marker.rangeForLine, n as CFNumber) else { return nil }
        var out: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(wa, Marker.bounds as CFString, range, &out) == .success,
              let v = out, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var r = CGRect.zero
        // swiftlint:disable:next force_cast
        guard AXValueGetValue(v as! AXValue, .cgRect, &r), r.height > 0, r.height <= 120 else { return nil }
        return NSRect(x: r.minX, y: r.minY, width: r.width, height: r.height)
    }

    private func webLineBounds(_ wa: AXUIElement, line n: Int, flipped: Bool) -> Rect? {
        guard let raw = rawMarkerBounds(wa, line: n) else { return nil }
        return flipped ? Coordinates.cgRect(fromAppKit: raw) : Rect(x: raw.minX, y: raw.minY, width: raw.width, height: raw.height)
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
        return Coordinates.cgRect(fromAppKit: NSRect(x: r.minX, y: r.minY, width: r.width, height: r.height))
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
