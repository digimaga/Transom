import AppKit
import WindowBarCore

final class HeaderPanel: NSPanel {
    let token: WindowToken
    let headerView = HeaderView(frame: .zero)
    var globalHeaderFrame: Rect?
    var targetFrame: Rect?
    var orderRequestedAt: TimeInterval = 0
    var unsafeCount = 0
    var renderedAt: TimeInterval = -1
    var renderedFocused = false

    init(token: WindowToken) {
        self.token = token
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        // Non-opaque with a clear background: the band below the header strip is transparent except for the
        // corner notches, and the window server passes clicks through fully transparent pixels.
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
        setAccessibilityLabel("WindowBar 外付けタイトルバー")
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    func hide() { conceal(); orderOut(nil) }
    func reveal() { headerView.isHidden = false; alphaValue = 1 }
    func probe() { conceal() }
    /// Invisible AND intercepting nothing: with the content view hidden the backing store has no opaque
    /// pixel, so the window server routes every click to the windows below. `ignoresMouseEvents` is
    /// deliberately never touched: once it has been set to false, the window receives events over its
    /// whole frame for good, including the transparent band over the target's corners (macOS 26.6).
    private func conceal() { alphaValue = 0; headerView.isHidden = true }
}
