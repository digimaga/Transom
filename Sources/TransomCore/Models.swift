import Foundation

/// An ID is only valid for one process instance and one observed window lifetime.
public struct WindowToken: Hashable, Codable, Sendable {
    public let processInstance: UUID
    public let pid: Int32
    public let windowID: UInt32
    public let incarnation: UInt64

    public init(processInstance: UUID, pid: Int32, windowID: UInt32, incarnation: UInt64) {
        self.processInstance = processInstance
        self.pid = pid
        self.windowID = windowID
        self.incarnation = incarnation
    }
}

public struct Point: Equatable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// Global logical points, origin at the upper-left of the primary display.
public struct Rect: Equatable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var area: Double { max(0, width) * max(0, height) }
    public var isValid: Bool {
        [x, y, width, height].allSatisfy(\.isFinite) && width > 0 && height > 0
    }
    public func contains(_ other: Rect, tolerance: Double = 0) -> Bool {
        other.x >= x - tolerance && other.y >= y - tolerance &&
        other.maxX <= maxX + tolerance && other.maxY <= maxY + tolerance
    }
    public func intersection(_ other: Rect) -> Rect? {
        let left = max(x, other.x), top = max(y, other.y)
        let right = min(maxX, other.maxX), bottom = min(maxY, other.maxY)
        guard right > left, bottom > top else { return nil }
        return Rect(x: left, y: top, width: right - left, height: bottom - top)
    }
    public func approximatelyEquals(_ other: Rect, tolerance: Double = 1) -> Bool {
        abs(x - other.x) <= tolerance && abs(y - other.y) <= tolerance &&
        abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}

public struct MenuHeading: Hashable, Sendable {
    /// Index in the unfiltered AXMenuBar AXChildren, not the visible button index.
    public let index: Int
    public let title: String
    public init(index: Int, title: String) { self.index = index; self.title = title }
}

public struct MenuEntry: Sendable {
    public let commandID: UUID?
    public let title: String
    public let enabled: Bool
    public let mark: String
    public let shortcut: String
    public let isSeparator: Bool
    public let children: [MenuEntry]
    public init(commandID: UUID? = nil, title: String, enabled: Bool = false,
                mark: String = "", shortcut: String = "", isSeparator: Bool = false,
                children: [MenuEntry] = []) {
        self.commandID = commandID; self.title = title; self.enabled = enabled
        self.mark = mark; self.shortcut = shortcut; self.isSeparator = isSeparator
        self.children = children
    }
    public static func notice(_ text: String) -> MenuEntry { MenuEntry(title: text) }
}

public struct PreparedMenu: Sendable {
    public let sessionID: UUID
    public let target: WindowToken
    public let entries: [MenuEntry]
    public let truncated: Bool
    public init(sessionID: UUID, target: WindowToken, entries: [MenuEntry], truncated: Bool) {
        self.sessionID = sessionID; self.target = target
        self.entries = entries; self.truncated = truncated
    }
}
