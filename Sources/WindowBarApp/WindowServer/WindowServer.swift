import AppKit
import CoreGraphics
import WindowBarBridge
import WindowBarCore

struct ServerWindow {
    let id: UInt32
    let pid: Int32
    let layer: Int
    let alpha: Double
    let frame: Rect
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
@MainActor
final class WindowServer {
    private let queue = DispatchQueue(label: "WindowBar.WindowMetadata", qos: .userInteractive)
    private var busy = false
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

    func read(completion: @escaping (ServerSnapshot?) -> Void) {
        precondition(Thread.isMainThread)
        guard !busy else { return }
        busy = true
        queue.async {
            let snapshot: ServerSnapshot?
            if let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
                let windows = raw.compactMap { row -> ServerWindow? in
                    guard let id = row[kCGWindowNumber as String] as? NSNumber,
                          let pid = row[kCGWindowOwnerPID as String] as? NSNumber,
                          let layer = row[kCGWindowLayer as String] as? NSNumber,
                          let bounds = row[kCGWindowBounds as String] as? [String: Any],
                          let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                          let number = UInt32(exactly: id.uint64Value) else { return nil }
                    return ServerWindow(id: number, pid: pid.int32Value, layer: layer.intValue,
                        alpha: (row[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1,
                        frame: Rect(frame))
                }
                snapshot = ServerSnapshot(windows: windows, readAt: ProcessInfo.processInfo.systemUptime)
            } else { snapshot = nil }
            DispatchQueue.main.async { self.busy = false; completion(snapshot) }
        }
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
