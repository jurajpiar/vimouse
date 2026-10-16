#if canImport(AppKit)
import ApplicationServices
import Foundation

enum Permissions {
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
