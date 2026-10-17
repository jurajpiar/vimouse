#if canImport(AppKit)
import AppKit
import ApplicationServices
import VimouseCore

/// Headless exercise of the line provider against running apps, for unattended
/// iteration: `vimouse --probe "Markdown Preview" "Brave Browser" Claude`.
/// For each app it finds a paragraph (a long static text whose centre is actually hit
/// by a screen point), hit-tests every line in its left column from the top of the
/// screen down, then walks the lines with the stepping routes and reports anything
/// skipped, invented or not retraced. Run with VIMOUSE_DEBUG=1 for the provider's log.
enum Probe {
    static func run(apps: [String]) -> Int32 {
        guard AXIsProcessTrusted() else {
            print("probe: no Accessibility access for this process (grant it to the terminal running it)")
            return 2
        }
        setlinebuf(stdout)
        var failures = 0
        for name in apps {
            print("=== \(name)")
            guard let app = NSWorkspace.shared.runningApplications.first(where: { ($0.localizedName ?? "").lowercased().contains(name.lowercased()) }) else {
                print("not running"); failures += 1; continue
            }
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(appElement, 0.2)
            AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            usleep(200_000)
            guard let target = paragraph(in: appElement, pid: app.processIdentifier) else {
                print("no visible paragraph found (is a document with text showing, uncovered?)"); failures += 1; continue
            }
            print("paragraph \(target.frame) \"\(target.text.prefix(50))\"")
            let before = failures
            let screen = NSScreen.screens.first.map { Coordinates.cgRect(fromAppKit: $0.frame) } ?? Rect(x: 0, y: 0, width: 3000, height: 2000)
            let provider = AXLineProvider()
            // Ground truth: every line a plain hit test finds in the paragraph's left
            // column, top to bottom of the screen. Then walk down from the first with the
            // stepping routes and check that nothing is skipped, invented or revisited,
            // and that the way back up retraces the way down.
            let column = target.frame.x + min(12, target.frame.width / 2)
            var scanned: [Rect] = []
            var y = screen.y + 30
            while y < screen.maxY {
                if let l = provider.textLine(at: column, y: y, direction: 0, on: screen),
                   !scanned.contains(where: { abs($0.midY - l.midY) < 2 }) {
                    scanned.append(l)
                }
                y += 6
            }
            scanned.sort { $0.midY < $1.midY }
            guard let first = scanned.first else { print("FAIL: no line found in column \(Int(column))"); failures += 1; continue }
            print("scan found \(scanned.count) lines in column \(Int(column)), y \(Int(first.y)) to \(Int(scanned.last!.maxY))")
            var lines = [first]
            y = first.midY
            let t0 = Date()
            var steps = 0
            while lines.count < 300, let l = provider.textLine(at: column, y: y, direction: 1, on: screen) {
                steps += 1
                if l.midY <= y { print("FAIL: step down from y \(Int(y)) went to \(l)"); failures += 1; break }
                if l.maxY > screen.maxY - 40 { break }
                lines.append(l)
                y = l.midY
            }
            var back: [Rect] = []
            while back.count < lines.count, let l = provider.textLine(at: column, y: y, direction: -1, on: screen) {
                steps += 1
                if l.midY >= y { print("FAIL: step up from y \(Int(y)) went to \(l)"); failures += 1; break }
                back.append(l)
                y = l.midY
            }
            print("walked \(lines.count) lines down (\(Int(first.y)) to \(Int(lines.last!.maxY))), \(back.count) back up, " +
                  String(format: "%.0f ms per step", steps > 0 ? Date().timeIntervalSince(t0) * 1000 / Double(steps) : 0))
            func same(_ a: Rect, _ b: Rect) -> Bool { min(a.maxY, b.maxY) - max(a.y, b.y) > min(a.height, b.height) / 2 }
            for l in scanned where l.midY < lines.last!.midY && !lines.contains(where: { same($0, l) }) {
                print("FAIL: skipped line at \(l) going down"); failures += 1
            }
            for l in lines where !scanned.contains(where: { same($0, l) }) {
                print("WARN: step landed on \(l), which no hit test in the column found")
            }
            for (a, b) in zip(lines, lines.dropFirst()) {
                if b.y < a.maxY - 2 { print("WARN: overlap between \(a) and \(b)") }
                if abs(b.height - a.height) > a.height * 0.6 { print("WARN: height jump \(a.height) -> \(b.height)") }
            }
            let expected = Array(lines.dropLast().reversed())
            if back.count < expected.count, let l = back.last, l.y > first.maxY { print("FAIL: the way up stopped after \(back.count) of \(expected.count) lines"); failures += 1 }
            for (i, (down, up)) in zip(expected, back).enumerated() where !same(down, up) {
                print("FAIL: back step \(i + 1) landed at y \(Int(up.midY)), expected \(Int(down.midY))"); failures += 1
                break
            }
            if failures == before { print("ok") }
        }
        return failures == 0 ? 0 : 1
    }

    private struct Target { var frame: Rect; var text: String }

    /// The largest long static text in the app's windows whose centre a screen hit test
    /// attributes to this app (so it is not covered).
    private static func paragraph(in app: AXUIElement, pid: pid_t) -> Target? {
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else { return nil }
        var best: Target?
        var visited = 0
        let systemWide = AXUIElementCreateSystemWide()
        func walk(_ e: AXUIElement, depth: Int) {
            visited += 1
            if visited > 4000 || depth > 60 { return }
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(e, kAXRoleAttribute as CFString, &roleRef)
            let role = roleRef as? String ?? ""
            if role == "AXStaticText" || role == "AXTextArea" {
                var valueRef: CFTypeRef?
                AXUIElementCopyAttributeValue(e, kAXValueAttribute as CFString, &valueRef)
                if let text = valueRef as? String, text.count >= 120, let f = frame(of: e), f.height >= 30, f.width >= 200 {
                    let c = f.center
                    var hitRef: AXUIElement?
                    var hitPid: pid_t = 0
                    if AXUIElementCopyElementAtPosition(systemWide, Float(c.x), Float(c.y), &hitRef) == .success, let h = hitRef {
                        AXUIElementGetPid(h, &hitPid)
                    }
                    if hitPid == pid, (best.map { f.width * f.height > $0.frame.width * $0.frame.height } ?? true) {
                        best = Target(frame: f, text: text)
                    }
                }
            }
            var childrenRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                  let children = childrenRef as? [AXUIElement] else { return }
            for c in children { walk(c, depth: depth + 1) }
        }
        for w in windows { walk(w, depth: 0) }
        return best
    }

    private static func frame(of element: AXUIElement) -> Rect? {
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
