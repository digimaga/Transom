import Foundation
import ApplicationServices

/// AX callbacks only schedule work. No tree traversal or UI mutation in the callback.
@MainActor
final class AXObserverHub {
    static let shared = AXObserverHub()
    var onChange: ((Int32) -> Void)?
    private var observers: [Int32: AXObserver] = [:]

    func add(pid: Int32) -> AXObserver? {
        precondition(Thread.isMainThread)
        if let existing = observers[pid] { return existing }
        var observer: AXObserver?
        let error = AXObserverCreate(pid, { _, element, _, _ in
            var pid: pid_t = 0
            guard AXUIElementGetPid(element, &pid) == .success else { return }
            // The observer source lives on the main run loop, so this callback is already on the main
            // thread. Call through directly: a DispatchQueue.main hop would stall during NSMenu tracking.
            MainActor.assumeIsolated { AXObserverHub.shared.onChange?(pid) }
        }, &observer)
        guard error == .success, let observer else { return nil }
        observers[pid] = observer
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        return observer
    }
    func remove(pid: Int32) {
        precondition(Thread.isMainThread)
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }
    func removeAll() { for pid in Array(observers.keys) { remove(pid: pid) } }
}
