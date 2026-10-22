import Foundation
import Testing
import TransomCore
@testable import TransomApp

@Suite struct ServerSnapshotTests {
    @Test func duplicateIDsKeepFirstDescriptionAndNewSnapshotDoesNotMutateOld() {
        let first = ServerWindow(id: 12, pid: 100, layer: 0, alpha: 1,
                                 frame: Rect(x: 40, y: 100, width: 800, height: 600))
        let duplicate = ServerWindow(id: 12, pid: 200, layer: 2, alpha: 0,
                                     frame: Rect(x: 400, y: 200, width: 300, height: 200))
        let snapshot = ServerSnapshot(windows: [first, duplicate], readAt: 42)
        #expect(snapshot.windows.map(\.id) == [12, 12])
        #expect(snapshot.byID[12]?.id == first.id)
        #expect(snapshot.byID[12]?.pid == first.pid)
        #expect(snapshot.byID[12]?.layer == first.layer)
        #expect(snapshot.byID[12]?.alpha == first.alpha)
        #expect(snapshot.byID[12]?.frame == first.frame)
        #expect(snapshot.ordering.map(\.id) == [12, 12])
        #expect(snapshot.ordering.map(\.pid) == [100, 200])
        #expect(snapshot.ordering.map(\.frame) == [first.frame, duplicate.frame])
        #expect(snapshot.readAt == 42)
        let replacement = ServerWindow(id: 12, pid: 300, layer: 4, alpha: 0.5,
                                       frame: Rect(x: -200, y: 80, width: 500, height: 400))
        let newer = ServerSnapshot(windows: [replacement], readAt: 43)
        #expect(newer.windows.count == 1)
        #expect(newer.byID[12]?.id == replacement.id)
        #expect(newer.byID[12]?.pid == replacement.pid)
        #expect(newer.byID[12]?.layer == replacement.layer)
        #expect(newer.byID[12]?.alpha == replacement.alpha)
        #expect(newer.byID[12]?.frame == replacement.frame)
        #expect(newer.ordering.map(\.id) == [12])
        #expect(newer.ordering.map(\.pid) == [300])
        #expect(newer.ordering.map(\.frame) == [replacement.frame])
        #expect(newer.readAt == 43)
        #expect(snapshot.byID[12]?.pid == 100)
        #expect(snapshot.byID[12]?.layer == 0)
        #expect(snapshot.byID[12]?.alpha == 1)
        #expect(snapshot.byID[12]?.frame == first.frame)
        #expect(snapshot.ordering.map(\.pid) == [100, 200])
        #expect(snapshot.ordering.map(\.frame) == [first.frame, duplicate.frame])
        #expect(snapshot.readAt == 42)
    }
}

@Suite @MainActor struct FrameTrackerTests {
    @Test func firstSampleDoesNotWaitForTimerAndRepeatedStartDoesNotResample() {
        let tracker = FrameTracker()
        var samples = 0
        tracker.windowIDs = { samples += 1; return [] }
        defer { tracker.stop() }
        tracker.start()
        #expect(tracker.isRunning)
        #expect(samples == 1)
        tracker.start()
        #expect(samples == 1)
    }

    @Test func stoppedTrackerCanRestartWithAFreshTargetSelection() {
        let tracker = FrameTracker()
        var samples = 0
        tracker.windowIDs = { samples += 1; return [] }
        tracker.start()
        tracker.stop()
        #expect(!tracker.isRunning)
        tracker.start()
        #expect(samples == 2)
        tracker.stop()
        tracker.stop()
        #expect(!tracker.isRunning)
    }
}
