import Foundation

public enum Geometry {
    /// AppKit's primary display bottom-left -> AX/CG global upper-left. This is
    /// deliberately NOT based on NSScreen.main (which follows keyboard focus).
    public static func flip(_ r: Rect, primaryHeight: Double) -> Rect {
        Rect(x: r.x, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }
    public static func flip(_ p: Point, primaryHeight: Double) -> Point {
        Point(x: p.x, y: primaryHeight - p.y)
    }
    public static func bestScreen(for window: Rect, visibleFrames: [Rect]) -> Rect? {
        visibleFrames.max { a, b in
            (a.intersection(window)?.area ?? 0) < (b.intersection(window)?.area ?? 0)
        }.flatMap { $0.intersection(window) == nil ? nil : $0 }
    }
    /// Never covers native controls, clamps onto content, or mutates the target.
    public static func externalHeader(for window: Rect, in visibleFrame: Rect,
                                      height: Double = 30) -> Rect? {
        guard window.isValid, visibleFrame.isValid, height.isFinite, height > 0 else { return nil }
        let header = Rect(x: window.x, y: window.y - height, width: window.width, height: height)
        return visibleFrame.contains(header, tolerance: 0.5) ? header : nil
    }
    /// Called ONLY after an explicit user command for ONE focused window.
    public static func reserveSpace(for window: Rect, in screen: Rect,
                                    headerHeight: Double = 30, minimumHeight: Double = 160) -> Rect? {
        guard window.isValid, screen.isValid, headerHeight > 0 else { return nil }
        guard window.width <= screen.width, screen.height > headerHeight + minimumHeight else { return nil }
        let y = max(window.y, screen.y + headerHeight)
        let height = min(window.height, screen.maxY - y)
        guard height >= minimumHeight else { return nil }
        let x = min(max(window.x, screen.x), screen.maxX - window.width)
        return Rect(x: x, y: y, width: window.width, height: height)
    }
}

public struct OrderedWindow: Sendable {
    public let id: UInt32
    public let pid: Int32
    public let frame: Rect
    public init(id: UInt32, pid: Int32, frame: Rect) {
        self.id = id; self.pid = pid; self.frame = frame
    }
}

public enum OrderingPolicy {
    /// Windows are front-to-back. A header may not float above an intervening
    /// foreign window that ought to cover it. A missing ID is not assumed safe.
    public static func isSafe(headerID: UInt32, targetID: UInt32, ownPID: Int32,
                              headerFrame: Rect, frontToBack: [OrderedWindow]) -> Bool {
        guard let h = frontToBack.firstIndex(where: { $0.id == headerID }),
              let t = frontToBack.firstIndex(where: { $0.id == targetID }), h < t else { return false }
        return !frontToBack[(h + 1)..<t].contains {
            $0.pid != ownPID && $0.frame.intersection(headerFrame) != nil
        }
    }
}
