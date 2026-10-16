#if canImport(AppKit)
import ApplicationServices
import Carbon
import CoreGraphics
import Foundation

enum Permissions {
    /// Can this process still create a filtering event tap? `AXIsProcessTrusted` keeps
    /// saying yes after the user removes the app from the Accessibility list, but tap
    /// creation starts failing, so this is the reliable probe (Apple forums, DTS).
    static func canFilterEvents() -> Bool {
        let mask: CGEventMask = 1 << CGEventType.keyDown.rawValue
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: { _, _, e, _ in Unmanaged.passUnretained(e) }, userInfo: nil
        ) else { return false }
        CFMachPortInvalidate(port)
        return true
    }

    /// Secure input (a password field, or a terminal with Secure Keyboard Entry) blocks
    /// every event tap in the system until it ends.
    static var secureInputActive: Bool { IsSecureEventInputEnabled() }

    /// Returns true if trusted. Otherwise shows the system prompt once and returns false.
    static func ensureAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func pollUntilTrusted(interval: TimeInterval = 1, then action: @escaping () -> Void) {
        Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { timer in
            if AXIsProcessTrusted() {
                timer.invalidate()
                action()
            }
        }
    }
}
#endif
