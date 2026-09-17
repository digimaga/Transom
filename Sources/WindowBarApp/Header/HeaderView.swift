import AppKit
import WindowBarCore

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

private final class DragSurface: NSView {
    let label = NSTextField(labelWithString: "")
    var began: (() -> Void)?
    var moved: (() -> Void)?
    var ended: (() -> Void)?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.font = .systemFont(ofSize: 12)
        label.lineBreakMode = .byTruncatingMiddle
        label.isSelectable = false
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }
    override func layout() {
        super.layout()
        label.frame = NSRect(x: 0, y: max(0, (bounds.height - 18) / 2), width: bounds.width, height: 18)
    }
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
    private var menuButtons: [ActionButton] = []
    private var headings: [MenuHeading] = []
    private var currentLayout: HeaderLayout?
    private var focused = false
    var onMenu: (([MenuHeading], NSPoint) -> Void)?
    var onActivate: (() -> Void)?
    var onDragBegan: (() -> Void)?
    var onDragMoved: (() -> Void)?
    var onDragEnded: (() -> Void)?

    override var isFlipped: Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(appButton)
        addSubview(titleSurface)
        addSubview(overflowButton)
        appButton.font = .systemFont(ofSize: 12, weight: .semibold)
        appButton.imagePosition = .imageLeft
        appButton.imageScaling = .scaleProportionallyDown
        appButton.invoke = { [weak self] in
            guard let self else { return }
            if let first = self.headings.first { self.onMenu?([first], self.anchor(self.appButton.frame)) }
            else { self.onActivate?() }
        }
        overflowButton.toolTip = "残りのメニュー"
        overflowButton.setAccessibilityLabel("残りのアプリメニュー")
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
        appButton.toolTip = "\(snapshot.appName) のアプリメニュー"
        titleSurface.label.stringValue = snapshot.title.isEmpty ? "" : "— \(snapshot.title)"
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
        let layout = HeaderLayout.make(width: Double(bounds.width), height: Double(bounds.height),
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
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
        if focused {
            NSColor.controlAccentColor.setFill()
            NSRect(x: 0, y: 0, width: bounds.width, height: 2).fill()
        }
    }
}
