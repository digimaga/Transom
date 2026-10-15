import Testing
@testable import TransomCore

@Suite struct MaximizeHistoryTests {
    let original = Rect(x: 240, y: 439, width: 680, height: 448)

    @Test func constrainedMaximizeStillRestoresOriginalFrame() {
        let accepted = Rect(x: 0, y: 63, width: 800, height: 700)
        let history = MaximizeHistory(original: original, applied: accepted)
        #expect(history.matches(accepted))
        #expect(history.restorationFrame(from: accepted) == original)
        #expect(!history.matches(Rect(x: 100, y: 63, width: 800, height: 700)))
    }

    @Test func verticalRestorePreservesLaterHorizontalChanges() {
        let accepted = Rect(x: 240, y: 63, width: 680, height: 700)
        let current = Rect(x: -100, y: 63, width: 900, height: 700)
        let history = MaximizeHistory(original: original, applied: accepted)
        #expect(history.matches(current, verticalOnly: true))
        #expect(history.restorationFrame(from: current, verticalOnly: true)
            == Rect(x: -100, y: 439, width: 900, height: 448))
        #expect(!history.matches(Rect(x: -100, y: 100, width: 900, height: 700), verticalOnly: true))
    }

    @Test func fullAndVerticalHistoriesRemainIndependent() {
        let verticalFrame = Rect(x: 240, y: 63, width: 680, height: 700)
        let fullFrame = Rect(x: 0, y: 63, width: 1000, height: 700)
        let vertical = MaximizeHistory(original: original, applied: verticalFrame)
        let full = MaximizeHistory(original: verticalFrame, applied: fullFrame)
        let fullRestored = full.restorationFrame(from: fullFrame)
        #expect(vertical.matches(fullRestored, verticalOnly: true))
        #expect(vertical.restorationFrame(from: fullRestored, verticalOnly: true) == original)
    }
}
