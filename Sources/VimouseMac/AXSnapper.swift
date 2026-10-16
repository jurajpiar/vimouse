#if canImport(AppKit)
import AppKit
import ApplicationServices
import VimouseCore

/// Snaps the pointer to clickable UI elements of the frontmost app, using the
/// Accessibility (AX) tree. The tree is walked once per activation (cached), pruned
/// to what is on screen, and capped in size and time so a slow app cannot stall
/// the key handler. AX positions are in CG coordinates, the same as VimouseCore.
final class AXSnapper: SnapProvider, ElementProvider {
    /// Element roles that are worth snapping to. Anything with an AXPress action also counts.
    private static let clickableRoles: Set<String> = [
        "AXButton", "AXLink", "AXCheckBox", "AXRadioButton", "AXMenuItem", "AXMenuBarItem",
        "AXPopUpButton", "AXComboBox", "AXTextField", "AXTextArea", "AXSearchField",
        "AXTab", "AXDisclosureTriangle", "AXSlider", "AXIncrementor", "AXCell", "AXSwitch",
        "AXToolbarButton", "AXColorWell", "AXDockItem", "AXImage",
    ]

    var maxElements = 1500
    var timeBudget: TimeInterval = 0.15

    private var centres: [Point] = []
    private var frames: [Rect] = []
    private var preparedScreen: Rect?
    private var preparedAt = Date.distantPast

    /// Frames of the clickable elements on `screen`; the tree is walked again when the
    /// cache is older than a moment (the frontmost app may have changed).
    func elements(on screen: Rect) -> [Rect] {
        if preparedScreen != screen || Date().timeIntervalSince(preparedAt) > 1 { prepare(screen: screen) }
        return frames
    }

    func prepare(screen: Rect) {
        centres = []
        frames = []
        preparedScreen = screen
        preparedAt = Date()
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.1)
        // Chromium/Electron apps expose their full tree only to assistive clients.
        AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        let deadline = Date().addingTimeInterval(timeBudget)
        var visited = 0
        guard let windows: [AXUIElement] = attribute(appElement, kAXWindowsAttribute) else { return }
        for w in windows {
            walk(w, clip: screen, deadline: deadline, visited: &visited)
            if visited >= maxElements || Date() > deadline { break }
        }
    }

    func snapPoint(in rect: Rect) -> Point? {
        let c = rect.center
        return centres.filter { rect.contains($0) }.min { a, b in
            (a.x - c.x) * (a.x - c.x) + (a.y - c.y) * (a.y - c.y) < (b.x - c.x) * (b.x - c.x) + (b.y - c.y) * (b.y - c.y)
        }
    }

    // MARK: Tree walk

    private func walk(_ element: AXUIElement, clip: Rect, deadline: Date, visited: inout Int) {
        visited += 1
        if visited >= maxElements || Date() > deadline { return }

        guard let frame = frame(of: element) else {
            // Some containers report no frame; still look inside them.
            descend(element, clip: clip, deadline: deadline, visited: &visited)
            return
        }
        guard frame.intersects(clip) else { return }

        let role: String = attribute(element, kAXRoleAttribute) ?? ""
        if isClickable(element, role: role) {
            let visible = frame.intersection(clip)
            if visible.width > 2, visible.height > 2 {
                centres.append(visible.center)
                frames.append(visible)
            }
        }
        // Scroll areas clip their children; everything else inherits the clip.
        let childClip = role == "AXScrollArea" ? clip.intersection(frame) : clip
        if childClip.width > 0, childClip.height > 0 {
            descend(element, clip: childClip, deadline: deadline, visited: &visited)
        }
    }

    private func descend(_ element: AXUIElement, clip: Rect, deadline: Date, visited: inout Int) {
        guard let children: [AXUIElement] = attribute(element, kAXChildrenAttribute) else { return }
        for child in children {
            walk(child, clip: clip, deadline: deadline, visited: &visited)
            if visited >= maxElements || Date() > deadline { return }
        }
    }

    private func isClickable(_ element: AXUIElement, role: String) -> Bool {
        if AXSnapper.clickableRoles.contains(role) { return true }
        var names: CFArray?
        if AXUIElementCopyActionNames(element, &names) == .success, let actions = names as? [String] {
            return actions.contains(kAXPressAction)
        }
        return false
    }

    // MARK: AX helpers

    private func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
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
