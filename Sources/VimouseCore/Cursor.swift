/// A marker drawn at the pointer while a mode is active, chosen by name in
/// `[cursor] style`. The second plugin kind: register styles next to the modes.
public protocol CursorStyle: AnyObject {
    /// Name used in `[cursor] style`; lower case.
    var id: String { get }
    /// One line for the config comment.
    var summary: String { get }
    func draw(at p: Point, size: Double, colour: String) -> [Drawable]
}

public final class RingCursor: CursorStyle {
    public let id = "ring"
    public let summary = "a ring around the pointer"
    public init() {}
    public func draw(at p: Point, size: Double, colour: String) -> [Drawable] {
        [.ring(p, radius: size / 2, colour: colour, alpha: 1, width: 3)]
    }
}

public final class CrosshairCursor: CursorStyle {
    public let id = "crosshair"
    public let summary = "a crosshair centred on the pointer"
    public init() {}
    public func draw(at p: Point, size: Double, colour: String) -> [Drawable] {
        [.crosshair(p, size: size, colour: colour, alpha: 1, width: 2)]
    }
}

public final class DotCursor: CursorStyle {
    public let id = "dot"
    public let summary = "a filled dot on the pointer"
    public init() {}
    public func draw(at p: Point, size: Double, colour: String) -> [Drawable] {
        [.dot(p, radius: size / 4, colour: colour, alpha: 0.9)]
    }
}

/// `[cursor]` settings.
public struct CursorConfig: Equatable {
    /// Style id, or "" for no marker (the real pointer only).
    public var style = "ring"
    public var size: Double = 36
    /// "#RRGGBB", or "" for the active mode's colour.
    public var colour = ""
    public init() {}
}
