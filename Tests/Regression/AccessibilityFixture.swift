import AppKit
import ApplicationServices
import Foundation
import TransomCore

final class AXBudget {
    let deadline: TimeInterval
    init(seconds: TimeInterval) { deadline = ProcessInfo.processInfo.systemUptime + seconds }
    func check() throws {
        if ProcessInfo.processInfo.systemUptime >= deadline { throw TransomError.deadline }
    }
}

final class AXFixtureNode {
    let reference: AXUIElement
    var windowID: UInt32?
    var fields: [String: AnyObject] = [:]
    var children: [AXUIElement] = []
    var actions: [String] = []
    var settable: Set<String> = []
    var hasSheet = false
    var failBatch = false

    init(reference: AXUIElement, windowID: UInt32? = nil) {
        self.reference = reference
        self.windowID = windowID
    }
}

enum AXFixture {
    static let pid: Int32 = 981234
    static var nextPID: Int32 = pid + 1
    static var nodes: [AXFixtureNode] = []
    static var frontmostPID: Int32? = pid
    static var reads: [String] = []
    static var writes: [String] = []
    static var readHook: ((String) -> Void)?
    static var actionResult: AXError = .success
    static var listFails = false
    static var frameValue = Rect(x: 100, y: 100, width: 400, height: 300)
    static var acceptedFrame: Rect?
    static var acceptedAfterWrite: Int?
    static var serverPID: Int32 = pid
    static var describedIDs: [[UInt32]] = []
    static var flushCount = 0

    static func reset() {
        nextPID = pid + 1
        nodes = []
        frontmostPID = pid
        reads = []
        writes = []
        readHook = nil
        actionResult = .success
        listFails = false
        frameValue = Rect(x: 100, y: 100, width: 400, height: 300)
        acceptedFrame = nil
        acceptedAfterWrite = nil
        serverPID = pid
        describedIDs = []
        flushCount = 0
    }
    static func make(windowID: UInt32? = nil) -> AXFixtureNode {
        let result = AXFixtureNode(reference: AXUIElementCreateApplication(nextPID), windowID: windowID)
        nextPID += 1
        nodes.append(result)
        return result
    }
    static func application() -> AXFixtureNode {
        let result = AXFixtureNode(reference: AXUIElementCreateApplication(pid))
        nodes.append(result)
        return result
    }
    static func node(_ reference: AXUIElement) -> AXFixtureNode {
        guard let result = nodes.first(where: { CFEqual($0.reference, reference) }) else {
            fatalError("Unknown fixture AX reference")
        }
        return result
    }
    static func read(_ key: String) {
        reads.append(key)
        readHook?(key)
    }
    static func performAction(_ element: AXUIElement, _ action: CFString) -> AXError {
        writes.append("action:\(node(element).windowID.map(String.init) ?? "node"):\(action)")
        return actionResult
    }
    static func forbiddenObserverCall(_ observer: AXObserver, _ element: AXUIElement,
                                      _ name: CFString, _ context: UnsafeMutableRawPointer? = nil) -> AXError {
        fatalError("Observer IPC is outside fixture scope")
    }
    static func acceptFrameIfConfigured() {
        let frameWrites = writes.filter { $0 == "position" || $0 == "size" }.count
        if let acceptedAfterWrite, frameWrites == acceptedAfterWrite,
           let acceptedFrame { frameValue = acceptedFrame }
    }
}

enum AX {
    static func configure(_ element: AXUIElement) {}
    static func windowID(_ element: AXUIElement) throws -> UInt32 {
        AXFixture.read("windowID")
        guard let windowID = AXFixture.node(element).windowID else { throw TransomError.stale }
        return windowID
    }
    static func value(_ element: AXUIElement, _ name: String, budget: AXBudget? = nil) throws -> CFTypeRef? {
        try budget?.check()
        AXFixture.read("value:\(name)")
        if name == kAXWindowsAttribute && AXFixture.listFails { throw TransomError.ax(AXError.cannotComplete.rawValue) }
        return AXFixture.node(element).fields[name]
    }
    static func element(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }
    static func elements(_ value: CFTypeRef?) -> [AXUIElement] {
        guard let value, CFGetTypeID(value) == CFArrayGetTypeID() else { return [] }
        return (value as? [AXUIElement]) ?? []
    }
    static func point(_ value: AnyObject?) -> CGPoint? {
        (value as? NSValue)?.pointValue
    }
    static func size(_ value: AnyObject?) -> CGSize? {
        (value as? NSValue)?.sizeValue
    }
    static func batch(_ element: AXUIElement, attributes: [String], budget: AXBudget) throws -> [String: AnyObject] {
        try budget.check()
        AXFixture.read("batch")
        let target = AXFixture.node(element)
        if target.failBatch { throw TransomError.ax(AXError.cannotComplete.rawValue) }
        return target.fields.filter { attributes.contains($0.key) }
    }
    static func focusedPID() throws -> Int32? {
        AXFixture.read("focusedPID")
        return AXFixture.frontmostPID
    }
    static func string(_ element: AXUIElement, _ name: String, budget: AXBudget? = nil) throws -> String? {
        try budget?.check()
        AXFixture.read("string:\(name)")
        return AXFixture.node(element).fields[name] as? String
    }
    static func bool(_ element: AXUIElement, _ name: String, budget: AXBudget? = nil) throws -> Bool? {
        try budget?.check()
        AXFixture.read("bool:\(name)")
        return (AXFixture.node(element).fields[name] as? NSNumber)?.boolValue
    }
    static func hasSheet(_ element: AXUIElement, budget: AXBudget? = nil) throws -> Bool {
        try budget?.check()
        AXFixture.read("hasSheet")
        return AXFixture.node(element).hasSheet
    }
    static func settable(_ element: AXUIElement, _ name: String) -> Bool {
        AXFixture.read("settable:\(name)")
        return AXFixture.node(element).settable.contains(name)
    }
    static func set(_ element: AXUIElement, _ name: String, _ value: CFTypeRef) throws {
        AXFixture.writes.append("set:\(name)")
    }
    static func setPosition(_ element: AXUIElement, _ point: Point) throws {
        AXFixture.writes.append("position")
        AXFixture.frameValue.x = point.x
        AXFixture.frameValue.y = point.y
        AXFixture.acceptFrameIfConfigured()
    }
    static func setSize(_ element: AXUIElement, _ rect: Rect) throws {
        AXFixture.writes.append("size")
        AXFixture.frameValue.width = rect.width
        AXFixture.frameValue.height = rect.height
        AXFixture.acceptFrameIfConfigured()
    }
    static func frame(_ element: AXUIElement) throws -> Rect {
        AXFixture.read("frame")
        return AXFixture.frameValue
    }
    static func actions(_ element: AXUIElement, budget: AXBudget? = nil) throws -> [String] {
        try budget?.check()
        AXFixture.read("actions")
        return AXFixture.node(element).actions
    }
    static func children(_ element: AXUIElement, budget: AXBudget? = nil) throws -> [AXUIElement] {
        try budget?.check()
        AXFixture.read("children")
        return AXFixture.node(element).children
    }
    static func equal(_ first: CFTypeRef?, _ second: CFTypeRef?) -> Bool {
        switch (first, second) {
        case (nil, nil): return true
        case let (first?, second?): return CFEqual(first, second)
        default: return false
        }
    }
}

enum WindowServer {
    struct Description { let pid: Int32; let frame: Rect }
    static func flushPendingTransaction() { AXFixture.flushCount += 1 }
    static func describe(_ ids: [UInt32]) -> [Description] {
        AXFixture.describedIDs.append(ids)
        guard ids.contains(777) else { return [] }
        return [Description(pid: AXFixture.serverPID, frame: AXFixture.frameValue)]
    }
}
