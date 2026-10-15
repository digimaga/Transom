import Foundation
import Testing
@testable import TransomCore

@Suite struct PresenceRefreshTests {
    let instance = UUID()

    func token(_ id: UInt32) -> WindowToken {
        WindowToken(processInstance: instance, pid: 123, windowID: id, incarnation: 1)
    }

    @Test func partialRefreshRemovesOnlyConfirmedAbsentWindow() {
        let unreadable = token(1), disappeared = token(2)
        let known: Set<WindowToken> = [unreadable, disappeared]
        var tracker = PresenceTracker()

        // The list succeeds, but the surviving window's attributes cannot be refreshed.
        let first = tracker.reconcile(known: known, observed: [unreadable], refreshed: [])
        #expect(first.hidden == known)
        #expect(first.removed.isEmpty)
        let second = tracker.reconcile(known: known, observed: [unreadable], refreshed: [])
        #expect(second.hidden == known)
        #expect(second.removed == [disappeared])

        let recovered = tracker.reconcile(known: [unreadable], observed: [unreadable], refreshed: [unreadable])
        #expect(recovered.hidden.isEmpty)
        #expect(recovered.removed.isEmpty)
    }

    @Test func unknownListDoesNotCountAsAbsence() {
        let window = token(1)
        var tracker = PresenceTracker()
        _ = tracker.reconcile(known: [window], observed: [], refreshed: [])
        for _ in 0..<3 {
            let unknown = tracker.reconcile(known: [window], observed: nil, refreshed: [])
            #expect(unknown.hidden == [window])
            #expect(unknown.removed.isEmpty)
        }
        let next = tracker.reconcile(known: [window], observed: [window], refreshed: [window])
        #expect(next.hidden.isEmpty)
        #expect(next.removed.isEmpty)
        #expect(tracker.reconcile(known: [window], observed: [], refreshed: []).removed.isEmpty)
    }
}
