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
        isOpaque = false
        backgroundColor = .windowBackgroundColor
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
        alphaValue = 0
        ignoresMouseEvents = true
        setAccessibilityLabel("WindowBar 外付けタイトルバー")
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    func hide() { alphaValue = 0; ignoresMouseEvents = true; orderOut(nil) }
    func reveal() { alphaValue = 1; ignoresMouseEvents = false }
    func probe() { alphaValue = 0; ignoresMouseEvents = true }
}
