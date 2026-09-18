import AppKit
import TransomCore

private final class ActionButton: NSButton {
    var invoke: (() -> Void)?
    init(title: String) {
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        font = .systemFont(ofSize: 12)
        setButtonType(.momentaryChange)
        target = self
        action = #selector(fire)
    }
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }
    @objc private func fire() { invoke?() }
    override var acceptsFirstResponder: Bool { false }
}

/// The empty stretch after the menus: the handle for dragging the window. It shows no text on purpose;
/// the window's own title bar and the app's tabs already name the document, and the app name sits at the
/// left of the bar. The tool tip still carries "app — title" for anyone who hovers.
private final class DragSurface: NSView {
    var began: (() -> Void)?
    var moved: (() -> Void)?
    var ended: (() -> Void)?
    override init(frame frameRect: NSRect) { super.init(frame: frameRect) }
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { began?() }
    override func mouseDragged(with event: NSEvent) { moved?() }
    override func mouseUp(with event: NSEvent) { ended?() }
}

final class HeaderView: NSView {
    private let appButton = ActionButton(title: "")
    private let titleSurface = DragSurface(frame: .zero)
    private let overflowButton = ActionButton(title: "»")
    /// Windows-style window controls at the right edge, left to right: minimize, maximize, close.
    private let minimizeButton = ActionButton(title: "")
    private let maximizeButton = ActionButton(title: "")
    private let closeButton = ActionButton(title: "")
    private var menuButtons: [ActionButton] = []
    private var headings: [MenuHeading] = []
    private var currentLayout: HeaderLayout?
    private var focused = false
    /// The header strip occupies the top of the view; the rest is the backfill band that runs on behind
    /// the target window and shows only through its rounded corners.
    private let stripHeight = CGFloat(Geometry.headerHeight)
    var onMenu: (([MenuHeading], NSPoint) -> Void)?
    var onActivate: (() -> Void)?
    var onDragBegan: (() -> Void)?
    var onDragMoved: (() -> Void)?
    var onDragEnded: (() -> Void)?
    var onMinimize: (() -> Void)?
    var onMaximize: (() -> Void)?
    var onClose: (() -> Void)?

    override var isFlipped: Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(appButton)
        addSubview(titleSurface)
        addSubview(overflowButton)
        for (button, symbol, label, action) in [
            (minimizeButton, "minus", NSLocalizedString("最小化", comment: "Header button: minimize"), { [weak self] in self?.onMinimize?() }),
            (maximizeButton, "square", NSLocalizedString("最大化／元のサイズに戻す", comment: "Header button: maximize or restore"), { [weak self] in self?.onMaximize?() }),
            (closeButton, "xmark", NSLocalizedString("閉じる", comment: "Header button: close"), { [weak self] in self?.onClose?() })
        ] as [(ActionButton, String, String, () -> Void)] {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
                .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
            button.imagePosition = .imageOnly
            button.toolTip = label
            button.setAccessibilityLabel(label)
            button.invoke = action
            addSubview(button)
        }
        appButton.font = .systemFont(ofSize: 12, weight: .semibold)
        appButton.imagePosition = .imageLeft
        appButton.imageScaling = .scaleProportionallyDown
        appButton.invoke = { [weak self] in
            guard let self else { return }
            if let first = self.headings.first { self.onMenu?([first], self.anchor(self.appButton.frame)) }
            else { self.onActivate?() }
        }
        overflowButton.toolTip = NSLocalizedString("残りのメニュー", comment: "Overflow button tooltip")
        overflowButton.setAccessibilityLabel(NSLocalizedString("残りのアプリメニュー", comment: "Overflow button accessibility label"))
        overflowButton.invoke = { [weak self] in
            guard let self, let layout = self.currentLayout else { return }
            let rest = Array(self.headings.dropFirst().dropFirst(layout.visibleMenuCount))
            if !rest.isEmpty { self.onMenu?(rest, self.anchor(self.overflowButton.frame)) }
        }
        titleSurface.began = { [weak self] in self?.onDragBegan?() }
        titleSurface.moved = { [weak self] in self?.onDragMoved?() }
        titleSurface.ended = { [weak self] in self?.onDragEnded?() }
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onDragBegan?() }
    override func mouseDragged(with event: NSEvent) { onDragMoved?() }
    override func mouseUp(with event: NSEvent) { onDragEnded?() }

    func update(_ snapshot: WindowSnapshot, icon: NSImage?, focused: Bool) {
        self.focused = focused
        appButton.title = snapshot.appName
        if let icon { let copy = icon.copy() as? NSImage; copy?.size = NSSize(width: 16, height: 16); appButton.image = copy }
        appButton.toolTip = String(format: NSLocalizedString("%@ のアプリメニュー", comment: "App button tooltip, e.g. 'Safari App Menu'"), snapshot.appName)
        titleSurface.toolTip = snapshot.title.isEmpty ? snapshot.appName : "\(snapshot.appName) — \(snapshot.title)"
        if headings != snapshot.headings {
            headings = snapshot.headings
            menuButtons.forEach { $0.removeFromSuperview() }
            menuButtons = headings.dropFirst().map { heading in
                let button = ActionButton(title: heading.title)
                button.toolTip = heading.title
                button.setAccessibilityLabel(heading.title)
                button.invoke = { [weak self, weak button] in
                    guard let self, let button else { return }
                    self.onMenu?([heading], self.anchor(button.frame))
                }
                addSubview(button)
                return button
            }
        }
        needsLayout = true
        needsDisplay = true
    }
    private func anchor(_ frame: NSRect) -> NSPoint { NSPoint(x: frame.minX, y: frame.maxY) }
    override func layout() {
        super.layout()
        let font = NSFont.systemFont(ofSize: 12)
        func measured(_ title: String) -> Double {
            Double((title as NSString).size(withAttributes: [.font: font]).width) + 16
        }
        let layout = HeaderLayout.make(width: Double(bounds.width), height: Double(min(bounds.height, stripHeight)),
            appWidth: min(200, measured(appButton.title) + 22), menuWidths: menuButtons.map { measured($0.title) })
        currentLayout = layout
        appButton.frame = layout.app.cgRect
        titleSurface.frame = layout.title.cgRect
        for (i, button) in menuButtons.enumerated() {
            button.isHidden = i >= layout.visibleMenuCount
            if layout.menus.indices.contains(i) { button.frame = layout.menus[i].cgRect }
        }
        overflowButton.isHidden = layout.overflow == nil
        if let rect = layout.overflow { overflowButton.frame = rect.cgRect }
        for (button, rect) in zip([minimizeButton, maximizeButton, closeButton], layout.controls) { button.frame = rect.cgRect }
    }
    override func draw(_ dirtyRect: NSRect) {
        // The whole panel is bar colour: the strip above the window and, below it, the backfill band that
        // the window in front hides everywhere except through its rounded corners. No shape is assumed.
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        if focused {
            NSColor.controlAccentColor.setFill()
            NSRect(x: 0, y: 0, width: bounds.width, height: 2).fill()
        }
    }
}
