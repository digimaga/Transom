import AppKit
import TransomCore

final class HeaderPanel: NSPanel {
    let token: WindowToken
    let headerView = HeaderView(frame: .zero)
    var globalHeaderFrame: Rect?
    var targetFrame: Rect?
    /// When `targetFrame` was last written by the per-frame tracker (0 = only by the metadata pass).
    var followedAt: TimeInterval = 0
    var orderRequestedAt: TimeInterval = 0
    var unsafeCount = 0
    var renderedAt: TimeInterval = -1
    var renderedFocused = false

    init(token: WindowToken) {
        self.token = token
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        // Non-opaque with a clear background: while concealed the content view is hidden, the backing store
        // has no opaque pixel, and the window server passes every click through to the windows below. That
        // matters because the panel's backfill band lies under the target's title bar (the target is
        // ordered in front of it); an opaque or intercepting concealed panel would swallow those clicks.
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isFloatingPanel = false
        becomesKeyOnlyIfNeeded = true
        isMovable = false
        isMovableByWindowBackground = false
        animationBehavior = .none
        // Only headers whose targets are confirmed on-screen are shown. No target Space is modified.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        level = .normal
        contentView = headerView
        conceal()
        setAccessibilityLabel(NSLocalizedString("Transom 外付けタイトルバー", comment: "Accessibility label for the external title bar panel"))
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    func hide() { conceal(); orderOut(nil) }
    func reveal() { headerView.isHidden = false; alphaValue = 1 }
    func probe() { conceal() }
    /// Invisible AND intercepting nothing: with the content view hidden the backing store has no opaque
    /// pixel, so the window server routes every click to the windows below. `ignoresMouseEvents` is
    /// deliberately never touched: once it has been set to false, the window receives events over its
    /// whole frame for good, transparent pixels included (macOS 26.6).
    private func conceal() { alphaValue = 0; headerView.isHidden = true }
}
