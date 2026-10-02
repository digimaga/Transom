import AppKit
import TransomCore

private final class ActionButton: NSButton {
    var invoke: (() -> Void)?
    /// Fill drawn under the button while the pointer is inside it (Windows-style hover); nil draws nothing.
    var hoverTint: NSColor?
    /// Glyph colour while hovered; nil keeps normalTint.
    var hoverTextTint: NSColor?
    /// Resting glyph colour, written by the bar's tint pass; contentTintColor follows the hover state.
    var normalTint: NSColor? { didSet { applyTint() } }
    private var hovered = false
    private var tracking: NSTrackingArea?
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
    // AppKit asks the hit view, not its parent. Keep the non-key bar behind its target throughout
    // button tracking; otherwise the ordering check can hide it before mouse-up and lose the click.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func shouldDelayWindowOrdering(for event: NSEvent) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        NSApp.preventWindowOrdering()
        super.mouseDown(with: event)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero,
                                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; applyTint(); needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; applyTint(); needsDisplay = true }
    private func applyTint() { contentTintColor = hovered ? (hoverTextTint ?? normalTint) : normalTint }
    override func draw(_ dirtyRect: NSRect) {
        if hovered, let hoverTint {
            hoverTint.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4).fill()
        }
        super.draw(dirtyRect)
    }
}

/// The empty stretch after the menus: the handle for dragging the window. It shows no text on purpose;
/// the window's own title bar and the app's tabs already name the document, and the app name sits at the
/// left of the bar. The tool tip still carries "app — title" for anyone who hovers.
private final class DragSurface: NSView {
    var began: ((NSPoint) -> Void)?
    var moved: (() -> Void)?
    var ended: (() -> Void)?
    /// Windows-style: a double click on the empty stretch toggles maximize instead of starting a drag.
    var doubleClicked: (() -> Void)?
    private var gesture = TitleBarGesture()
    private var mouseDownPoint = NSPoint.zero
    private var mouseDownScreenPoint = NSPoint.zero
    override init(frame frameRect: NSRect) { super.init(frame: frameRect) }
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func shouldDelayWindowOrdering(for event: NSEvent) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        NSApp.preventWindowOrdering()
        mouseDownPoint = event.locationInWindow
        mouseDownScreenPoint = NSEvent.mouseLocation
        dispatch(gesture.mouseDown(clickCount: event.clickCount))
    }
    override func mouseDragged(with event: NSEvent) {
        dispatch(gesture.mouseDragged(distance: hypot(event.locationInWindow.x - mouseDownPoint.x,
                                                       event.locationInWindow.y - mouseDownPoint.y)))
    }
    override func mouseUp(with event: NSEvent) { dispatch(gesture.mouseUp()) }
    private func dispatch(_ actions: [TitleBarGesture.Action]) {
        for action in actions {
            switch action {
            case .beginDrag: began?(mouseDownScreenPoint)
            case .moveDrag: moved?()
            case .endDrag: ended?()
            case .doubleClick: doubleClicked?()
            }
        }
    }
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
    private var accentColor: NSColor?
    private var baseColor: NSColor?
    private var fillWhenFocused = false
    private var lineWidth = CGFloat(2)
    private var resolvedAccent: NSColor { accentColor ?? .controlAccentColor }
    /// The header strip occupies the top of the view; the rest is the backfill band that runs on behind
    /// the target window and shows only through its rounded corners. Its height is user-configurable.
    private var stripHeight = CGFloat(Geometry.headerHeight)
    private var gesture = TitleBarGesture()
    private var mouseDownPoint = NSPoint.zero
    private var mouseDownScreenPoint = NSPoint.zero
    /// Text, glyphs and the app icon scale modestly with the bar height.
    private var fontSize: CGFloat { min(14, max(11, (stripHeight * 0.42).rounded(.down))) }
    private var symbolSize: CGFloat { min(13, max(10, (stripHeight * 0.37).rounded(.down))) }
    private var iconSize: CGFloat { min(18, max(14, stripHeight - 14)) }
    /// Symbol names and labels of the three window controls, kept for re-rendering at a new size.
    private var controlButtons: [(button: ActionButton, symbol: String, label: String)] = []
    var onMenu: (([MenuHeading], NSPoint) -> Void)?
    var onActivate: (() -> Void)?
    var onDragBegan: ((NSPoint) -> Void)?
    var onDragMoved: (() -> Void)?
    var onDragEnded: (() -> Void)?
    var onMinimize: (() -> Void)?
    var onMaximize: (() -> Void)?
    var onClose: (() -> Void)?
    var onReserveSpace: (() -> Void)?
    var onExclude: (() -> Void)?

    /// Windows-style window menu on a right-click anywhere on the bar: the same actions as the three
    /// buttons plus the two bar-level commands, all routed through the same callbacks.
    private lazy var contextMenu: NSMenu = {
        let menu = NSMenu()
        menu.autoenablesItems = false
        func item(_ title: String, _ selector: Selector) {
            let i = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            i.target = self
            menu.addItem(i)
        }
        item(NSLocalizedString("最小化", comment: "Header button: minimize"), #selector(contextMinimize))
        item(NSLocalizedString("最大化／元のサイズに戻す", comment: "Header button: maximize or restore"), #selector(contextMaximize))
        item(NSLocalizedString("閉じる", comment: "Header button: close"), #selector(contextClose))
        menu.addItem(.separator())
        item(NSLocalizedString("このウィンドウにバー用の空間を確保", comment: "Context menu: reserve bar space on this window"), #selector(contextReserveSpace))
        item(NSLocalizedString("このアプリを除外", comment: "Context menu: exclude this app"), #selector(contextExclude))
        return menu
    }()
    @objc private func contextMinimize() { onMinimize?() }
    @objc private func contextMaximize() { onMaximize?() }
    @objc private func contextClose() { onClose?() }
    @objc private func contextReserveSpace() { onReserveSpace?() }
    @objc private func contextExclude() { onExclude?() }

    override var isFlipped: Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(appButton)
        addSubview(titleSurface)
        addSubview(overflowButton)
        controlButtons = [
            (minimizeButton, "minus", NSLocalizedString("最小化", comment: "Header button: minimize")),
            (maximizeButton, "square", NSLocalizedString("最大化／元のサイズに戻す", comment: "Header button: maximize or restore")),
            (closeButton, "xmark", NSLocalizedString("閉じる", comment: "Header button: close"))
        ]
        for (button, _, label) in controlButtons {
            button.imagePosition = .imageOnly
            button.toolTip = label
            button.setAccessibilityLabel(label)
            addSubview(button)
        }
        minimizeButton.invoke = { [weak self] in self?.onMinimize?() }
        maximizeButton.invoke = { [weak self] in self?.onMaximize?() }
        closeButton.invoke = { [weak self] in self?.onClose?() }
        // Hover feedback: subtle grey everywhere, Windows red for close with a white glyph.
        let subtle = NSColor.labelColor.withAlphaComponent(0.08)
        for button in [appButton, overflowButton, minimizeButton, maximizeButton] { button.hoverTint = subtle }
        closeButton.hoverTint = NSColor(srgbRed: 0.91, green: 0.07, blue: 0.14, alpha: 1)
        closeButton.hoverTextTint = .white
        menu = contextMenu
        for view in [appButton, titleSurface, overflowButton, minimizeButton, maximizeButton, closeButton] {
            view.menu = contextMenu
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
        titleSurface.began = { [weak self] point in self?.onDragBegan?(point) }
        titleSurface.moved = { [weak self] in self?.onDragMoved?() }
        titleSurface.ended = { [weak self] in self?.onDragEnded?() }
        titleSurface.doubleClicked = { [weak self] in self?.onMaximize?() }
        applyMetrics()
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }
    /// Fonts, control glyphs and icon size follow the configured bar height.
    private func applyMetrics() {
        appButton.font = .systemFont(ofSize: fontSize, weight: .semibold)
        overflowButton.font = .systemFont(ofSize: fontSize)
        for button in menuButtons { button.font = .systemFont(ofSize: fontSize) }
        for (button, symbol, label) in controlButtons {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
                .withSymbolConfiguration(.init(pointSize: symbolSize, weight: .regular))
        }
        needsLayout = true
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func shouldDelayWindowOrdering(for event: NSEvent) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        NSApp.preventWindowOrdering()
        mouseDownPoint = event.locationInWindow
        mouseDownScreenPoint = NSEvent.mouseLocation
        dispatch(gesture.mouseDown(clickCount: event.clickCount))
    }
    override func mouseDragged(with event: NSEvent) {
        dispatch(gesture.mouseDragged(distance: hypot(event.locationInWindow.x - mouseDownPoint.x,
                                                       event.locationInWindow.y - mouseDownPoint.y)))
    }
    override func mouseUp(with event: NSEvent) { dispatch(gesture.mouseUp()) }
    private func dispatch(_ actions: [TitleBarGesture.Action]) {
        for action in actions {
            switch action {
            case .beginDrag: onDragBegan?(mouseDownScreenPoint)
            case .moveDrag: onDragMoved?()
            case .endDrag: onDragEnded?()
            case .doubleClick: onMaximize?()
            }
        }
    }

    func update(_ snapshot: WindowSnapshot, icon: NSImage?, focused: Bool) {
        self.focused = focused
        appButton.title = snapshot.appName
        if let icon { let copy = icon.copy() as? NSImage; copy?.size = NSSize(width: iconSize, height: iconSize); appButton.image = copy }
        appButton.toolTip = String(format: NSLocalizedString("%@ のアプリメニュー", comment: "App button tooltip, e.g. 'Safari App Menu'"), snapshot.appName)
        titleSurface.toolTip = snapshot.title.isEmpty ? snapshot.appName : "\(snapshot.appName) — \(snapshot.title)"
        if headings != snapshot.headings {
            headings = snapshot.headings
            menuButtons.forEach { $0.removeFromSuperview() }
            menuButtons = headings.dropFirst().map { heading in
                let button = ActionButton(title: heading.title)
                button.font = .systemFont(ofSize: fontSize)
                button.hoverTint = NSColor.labelColor.withAlphaComponent(0.08)
                button.menu = contextMenu
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
        refreshTextTint()
        needsDisplay = true
    }
    /// accent nil keeps the system accent, base nil keeps the system window background. fill paints
    /// the whole focused bar in the accent; otherwise a lineWidth-point line at the top marks it
    /// (0 draws no line). height is the strip height in points.
    func setAppearance(accent: NSColor?, base: NSColor?, fill: Bool, lineWidth: CGFloat, height: CGFloat) {
        accentColor = accent
        baseColor = base
        fillWhenFocused = fill
        self.lineWidth = lineWidth
        if stripHeight != height { stripHeight = height; applyMetrics() }
        refreshTextTint()
        needsDisplay = true
    }
    /// Titles and glyphs need a readable colour over a painted bar: the accent while the focused bar
    /// is fully painted, a custom base colour at all times. Over the plain system background the
    /// regular label colour stays.
    private func refreshTextTint() {
        let tinted = focused && fillWhenFocused
        let text: NSColor
        if tinted { text = readableTextColor(on: resolvedAccent) }
        else if let baseColor { text = readableTextColor(on: baseColor) }
        else { text = .labelColor }
        for button in [appButton, overflowButton] + menuButtons {
            button.attributedTitle = NSAttributedString(string: button.title, attributes:
                [.font: button.font ?? .systemFont(ofSize: fontSize), .foregroundColor: text])
        }
        for button in [minimizeButton, maximizeButton, closeButton] { button.normalTint = tinted ? text : nil }
    }
    private func readableTextColor(on background: NSColor) -> NSColor {
        guard let color = background.usingColorSpace(.sRGB) else { return .labelColor }
        let lum = 0.299 * color.redComponent + 0.587 * color.greenComponent + 0.114 * color.blueComponent
        return lum > 0.55 ? .black : .white
    }
    private func anchor(_ frame: NSRect) -> NSPoint { NSPoint(x: frame.minX, y: frame.maxY) }
    override func layout() {
        super.layout()
        let font = NSFont.systemFont(ofSize: fontSize)
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
        // In fill style the focused window's bar colour is the accent itself.
        if focused && fillWhenFocused {
            resolvedAccent.setFill()
            bounds.fill()
            return
        }
        (baseColor ?? .windowBackgroundColor).setFill()
        bounds.fill()
        if focused && lineWidth > 0 {
            resolvedAccent.setFill()
            NSRect(x: 0, y: 0, width: bounds.width, height: lineWidth).fill()
        }
    }
}
