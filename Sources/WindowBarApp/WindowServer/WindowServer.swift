import AppKit
import CoreGraphics
import OSLog
import QuartzCore
import WindowBarBridge
import WindowBarCore

struct ServerWindow {
    let id: UInt32
    let pid: Int32
    let layer: Int
    let alpha: Double
    let frame: Rect

    init(id: UInt32, pid: Int32, layer: Int, alpha: Double, frame: Rect) {
        self.id = id; self.pid = pid; self.layer = layer; self.alpha = alpha; self.frame = frame
    }
    /// One row of a CGWindowList description. Only metadata keys are read: never kCGWindowName.
    init?(row: [String: Any]) {
        guard let id = row[kCGWindowNumber as String] as? NSNumber,
              let pid = row[kCGWindowOwnerPID as String] as? NSNumber,
              let layer = row[kCGWindowLayer as String] as? NSNumber,
              let bounds = row[kCGWindowBounds as String] as? [String: Any],
              let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
              let number = UInt32(exactly: id.uint64Value) else { return nil }
        self.id = number
        self.pid = pid.int32Value
        self.layer = layer.intValue
        self.alpha = (row[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
        self.frame = Rect(frame)
    }
}
struct ServerSnapshot {
    let windows: [ServerWindow] // ordered front-to-back, including our own transparent probe panels
    let readAt: TimeInterval
    var byID: [UInt32: ServerWindow] {
        Dictionary(windows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
    var ordering: [OrderedWindow] { windows.map { OrderedWindow(id: $0.id, pid: $0.pid, frame: $0.frame) } }
}

/// Reads metadata only: never requests pixels, kCGWindowName, or Screen Recording.
///
/// Every CGWindowList query first synchronizes with this connection's last CoreAnimation/SkyLight
/// transaction (the previous header move or re-order), holding the connection lock while it waits. Run
/// from a background queue, that wait and the main thread's next commit (which needs the same lock) block
/// each other until a 0.5 s timeout: observed on macOS 26.6 as a header and its window freezing for half a
/// second at the end of a drag. So the reads are done on the main thread, right after flushing the pending
/// transaction, where the synchronization is immediate. A full read costs about a millisecond.
@MainActor
final class WindowServer {
    let privateOrdering = WBHasRelativeOrdering()
    let exactIdentity = WBHasAXWindowID()
    /// Diagnostics only (no window content): last private-path step code, its raw CGError, and failure count.
    private(set) var lastPrivateOrderCode: Int32 = 0
    private(set) var lastPrivateCGError: Int32 = 0
    private(set) var privateOrderFailures = 0
    /// After repeated private-path failures we stop calling it and rely on the public path only.
    /// This avoids per-frame syscalls and log spam on OS versions where the SkyLight ABI differs.
    private(set) var privateOrderingDisabled = false
    private let privateFailureLimit = 3
    private static let logger = Logger(subsystem: "dev.local.WindowBar", category: "metadata")

    /// Front-to-back on-screen windows. `own`: this process's window numbers (the header panels) and pid.
    /// They keep their place in the ordering but are not described: their frames are known locally.
    func read(own: (pid: Int32, windows: Set<UInt32>)) -> ServerSnapshot? {
        precondition(Thread.isMainThread)
        let started = ProcessInfo.processInfo.systemUptime
        WindowServer.flushPendingTransaction()
        guard let list = WBCopyOnScreenWindowIDs()?.takeRetainedValue() else { return nil }
        var ordered: [UInt32] = []
        for index in 0..<CFArrayGetCount(list) {
            ordered.append(UInt32(truncatingIfNeeded: UInt(bitPattern: CFArrayGetValueAtIndex(list, index))))
        }
        let foreign = ordered.filter { !own.windows.contains($0) }
        let described = Dictionary(WindowServer.describe(foreign).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var windows: [ServerWindow] = []
        var seen = Set<UInt32>()
        for id in ordered where seen.insert(id).inserted {
            if own.windows.contains(id) {
                windows.append(ServerWindow(id: id, pid: own.pid, layer: 0, alpha: 1, frame: Rect(x: 0, y: 0, width: 0, height: 0)))
            } else if let window = described[id] {
                windows.append(window)
            }
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        if elapsed > 0.02 {
            WindowServer.logger.debug("on-screen metadata read took \(elapsed * 1000, format: .fixed(precision: 1), privacy: .public) ms")
        }
        return ServerSnapshot(windows: windows, readAt: ProcessInfo.processInfo.systemUptime)
    }
    /// Commits the implicit CoreAnimation transaction now, so that a window-list query that follows does
    /// not wait for the end of the run-loop iteration (or, from another thread, for the lock this commit
    /// itself needs). Cheap when nothing is pending.
    static func flushPendingTransaction() { CATransaction.flush() }
    /// Descriptions of exactly these windows (metadata only). A window that no longer exists is absent.
    /// Main thread only, after `flushPendingTransaction`, for the reason given on the class.
    static func describe(_ ids: [UInt32]) -> [ServerWindow] {
        // CGWindowListCreateDescriptionFromArray takes the raw window IDs as the CFArray values.
        var pointers: [UnsafeRawPointer?] = ids.map { UnsafeRawPointer(bitPattern: UInt($0)) }
        guard let array = CFArrayCreate(nil, &pointers, pointers.count, nil),
              let rows = CGWindowListCreateDescriptionFromArray(array) as? [[String: Any]] else { return [] }
        return rows.compactMap(ServerWindow.init(row:))
    }
    /// Relative public ordering is tried first; the private transaction aligns sublevel when available.
    /// Both paths remain subject to the independent metadata ordering check before opacity is restored.
    /// Returns true if this call was the one that disabled the private path (for a single log line).
    @discardableResult
    func order(_ panel: NSPanel, above target: UInt32) -> Bool {
        precondition(Thread.isMainThread)
        panel.level = .normal
        panel.order(.above, relativeTo: Int(target))
        guard panel.windowNumber > 0, let number = UInt32(exactly: panel.windowNumber) else { return false }
        if privateOrdering && !privateOrderingDisabled {
            let code = WBOrderAboveWindow(number, target)
            lastPrivateOrderCode = code
            if code == 0 {
                privateOrderFailures = 0
            } else {
                lastPrivateCGError = WBLastOrderCGError()
                privateOrderFailures += 1
                // Stop retrying (and stop spamming) once the ABI is shown to be unusable here.
                // The public relative order stays in effect; OrderingPolicy.isSafe remains the gate.
                if privateOrderFailures >= privateFailureLimit { privateOrderingDisabled = true }
            }
        }
        return true
    }
}
