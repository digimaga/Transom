import Foundation

/// Revocation crosses the main/UI queue and an AX worker queue synchronously.
/// Cancelling a Swift Task alone cannot stop a synchronous AX message already sent.
public final class OperationPermit: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var committed = false
    private let expiresAt: TimeInterval

    public init(lifetime: TimeInterval = 30, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        expiresAt = now + lifetime
    }
    public func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    public func isValid(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return !cancelled && !committed && now <= expiresAt
    }
    /// A non-idempotent action is issued at most once, INCLUDING after a timeout.
    public func commitOnce(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled && !committed && now <= expiresAt else { return false }
        committed = true
        return true
    }
}

public struct ContextStamp: Equatable, Sendable {
    public let token: WindowToken
    public let title: String
    public let document: String?
    public init(token: WindowToken, title: String, document: String?) {
        self.token = token; self.title = title; self.document = document
    }
}

public enum FocusPolicy {
    public static func permits(expected: ContextStamp, current: ContextStamp,
                               frontmostPID: Int32?, isModal: Bool, isMinimized: Bool) -> Bool {
        expected == current && frontmostPID == expected.token.pid && !isModal && !isMinimized
    }
}

/// A transient AX failure is "unknown", not proof that all windows were closed.
public struct PresenceTracker: Sendable {
    private var missing: [WindowToken: Int] = [:]
    public init() {}
    public mutating func reconcile(known: Set<WindowToken>, observed: Set<WindowToken>?,
                                    threshold: Int = 2) -> (hidden: Set<WindowToken>, removed: Set<WindowToken>) {
        guard let observed else { return (known, []) }
        var hidden = Set<WindowToken>(), removed = Set<WindowToken>()
        for token in known {
            if observed.contains(token) { missing[token] = nil }
            else {
                hidden.insert(token)
                missing[token, default: 0] += 1
                if missing[token, default: 0] >= threshold { removed.insert(token); missing[token] = nil }
            }
        }
        for token in Array(missing.keys) where !known.contains(token) { missing[token] = nil }
        return (hidden, removed)
    }
}
