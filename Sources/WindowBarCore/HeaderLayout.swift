import Foundation

public struct HeaderLayout: Sendable {
    public let app: Rect
    public let title: Rect
    public let menus: [Rect]
    public let overflow: Rect?
    public let visibleMenuCount: Int
    /// Windows-style window controls at the right edge: minimize, maximize, close (in that order).
    public let controls: [Rect]

    /// Width of one window-control button; three of them sit flush at the right edge.
    public static let controlWidth = 40.0
    public static let controlCount = 3

    public static func make(width: Double, height: Double = Geometry.headerHeight,
                            appWidth: Double, menuWidths: [Double]) -> HeaderLayout {
        let width = max(0, width), gap = 4.0, inset = 5.0
        let controlsWidth = controlWidth * Double(controlCount)
        let controls = (0..<controlCount).map { index in
            Rect(x: width - controlsWidth + Double(index) * controlWidth, y: 0, width: controlWidth, height: height)
        }
        let appW = min(max(36, appWidth), max(0, width - controlsWidth - 2 * inset - 32))
        let app = Rect(x: inset, y: 0, width: appW, height: height)
        let remaining = max(0, width - controlsWidth - app.maxX - 2 * gap - inset)
        let titleMinimum = min(64.0, max(0, remaining - (menuWidths.isEmpty ? 0 : 28)))
        let allWidth = menuWidths.reduce(0, +)
        var count = menuWidths.count
        var overflowWidth = 0.0
        if allWidth > remaining - titleMinimum {
            overflowWidth = min(28, remaining)
            count = 0
            var used = 0.0
            for menuWidth in menuWidths {
                if used + menuWidth > remaining - titleMinimum - overflowWidth { break }
                used += menuWidth
                count += 1
            }
        }
        // Left to right: app button, the menu headings (and the overflow button) directly after it, then
        // the document title, which takes whatever width is left. Menus stay left-aligned like a menu bar.
        var x = app.maxX + gap
        let menus = menuWidths.prefix(count).map { w -> Rect in
            defer { x += w }
            return Rect(x: x, y: 0, width: w, height: height)
        }
        let overflow = overflowWidth > 0 ? Rect(x: x, y: 0, width: overflowWidth, height: height) : nil
        if let overflow { x = overflow.maxX }
        let titleX = count > 0 || overflow != nil ? x + gap : x
        let title = Rect(x: titleX, y: 0, width: max(0, width - controlsWidth - inset - titleX), height: height)
        return HeaderLayout(app: app, title: title, menus: menus,
                            overflow: overflow, visibleMenuCount: count, controls: controls)
    }
}
