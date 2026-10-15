/// The frame accepted by an application may be smaller than the requested maximum.
/// Keep that applied frame with its origin so the next toggle can still restore it.
public struct MaximizeHistory: Sendable {
    public let original: Rect
    public let applied: Rect

    public init(original: Rect, applied: Rect) {
        self.original = original
        self.applied = applied
    }

    public func matches(_ current: Rect, verticalOnly: Bool = false) -> Bool {
        if verticalOnly {
            return abs(current.y - applied.y) <= 2 && abs(current.height - applied.height) <= 2
        }
        return current.approximatelyEquals(applied, tolerance: 2)
    }

    public func restorationFrame(from current: Rect, verticalOnly: Bool = false) -> Rect {
        verticalOnly
            ? Rect(x: current.x, y: original.y, width: current.width, height: original.height)
            : original
    }
}
