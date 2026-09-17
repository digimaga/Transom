import Foundation

public struct HeaderLayout: Sendable {
    public let app: Rect
    public let title: Rect
    public let menus: [Rect]
    public let overflow: Rect?
    public let visibleMenuCount: Int

    public static func make(width: Double, height: Double = Geometry.headerHeight,
                            appWidth: Double, menuWidths: [Double]) -> HeaderLayout {
        let width = max(0, width), gap = 4.0, inset = 5.0
        let appW = min(max(36, appWidth), max(0, width - 2 * inset - 32))
        let app = Rect(x: inset, y: 0, width: appW, height: height)
        let remaining = max(0, width - app.maxX - 2 * gap - inset)
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
        let used = menuWidths.prefix(count).reduce(0, +)
        let titleW = max(0, remaining - used - overflowWidth)
        let title = Rect(x: app.maxX + gap, y: 0, width: titleW, height: height)
        var x = title.maxX + gap
        let menus = menuWidths.prefix(count).map { w -> Rect in
            defer { x += w }
            return Rect(x: x, y: 0, width: w, height: height)
        }
        let overflow = overflowWidth > 0 ? Rect(x: x, y: 0, width: overflowWidth, height: height) : nil
        return HeaderLayout(app: app, title: title, menus: menus,
                            overflow: overflow, visibleMenuCount: count)
    }
}
