/// One descent through the quadrant tree. `stack[0]` is the root (the screen).
public struct BisectSession: Equatable, Sendable {
    public private(set) var stack: [Rect]

    public init(root: Rect) {
        stack = [root]
    }

    public var root: Rect { stack[0] }
    public var current: Rect { stack[stack.count - 1] }
    /// Every rectangle above the current one, root first.
    public var ancestors: ArraySlice<Rect> { stack.dropLast() }
    /// 0 at the root.
    public var depth: Int { stack.count - 1 }

    public mutating func select(_ quadrant: Quadrant) {
        stack.append(current.subdivided()[quadrant]!)
    }

    /// Narrow to one half along one axis; `up()` undoes it like a quadrant pick.
    public mutating func select(_ half: Half) {
        stack.append(current.half(half))
    }

    /// Returns false when already at the root.
    @discardableResult
    public mutating func up() -> Bool {
        guard stack.count > 1 else { return false }
        stack.removeLast()
        return true
    }

    public mutating func reset() {
        stack = [root]
    }
}
