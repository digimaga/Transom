import AppKit
import Foundation
import ApplicationServices
import OSLog
import WindowBarCore

/// Owns every AXUIElement and menu command reference for one process instance.
/// Only value snapshots cross to the main queue. Never execute synchronous AX IPC in AppKit callbacks.
final class AXAppWorker {
    struct Record {
        let token: WindowToken
        let element: AXUIElement
        var snapshot: WindowSnapshot
    }
    let descriptor: ApplicationDescriptor
    let queue: DispatchQueue
    let lifetime = OperationPermit(lifetime: .greatestFiniteMagnitude)
    let application: AXUIElement
    private var observer: AXObserver?
    var records: [UInt32: Record] = [:]
    private var nextIncarnation: UInt64 = 0
    private var presence = PresenceTracker()
    private var headings: [MenuHeading] = []
    private var headingsReadAt: TimeInterval = 0
    var menus: [UUID: AXMenuSession] = [:]

    init(descriptor: ApplicationDescriptor) {
        self.descriptor = descriptor
        queue = DispatchQueue(label: "WindowBar.AX.\(descriptor.pid).\(descriptor.instance.uuidString)", qos: .userInitiated)
        application = AXUIElementCreateApplication(descriptor.pid)
    }
    func stop() { lifetime.cancel() }

    func submit<T>(_ body: @escaping (AXAppWorker) throws -> T, completion: @escaping @MainActor (Result<T, Error>) -> Void) {
        queue.async {
            let result = Result { () throws -> T in
                guard self.lifetime.isValid() else { throw WindowBarError.cancelled }
                return try body(self)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }
    func installObserver(_ observer: AXObserver) {
        queue.async {
            guard self.lifetime.isValid() else { return }
            self.observer = observer
            AX.configure(self.application)
            for name in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification,
                         kAXMainWindowChangedNotification, kAXMenuOpenedNotification, kAXMenuClosedNotification] {
                AXObserverAddNotification(observer, self.application, name as CFString, nil)
            }
        }
    }
    private func observeWindow(_ element: AXUIElement) {
        guard let observer else { return }
        for name in [kAXMovedNotification, kAXResizedNotification, kAXTitleChangedNotification,
                     kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification,
                     kAXWindowDeminiaturizedNotification] {
            AXObserverAddNotification(observer, element, name as CFString, nil)
        }
    }
    private func unobserveWindow(_ element: AXUIElement) {
        guard let observer else { return }
        for name in [kAXMovedNotification, kAXResizedNotification, kAXTitleChangedNotification,
                     kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification,
                     kAXWindowDeminiaturizedNotification] {
            AXObserverRemoveNotification(observer, element, name as CFString)
        }
    }
    func scan(completion: @escaping @MainActor (Result<ApplicationScan, Error>) -> Void) {
        submit({ try $0.scanNow() }, completion: completion)
    }
    private func scanNow() throws -> ApplicationScan {
        let budget = AXBudget(seconds: 0.85)
        // A successful list read is distinguished from unavailable/timeout, including an empty list.
        guard let raw = try AX.value(application, kAXWindowsAttribute, budget: budget),
              CFGetTypeID(raw) == CFArrayGetTypeID() else {
            throw WindowBarError.unavailable("ウィンドウ一覧を読み取れません。")
        }
        let elements = AX.elements(raw)
        let focused = try? AX.element(AX.value(application, kAXFocusedWindowAttribute, budget: budget))
        let focusedID = focused.flatMap { try? AX.windowID($0) }
        let now = ProcessInfo.processInfo.systemUptime
        if headings.isEmpty || now - headingsReadAt > 15 {
            if let fresh = try? readHeadings(budget: budget) { headings = fresh; headingsReadAt = now }
        }
        var seen = Set<WindowToken>()
        var hidden = Set<WindowToken>()
        var complete = true
        let attributes = [kAXTitleAttribute, kAXRoleAttribute, kAXSubroleAttribute,
                          kAXPositionAttribute, kAXSizeAttribute, kAXMinimizedAttribute,
                          "AXFullScreen", "AXModal", "AXSheets"]
        // Read known focused windows first, improving responsiveness when another window is slow.
        let ordered = elements.sorted { a, b in
            let aFocused = focused.map { CFEqual(a, $0) } ?? false
            let bFocused = focused.map { CFEqual(b, $0) } ?? false
            return aFocused && !bFocused
        }
        for element in ordered {
            do {
                try budget.check()
                let id = try AX.windowID(element)
                let values = try AX.batch(element, attributes: attributes, budget: budget)
                guard let position = AX.point(values[kAXPositionAttribute]),
                      let size = AX.size(values[kAXSizeAttribute]) else { complete = false; continue }
                let old = records[id]
                let token: WindowToken
                if let old, CFEqual(old.element, element) { token = old.token }
                else {
                    if let old { unobserveWindow(old.element) }
                    nextIncarnation &+= 1
                    token = WindowToken(processInstance: descriptor.instance, pid: descriptor.pid,
                                        windowID: id, incarnation: nextIncarnation)
                    observeWindow(element)
                }
                let title = values[kAXTitleAttribute] as? String ?? ""
                let frame = Rect(x: Double(position.x), y: Double(position.y),
                                 width: Double(size.width), height: Double(size.height))
                let modal = (values["AXModal"] as? NSNumber)?.boolValue ?? false
                let hasSheets = !(values["AXSheets"] as? [AnyObject] ?? []).isEmpty
                let standard = (values[kAXRoleAttribute] as? String) == kAXWindowRole &&
                               (values[kAXSubroleAttribute] as? String) == kAXStandardWindowSubrole
                let snapshot = WindowSnapshot(token: token, appName: descriptor.name,
                    bundleIdentifier: descriptor.bundleIdentifier, title: title, frame: frame,
                    focused: focusedID == id,
                    minimized: (values[kAXMinimizedAttribute] as? NSNumber)?.boolValue ?? false,
                    fullscreen: (values["AXFullScreen"] as? NSNumber)?.boolValue ?? false,
                    modal: modal || hasSheets,
                    eligible: standard && frame.isValid && frame.width >= 280 && frame.height >= 120,
                    headings: headings, observedAt: ProcessInfo.processInfo.systemUptime)
                records[id] = Record(token: token, element: element, snapshot: snapshot)
                seen.insert(token)
            } catch {
                complete = false
                // Do not erase records because a single app/window failed to answer.
                if ProcessInfo.processInfo.systemUptime >= budget.deadline { break }
            }
        }
        let known = Set(records.values.map(\.token))
        let changes = presence.reconcile(known: known, observed: complete ? seen : nil)
        hidden.formUnion(changes.hidden)
        // On partial scans, freshly refreshed windows can still be shown.
        if !complete { hidden.subtract(seen) }
        for token in changes.removed {
            if let old = records.removeValue(forKey: token.windowID) { unobserveWindow(old.element) }
        }
        menus = menus.filter { $0.value.permit.isValid() }
        return ApplicationScan(instance: descriptor.instance, windows: records.values.map(\.snapshot),
                               hidden: hidden, complete: complete)
    }

    func exactRecord(_ token: WindowToken) throws -> Record {
        guard lifetime.isValid(), token.processInstance == descriptor.instance,
              let record = records[token.windowID], record.token == token,
              try AX.windowID(record.element) == token.windowID else { throw WindowBarError.stale }
        return record
    }
    /// Diagnostics only: the last reason validateFocus failed (a fixed code, never a title/URL).
    private(set) var lastFocusMismatch = ""
    static let focusLogger = Logger(subsystem: "dev.local.WindowBar", category: "focus")

    /// Frontmost process as seen by the system-wide AX element. Chromium/Electron apps (e.g. Claude, Chrome)
    /// can leave AXFocusedApplication unanswered (nil) while frontmost; ONLY in that no-answer case the
    /// workspace's notion of the frontmost app is used. A different pid from AX is still a mismatch.
    func frontmostPID() throws -> Int32? {
        if let pid = try AX.focusedPID() { return pid }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    func validateFocus(_ token: WindowToken) throws -> Record {
        let record = try exactRecord(token)
        do {
            let reason: String?
            let focused = AX.element(try AX.value(application, kAXFocusedWindowAttribute))
            // The exact-window checks below stay in force regardless of how the frontmost pid was obtained.
            let focusedPID = try frontmostPID()
            if focusedPID != token.pid { reason = "frontmost-pid(observed=\(focusedPID.map(String.init) ?? "nil"))" }
            else if focused == nil || !CFEqual(focused!, record.element) { reason = "focused-window" }
            else if try AX.windowID(focused!) != token.windowID { reason = "window-id" }
            else if try AX.string(record.element, kAXRoleAttribute) != kAXWindowRole { reason = "role" }
            else if try AX.string(record.element, kAXSubroleAttribute) != kAXStandardWindowSubrole { reason = "subrole" }
            else if try AX.bool(record.element, kAXMinimizedAttribute) == true { reason = "minimized" }
            else if try AX.bool(record.element, "AXFullScreen") == true { reason = "fullscreen" }
            else if try AX.bool(record.element, "AXModal") == true { reason = "modal" }
            else if !AX.elements(try AX.value(record.element, "AXSheets")).isEmpty { reason = "sheets" }
            else { reason = nil }
            if let reason { lastFocusMismatch = reason; throw WindowBarError.focusMismatch }
        } catch let error as WindowBarError {
            if case .ax(let code) = error { lastFocusMismatch = "ax-error(\(code))" }
            throw error
        }
        return record
    }
    /// Activation of the application is requested by the main queue as best effort only.
    /// macOS 14+ cooperative activation can refuse NSRunningApplication.activate() for a
    /// non-active accessory app, so the accessibility-backed frontmost request is made here.
    func focus(_ token: WindowToken, permit: OperationPermit,
               completion: @escaping @MainActor (Result<Void, Error>) -> Void) {
        submit({ worker in
            guard permit.isValid() else { throw WindowBarError.cancelled }
            let record = try worker.exactRecord(token)
            AX.configure(record.element)
            // AX IPC only on this per-app worker queue, never on MainActor.
            // A refusal here is not fatal: validateFocus below remains the only gate.
            if AX.settable(worker.application, kAXFrontmostAttribute) {
                try? AX.set(worker.application, kAXFrontmostAttribute, kCFBooleanTrue as CFTypeRef)
            }
            let error = AXUIElementPerformAction(record.element, kAXRaiseAction as CFString)
            guard error == .success else { throw WindowBarError.ax(error.rawValue) }
            if AX.settable(worker.application, kAXFocusedWindowAttribute) {
                try AX.set(worker.application, kAXFocusedWindowAttribute, record.element)
            }
            let deadline = ProcessInfo.processInfo.systemUptime + 0.6
            repeat {
                guard permit.isValid(), worker.lifetime.isValid() else { throw WindowBarError.cancelled }
                if (try? worker.validateFocus(token)) != nil { return }
                Thread.sleep(forTimeInterval: 0.025) // worker only; bounded, no MainActor blocking
            } while ProcessInfo.processInfo.systemUptime < deadline
            // Reason code only (frontmost-pid / focused-window / subrole / ax-error(n) ...). No titles or URLs.
            AXAppWorker.focusLogger.info("フォーカス検証が0.6秒以内に通りませんでした。最終理由コード: \(worker.lastFocusMismatch, privacy: .public)")
            throw WindowBarError.focusMismatch
        }, completion: completion)
    }
    func move(_ token: WindowToken, to point: Point, permit: OperationPermit,
              completion: @escaping @MainActor (Result<Rect, Error>) -> Void) {
        submit({ worker in
            let record = try worker.validateFocus(token)
            guard permit.isValid(), worker.lifetime.isValid(), point.x.isFinite, point.y.isFinite,
                  AX.settable(record.element, kAXPositionAttribute) else { throw WindowBarError.cancelled }
            try AX.setPosition(record.element, point)
            return try AX.frame(record.element)
        }, completion: completion)
    }
    func reserve(_ token: WindowToken, expected: Rect, desired: Rect, permit: OperationPermit,
                 completion: @escaping @MainActor (Result<Rect, Error>) -> Void) {
        submit({ worker in
            let record = try worker.validateFocus(token)
            guard permit.isValid(), worker.lifetime.isValid(), desired.isValid,
                  try AX.frame(record.element).approximatelyEquals(expected, tolerance: 2),
                  AX.settable(record.element, kAXPositionAttribute) else { throw WindowBarError.stale }
            let sizeChanges = abs(expected.height - desired.height) > 0.5 || abs(expected.width - desired.width) > 0.5
            if sizeChanges {
                guard AX.settable(record.element, kAXSizeAttribute) else {
                    throw WindowBarError.unavailable("このウィンドウはサイズを変更できません。")
                }
                try AX.setSize(record.element, desired)
            }
            // Position + size is not atomic. Do not silently rollback over later user changes.
            guard permit.isValid(), worker.lifetime.isValid() else { throw WindowBarError.cancelled }
            try AX.setPosition(record.element, Point(x: desired.x, y: desired.y))
            let actual = try AX.frame(record.element)
            guard actual.approximatelyEquals(desired, tolerance: 2) else {
                throw WindowBarError.unavailable("アプリが配置を補正しました。実際の配置を確認してください。")
            }
            return actual
        }, completion: completion)
    }
}
