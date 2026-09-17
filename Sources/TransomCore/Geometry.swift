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
    /// The header panel runs on this far below the target's top edge, BEHIND the target (it is ordered
    /// directly under it). The window hides all of that band except what shows through its own rounded
    /// top corners, so the corners are filled whatever their radius (16pt on standard macOS 26 windows,
    /// about 30pt on Safari) without the app knowing it. 48pt covers a continuous curve of radius ~31pt
    /// (it leaves the edge about 1.53 x radius from the corner) and fits inside the smallest eligible
    /// window height, so nothing of the band can show below a window either.
    public static let cornerBackfill = 48.0
    /// Never covers native controls, clamps onto content, or mutates the target.
    /// The header needs its full height inside the usable screen area (never over the menu bar, never
    /// pushed onto the window). Sideways or downward overflow of the window past the screen edges is fine:
    /// the header follows the window and is simply cut off at the edge like the window itself, as long
    /// as some part of it remains on this screen.
    public static func externalHeader(for window: Rect, in visibleFrame: Rect,
                                      height: Double = headerHeight) -> Rect? {
        guard window.isValid, visibleFrame.isValid, height.isFinite, height > 0 else { return nil }
        let header = Rect(x: window.x, y: window.y - height, width: window.width, height: height)
        let fitsVertically = header.y >= visibleFrame.y - 0.5 && header.maxY <= visibleFrame.maxY + 0.5
        return fitsVertically && header.intersection(visibleFrame) != nil ? header : nil
    }
    /// The panel that hosts a header: the header itself plus the opaque backfill band below it. The band
    /// keeps the header's x and width (the target's own), so it can only ever show through the target's
    /// rounded corners, never beside the window. Callers keep using `externalHeader` for space checks.
    public static func panelFrame(forHeader header: Rect, backfill: Double = cornerBackfill) -> Rect {
        guard backfill.isFinite, backfill > 0 else { return header }
        return Rect(x: header.x, y: header.y, width: header.width, height: header.height + backfill)
    }
    /// Windows-style "maximize": the usable screen area minus the header's own height at the top, so the
    /// header stays visible above the window. Applied ONLY when the user presses the header's maximize
    /// button for that one window; pressing it again restores the frame recorded before.
    public static func maximizedFrame(in screen: Rect, headerHeight: Double = headerHeight) -> Rect? {
        guard screen.isValid, headerHeight > 0, screen.height > headerHeight + 160 else { return nil }
        return Rect(x: screen.x, y: screen.y + headerHeight, width: screen.width, height: screen.height - headerHeight)
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
    /// Windows are front-to-back. The header belongs directly BEHIND its target: the target hides the
    /// backfill band and leaves the bar above it visible. A header in front of its target would paint
    /// that band over the title bar, so it is rejected outright. A foreign window between the two that
    /// overlaps the header would cut the bar although the target is in front of it, so that is rejected
    /// too (and triggers a re-order). A missing ID is not assumed safe.
    public static func isDirectlyBehind(headerID: UInt32, targetID: UInt32, ownPID: Int32,
                                        headerFrame: Rect, frontToBack: [OrderedWindow]) -> Bool {
        guard let h = frontToBack.firstIndex(where: { $0.id == headerID }),
              let t = frontToBack.firstIndex(where: { $0.id == targetID }), t < h else { return false }
        return !frontToBack[(t + 1)..<h].contains {
            $0.pid != ownPID && $0.frame.intersection(headerFrame) != nil
        }
    }
}
