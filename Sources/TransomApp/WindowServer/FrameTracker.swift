import AppKit
import TransomCore

/// Reads the on-screen bounds of a few known windows several times per display frame (metadata only: no
/// pixels, no kCGWindowName). It runs only while a mouse button is held or a header drag is active, so a
/// header follows a window that is being dragged or resized within the same frame instead of waiting for
/// the 20 Hz metadata poll. Z-order safety is still decided by the regular metadata pass.
@MainActor
final class FrameTracker {
    var windowIDs: (() -> [UInt32])?
    var onFrames: (([UInt32: Rect]) -> Void)?
    private var timer: Timer?
    var isRunning: Bool { timer != nil }
    /// Polling period. Reading a few window bounds costs well under 0.1 ms, and polling several times per
    /// display frame lets the header be re-placed within the same frame in which the target moved,
    /// instead of one frame later as a display-link callback (start of frame) would.
    static let period: TimeInterval = 1.0 / 240

    func start() {
        precondition(Thread.isMainThread)
        guard timer == nil else { return }
        let timer = Timer(timeInterval: FrameTracker.period, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
        timer.tolerance = 0
        // Common modes: keeps ticking while an NSMenu is tracking, like every other main-thread delivery here.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    func stop() {
        precondition(Thread.isMainThread)
        timer?.invalidate()
        timer = nil
    }
    private func step() {
        guard let ids = windowIDs?(), !ids.isEmpty else { return }
        WindowServer.flushPendingTransaction()
        var frames: [UInt32: Rect] = [:]
        for window in WindowServer.describe(ids) { frames[window.id] = window.frame }
        if !frames.isEmpty { onFrames?(frames) }
    }
}
