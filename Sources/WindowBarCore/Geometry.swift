import Foundation

public enum Geometry {
    /// Smallest window that gets a header. Applied to BOTH the AX frame (scan) and the on-screen CG frame
    /// (render): Stage Manager keeps the AX frame at full size while the CG frame is a strip thumbnail.
    public static let minimumEligibleWidth = 280.0
    public static let minimumEligibleHeight = 120.0
    public static func isEligibleSize(_ r: Rect) -> Bool {
        r.isValid && r.width >= minimumEligibleWidth && r.height >= minimumEligibleHeight
    }
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
    /// Height of the external header strip above the target window.
    public static let headerHeight = 30.0
    /// macOS 26 gives every standard window 16pt continuous-curve top corners (measured on 26.6 for AppKit and
    /// Electron windows alike). A rectangular header above such a window leaves a notch at each corner.
    public static let windowCornerRadius = 16.0
    /// A continuous curve leaves the straight edge about 1.53 x radius away from the corner, so the notch
    /// fill needs a band this tall below the header. Only the notch outside the curve is painted; the
    /// rest of the band stays fully transparent and therefore click-through.
    public static var cornerFillExtent: Double { (windowCornerRadius * 1.6).rounded(.up) }
    /// Never covers native controls, clamps onto content, or mutates the target.
    public static func externalHeader(for window: Rect, in visibleFrame: Rect,
                                      height: Double = headerHeight) -> Rect? {
        guard window.isValid, visibleFrame.isValid, height.isFinite, height > 0 else { return nil }
        let header = Rect(x: window.x, y: window.y - height, width: window.width, height: height)
        return visibleFrame.contains(header, tolerance: 0.5) ? header : nil
    }
    /// The panel that hosts a header: the header itself plus the corner-fill band that overlaps the
    /// target's rounded top corners. Everything in the band except the two notches is transparent.
    /// Callers keep using `externalHeader` for space checks; this larger frame is used for the panel
    /// and for the (more conservative) ordering safety check.
    public static func panelFrame(forHeader header: Rect, cornerExtent: Double = cornerFillExtent) -> Rect {
        guard cornerExtent.isFinite, cornerExtent > 0 else { return header }
        return Rect(x: header.x, y: header.y, width: header.width, height: header.height + cornerExtent)
    }
    /// Called ONLY after an explicit user command for ONE focused window.
    public static func reserveSpace(for window: Rect, in screen: Rect,
                                    headerHeight: Double = headerHeight, minimumHeight: Double = 160) -> Rect? {
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
