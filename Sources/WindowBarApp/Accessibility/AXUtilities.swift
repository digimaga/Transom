import Foundation
import ApplicationServices
import WindowBarBridge
import WindowBarCore

final class AXBudget {
    let deadline: TimeInterval
    init(seconds: TimeInterval) { deadline = ProcessInfo.processInfo.systemUptime + seconds }
    func check() throws {
        if ProcessInfo.processInfo.systemUptime > deadline { throw WindowBarError.deadline }
    }
}

enum AX {
    static let timeout: Float = 0.16
    static func configure(_ element: AXUIElement) { AXUIElementSetMessagingTimeout(element, timeout) }

    static func value(_ element: AXUIElement, _ name: String, budget: AXBudget? = nil) throws -> CFTypeRef? {
        try budget?.check()
        configure(element)
        var result: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name as CFString, &result)
        switch error {
        case .success: return result
        case .attributeUnsupported, .noValue: return nil
        default: throw WindowBarError.ax(error.rawValue)
        }
    }
    static func string(_ element: AXUIElement, _ name: String, budget: AXBudget? = nil) throws -> String? {
        try value(element, name, budget: budget) as? String
    }
    static func bool(_ element: AXUIElement, _ name: String, budget: AXBudget? = nil) throws -> Bool? {
        (try value(element, name, budget: budget) as? NSNumber)?.boolValue
    }
    static func element(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }
    static func elements(_ value: CFTypeRef?) -> [AXUIElement] {
        guard let array = value as? [AnyObject] else { return [] }
        return array.compactMap { element($0) }
    }
    static func children(_ element: AXUIElement, budget: AXBudget? = nil) throws -> [AXUIElement] {
        elements(try value(element, kAXChildrenAttribute, budget: budget))
    }
    static func windowID(_ element: AXUIElement) throws -> UInt32 {
        configure(element)
        var id: UInt32 = 0
        let error = WBCopyAXWindowID(element, &id)
        guard error == .success, id != 0 else { throw WindowBarError.unavailable("正確なウィンドウIDを取得できません。") }
        return id
    }
    static func point(_ value: CFTypeRef?) -> CGPoint? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeBitCast(value, to: AXValue.self)
        var point = CGPoint.zero
        guard AXValueGetType(axValue) == .cgPoint, AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }
    static func size(_ value: CFTypeRef?) -> CGSize? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeBitCast(value, to: AXValue.self)
        var size = CGSize.zero
        guard AXValueGetType(axValue) == .cgSize, AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }
    static func frame(_ element: AXUIElement) throws -> Rect {
        guard let p = point(try value(element, kAXPositionAttribute)),
              let s = size(try value(element, kAXSizeAttribute)) else { throw WindowBarError.stale }
        return Rect(x: Double(p.x), y: Double(p.y), width: Double(s.width), height: Double(s.height))
    }
    static func settable(_ element: AXUIElement, _ name: String) -> Bool {
        configure(element)
        var flag: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, name as CFString, &flag) == .success && flag.boolValue
    }
    static func set(_ element: AXUIElement, _ name: String, _ value: CFTypeRef) throws {
        configure(element)
        let error = AXUIElementSetAttributeValue(element, name as CFString, value)
        guard error == .success else { throw WindowBarError.ax(error.rawValue) }
    }
    static func setPosition(_ element: AXUIElement, _ p: Point) throws {
        var p = CGPoint(x: p.x, y: p.y)
        guard let value = AXValueCreate(.cgPoint, &p) else { throw WindowBarError.stale }
        try set(element, kAXPositionAttribute, value)
    }
    static func setSize(_ element: AXUIElement, _ rect: Rect) throws {
        var size = CGSize(width: rect.width, height: rect.height)
        guard let value = AXValueCreate(.cgSize, &size) else { throw WindowBarError.stale }
        try set(element, kAXSizeAttribute, value)
    }
    static func actions(_ element: AXUIElement, budget: AXBudget? = nil) throws -> [String] {
        try budget?.check()
        configure(element)
        var raw: CFArray?
        let error = AXUIElementCopyActionNames(element, &raw)
        guard error == .success else { throw WindowBarError.ax(error.rawValue) }
        return raw as? [String] ?? []
    }
    static func equal(_ a: CFTypeRef?, _ b: CFTypeRef?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case (let a?, let b?): return CFEqual(a, b)
        default: return false
        }
    }
    static func focusedPID() throws -> Int32? {
        let system = AXUIElementCreateSystemWide()
        guard let application = element(try value(system, kAXFocusedApplicationAttribute)) else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(application, &pid) == .success else { return nil }
        return pid
    }
    static func batch(_ element: AXUIElement, attributes: [String], budget: AXBudget) throws -> [String: AnyObject] {
        try budget.check()
        configure(element)
        var raw: CFArray?
        let error = AXUIElementCopyMultipleAttributeValues(element, attributes as CFArray, [], &raw)
        guard error == .success, let values = raw as? [AnyObject], values.count == attributes.count else {
            throw WindowBarError.ax(error.rawValue)
        }
        return Dictionary(uniqueKeysWithValues: zip(attributes, values))
    }
}
