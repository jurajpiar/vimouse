#if canImport(AppKit)
import CoreGraphics
import Foundation
import VimouseCore

/// An active (filtering) CGEventTap on keyboard events. The handler returns
/// true to swallow the event so the focused app never sees it.
final class InputTap {
    struct StartError: Error, CustomStringConvertible {
        var description: String { "CGEvent.tapCreate returned nil (Accessibility permission missing?)" }
    }

    /// `isModifier` is true for a modifier key going down or up (a flagsChanged event).
    typealias Handler = (_ key: KeyPress, _ isKeyDown: Bool, _ isRepeat: Bool, _ isModifier: Bool) -> Bool
    var handler: Handler?

    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    func start() throws {
        guard port == nil else { return }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: InputTap.callback,
            userInfo: refcon
        ) else { throw StartError() }

        self.port = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
    }

    func stop() {
        if let port { CGEvent.tapEnable(tap: port, enable: false); CFMachPortInvalidate(port) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        port = nil
        source = nil
    }

    private static let callback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let tap = Unmanaged<InputTap>.fromOpaque(refcon).takeUnretainedValue()

        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS disables taps that take too long; re-enable and carry on.
            if let port = tap.port { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        case .keyDown, .keyUp:
            // Our own synthetic events (a cancel-drag Escape) pass through untouched.
            if event.getIntegerValueField(.eventSourceUserData) == Pointer.syntheticMarker {
                return Unmanaged.passUnretained(event)
            }
            let code = KeyCode(rawValue: UInt16(event.getIntegerValueField(.keyboardEventKeycode)))
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            let key = KeyPress(code, InputTap.modifiers(from: event.flags))
            let swallow = tap.handler?(key, type == .keyDown, isRepeat, false) ?? false
            return swallow ? nil : Unmanaged.passUnretained(event)
        case .flagsChanged:
            let code = KeyCode(rawValue: UInt16(event.getIntegerValueField(.keyboardEventKeycode)))
            // Down or up is read from the resulting flags: the key's own bit is set after a press.
            let isDown: Bool
            if let bit = code.modifierBit {
                isDown = event.flags.contains(InputTap.cgMask(bit))
            } else if code == .function {
                isDown = event.flags.contains(.maskSecondaryFn)
            } else {
                return Unmanaged.passUnretained(event)
            }
            let key = KeyPress(code, InputTap.modifiers(from: event.flags))
            let swallow = tap.handler?(key, isDown, false, true) ?? false
            return swallow ? nil : Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private static func cgMask(_ m: Modifiers) -> CGEventFlags {
        switch m {
        case .shift: return .maskShift
        case .control: return .maskControl
        case .option: return .maskAlternate
        case .command: return .maskCommand
        default: return []
        }
    }

    private static func modifiers(from flags: CGEventFlags) -> Modifiers {
        var m: Modifiers = []
        if flags.contains(.maskShift) { m.insert(.shift) }
        if flags.contains(.maskControl) { m.insert(.control) }
        if flags.contains(.maskAlternate) { m.insert(.option) }
        if flags.contains(.maskCommand) { m.insert(.command) }
        return m
    }
}
#endif
