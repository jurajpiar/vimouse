#if canImport(AppKit)
import AppKit
import ApplicationServices
import VimouseCore

/// Headless exercise of the line provider against running apps, for unattended
/// iteration: `vimouse --probe "Markdown Preview" "Brave Browser" Claude`.
/// For each app it finds a paragraph (a long static text whose centre is actually hit
/// by a screen point), then asks for the line under that point, three lines down and
/// two up, printing every rectangle. Run with VIMOUSE_DEBUG=1 for the provider's log.
enum Probe {
    static func run(apps: [String]) -> Int32 {
        guard AXIsProcessTrusted() else {
            print("probe: no Accessibility access for this process (grant it to the terminal running it)")
            return 2
        }
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
            let p = Point(x: target.frame.x + min(60, target.frame.width / 3), y: target.frame.y + min(target.frame.height / 2, 30))
            let screen = NSScreen.screens.first.map { Coordinates.cgRect(fromAppKit: $0.frame) } ?? Rect(x: 0, y: 0, width: 3000, height: 2000)
            let provider = AXLineProvider()
            print("point \(p)")
            var y = p.y
            guard let first = provider.textLine(at: p.x, y: y, direction: 0, on: screen) else {
                print("FAIL: no line under the point"); failures += 1; continue
            }
            print("line 0: \(first)")
            var lines = [first]
            y = first.midY
            let steps = 10
            let t0 = Date()
            for i in 1...steps {
                guard let l = provider.textLine(at: p.x, y: y, direction: 1, on: screen) else { print("FAIL: no line \(i) below"); failures += 1; break }
                print("line +\(i): \(l)")
                lines.append(l)
                y = l.midY
            }
            var back: [Rect] = []
            for i in 1...(lines.count - 1) {
                guard let l = provider.textLine(at: p.x, y: y, direction: -1, on: screen) else { print("FAIL: no line \(i) back up"); failures += 1; break }
                print("line back \(i): \(l)")
                back.append(l)
                y = l.midY
            }
            print(String(format: "%.0f ms per step", Date().timeIntervalSince(t0) * 1000 / Double(lines.count - 1 + back.count)))
            // Sanity: downwards and consecutive, no overlap, similar heights, and the way
            // back retraces the way down.
            for (a, b) in zip(lines, lines.dropFirst()) {
                if b.midY <= a.midY { print("WARN: not below: \(a) then \(b)"); failures += 1 }
                if b.y < a.maxY - 2 { print("WARN: overlap between \(a) and \(b)") }
                if b.y - a.maxY > a.height * 2.5 { print("WARN: gap of \(Int(b.y - a.maxY)) px between lines (skipped one?)") }
                if abs(b.height - a.height) > a.height * 0.6 { print("WARN: height jump \(a.height) -> \(b.height)") }
            }
            let expected = Array(lines.dropLast().reversed())
            for (i, (down, up)) in zip(expected, back).enumerated() where abs(down.midY - up.midY) > 2 {
                print("WARN: back step \(i + 1) landed at y \(Int(up.midY)), expected \(Int(down.midY))"); failures += 1
            }
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
