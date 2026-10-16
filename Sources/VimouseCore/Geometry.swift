// All geometry in VimouseCore uses the Core Graphics convention:
// origin at the top-left of the primary display, y grows downwards.
// Conversion to AppKit's bottom-left convention happens only in VimouseMac.

public struct Point: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public enum Quadrant: CaseIterable, Hashable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight
}

public struct Rect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
    public var center: Point { Point(x: midX, y: midY) }

    public func contains(_ p: Point) -> Bool {
        p.x >= x && p.x < maxX && p.y >= y && p.y < maxY
    }

    /// Splits the rectangle into four equal quadrants.
    public func subdivided() -> [Quadrant: Rect] {
        let w = width / 2
        let h = height / 2
        return [
            .topLeft: Rect(x: x, y: y, width: w, height: h),
            .topRight: Rect(x: x + w, y: y, width: w, height: h),
            .bottomLeft: Rect(x: x, y: y + h, width: w, height: h),
            .bottomRight: Rect(x: x + w, y: y + h, width: w, height: h),
        ]
    }
}
