import Foundation
import Testing
import TransomCore
@testable import TransomApp

@Suite struct ServerSnapshotTests {
    @Test func duplicateIDsKeepFirstDescriptionAndOriginalOrdering() {
        let first = ServerWindow(id: 12, pid: 100, layer: 0, alpha: 1,
                                 frame: Rect(x: 40, y: 100, width: 800, height: 600))
        let duplicate = ServerWindow(id: 12, pid: 200, layer: 2, alpha: 0,
                                     frame: Rect(x: 400, y: 200, width: 300, height: 200))
        let snapshot = ServerSnapshot(windows: [first, duplicate], readAt: 42)
        #expect(snapshot.byID[12]?.pid == first.pid)
        #expect(snapshot.byID[12]?.frame == first.frame)
        #expect(snapshot.ordering.map(\.pid) == [100, 200])
        #expect(snapshot.ordering.map(\.frame) == [first.frame, duplicate.frame])
        #expect(snapshot.readAt == 42)
    }

    @Test func newerSnapshotDoesNotChangePreviouslyReadMetadata() {
        var windows = [ServerWindow(id: 12, pid: 100, layer: 0, alpha: 1,
                                    frame: Rect(x: 40, y: 100, width: 800, height: 600))]
        let before = ServerSnapshot(windows: windows, readAt: 42)
        windows.removeAll()
        let after = ServerSnapshot(windows: windows, readAt: 43)
        #expect(before.byID[12]?.pid == 100)
        #expect(before.ordering.count == 1)
        #expect(after.byID.isEmpty)
        #expect(after.ordering.isEmpty)
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
