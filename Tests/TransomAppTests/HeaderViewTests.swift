import AppKit
import Testing
import TransomCore
@testable import TransomApp

@Suite(.serialized) @MainActor struct HeaderViewTests {
    private let headings = ["App", "File", "Edit", "View", "Window", "Help"].enumerated().map {
        MenuHeading(index: $0.offset, title: $0.element)
    }

    private func makeWindow(width: CGFloat = 600, height: CGFloat = 30) -> (NSWindow, HeaderView) {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: width, height: height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        let header = HeaderView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        window.contentView = header
        return (window, header)
    }

    private func snapshot() -> WindowSnapshot {
        WindowSnapshot(token: WindowToken(processInstance: UUID(), pid: 123, windowID: 7, incarnation: 1),
                       appName: "Test", bundleIdentifier: nil, title: "Document",
                       frame: Rect(x: 100, y: 100, width: 600, height: 400),
                       focused: true, minimized: false, fullscreen: false, modal: false,
                       eligible: true, headings: headings, observedAt: 1)
    }

    private func event(_ type: NSEvent.EventType, at point: NSPoint, in window: NSWindow,
                       clickCount: Int = 1) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 1,
                           windowNumber: window.windowNumber, context: nil, eventNumber: 1,
                           clickCount: clickCount, pressure: 1)!
    }

    private func buttons(_ header: HeaderView) -> [NSButton] {
        header.subviews.compactMap { $0 as? NSButton }
    }

    @Test func configuredHeightsProduceRealButtonAndDragHitAreas() {
        for height in [24.0, 28, 30, 34, 38] {
            let (window, header) = makeWindow(height: height)
            header.setAppearance(accent: nil, base: nil, fill: false, lineWidth: 2, height: height)
            header.update(snapshot(), icon: nil, focused: true)
            header.layoutSubtreeIfNeeded()
            let allButtons = buttons(header)
            #expect(allButtons.count >= 5)
            let controls = Array(allButtons.dropFirst(2).prefix(3))
            let title = header.subviews[1]
            #expect(controls.count == 3)
            #expect(controls.allSatisfy { $0.frame.height == height && $0.frame.width == 40 })
            #expect(controls.last?.frame.maxX == 600)
            #expect(abs(title.frame.height - height) < 0.01)
            #expect(title.frame.width > 0)
            #expect(header.hitTest(NSPoint(x: title.frame.midX, y: title.frame.midY)) === title)
            #expect(header.hitTest(NSPoint(x: 580, y: height / 2)) === controls.last)
            #expect(window.contentView === header)
        }
    }

    @Test func overflowDeliversEveryHiddenHeadingOnceAndVisibleHeadingSeparately() {
        let (window, header) = makeWindow(width: 420)
        header.update(snapshot(), icon: nil, focused: true)
        header.layoutSubtreeIfNeeded()
        let allButtons = buttons(header)
        let overflow = allButtons.first { $0.title == "»" }
        let visibleMenus = allButtons.filter { ["File", "Edit", "View", "Window", "Help"].contains($0.title) && !$0.isHidden }
        #expect(visibleMenus.count == 3)
        var received: [[MenuHeading]] = []
        header.onMenu = { selected, _ in received.append(selected) }
        #expect(overflow?.isHidden == false)
        overflow?.performClick(nil)
        #expect(received.count == 1)
        let hidden = Array(headings.dropFirst(1 + visibleMenus.count))
        #expect(received.first == hidden)
        for button in visibleMenus { button.performClick(nil) }
        #expect(received.dropFirst().flatMap { $0 } == Array(headings.dropFirst().prefix(visibleMenus.count)))
        #expect(Set(received.flatMap { $0 }) == Set(headings.dropFirst()))
        #expect(received.flatMap { $0 }.count == headings.count - 1)
        #expect(window.contentView === header)
    }

    @Test func threeControlsInvokeOnlyTheirOwnCallbacks() {
        let (_, header) = makeWindow()
        var calls: [String] = []
        header.onMinimize = { calls.append("minimize") }
        header.onMaximize = { calls.append("maximize") }
        header.onClose = { calls.append("close") }
        for button in buttons(header).filter({ $0.imagePosition == .imageOnly }) {
            button.performClick(nil)
        }
        #expect(calls == ["minimize", "maximize", "close"])
    }

    @Test func directTitleSurfaceEventsIncludingHiddenMouseUpStaySeparated() {
        let (window, header) = makeWindow()
        header.update(snapshot(), icon: nil, focused: true)
        header.layoutSubtreeIfNeeded()
        let surface = header.subviews[1]
        var calls: [String] = []
        var beganAt: [NSPoint] = []
        header.onDragBegan = { beganAt.append($0); calls.append("begin") }
        header.onDragMoved = { calls.append("move") }
        header.onDragEnded = { calls.append("end") }
        header.onMaximize = { calls.append("maximize") }
        header.onVerticalMaximize = { calls.append("vertical") }
        let center = NSPoint(x: surface.frame.midX, y: 15)
        surface.mouseDown(with: event(.leftMouseDown, at: center, in: window, clickCount: 2))
        #expect(calls.isEmpty)
        surface.mouseUp(with: event(.leftMouseUp, at: center, in: window, clickCount: 2))
        #expect(calls == ["maximize"])
        calls.removeAll()
        let topEdge = NSPoint(x: center.x, y: 25)
        surface.mouseDown(with: event(.leftMouseDown, at: topEdge, in: window, clickCount: 2))
        surface.mouseUp(with: event(.leftMouseUp, at: topEdge, in: window, clickCount: 2))
        #expect(calls == ["vertical"])
        calls.removeAll()
        surface.mouseDown(with: event(.leftMouseDown, at: center, in: window))
        surface.mouseDragged(with: event(.leftMouseDragged,
                                         at: NSPoint(x: center.x + 10, y: center.y), in: window))
        surface.mouseUp(with: event(.leftMouseUp, at: center, in: window))
        #expect(calls == ["begin", "move", "end"])
        #expect(beganAt.count == 1)
        calls.removeAll()
        surface.mouseDown(with: event(.leftMouseDown, at: center, in: window, clickCount: 2))
        surface.mouseDragged(with: event(.leftMouseDragged,
                                         at: NSPoint(x: center.x + 3, y: center.y), in: window, clickCount: 2))
        surface.mouseUp(with: event(.leftMouseUp, at: center, in: window, clickCount: 2))
        #expect(calls == ["begin", "move", "end"])
        calls.removeAll()
        surface.mouseDown(with: event(.leftMouseDown, at: center, in: window, clickCount: 2))
        header.isHidden = true
        surface.mouseUp(with: event(.leftMouseUp, at: center, in: window, clickCount: 2))
        #expect(calls == ["maximize"])
    }

    @Test func focusedFillAndBaseColorsReachRealButtonTints() {
        let (window, header) = makeWindow()
        header.update(snapshot(), icon: nil, focused: false)
        let controls = buttons(header).filter { $0.imagePosition == .imageOnly }
        let appButton = buttons(header)[0]
        #expect(controls.allSatisfy { $0.contentTintColor == nil })
        header.setAppearance(accent: .black, base: nil, fill: true, lineWidth: 2, height: 30)
        header.update(snapshot(), icon: nil, focused: true)
        #expect(controls.allSatisfy { $0.contentTintColor == .white })
        #expect(appButton.attributedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .white)
        header.setAppearance(accent: .white, base: nil, fill: true, lineWidth: 2, height: 30)
        #expect(controls.allSatisfy { $0.contentTintColor == .black })
        header.update(snapshot(), icon: nil, focused: false)
        #expect(controls.allSatisfy { $0.contentTintColor == nil })
        header.setAppearance(accent: nil, base: .black, fill: false, lineWidth: 2, height: 30)
        #expect(controls.allSatisfy { $0.contentTintColor == .white })
        header.setAppearance(accent: nil, base: nil, fill: false, lineWidth: 2, height: 30)
        #expect(controls.allSatisfy { $0.contentTintColor == nil })
        let close = controls[2]
        close.mouseEntered(with: event(.mouseMoved, at: .zero, in: window))
        #expect(close.contentTintColor == .white)
        close.mouseExited(with: event(.mouseMoved, at: .zero, in: window))
        #expect(close.contentTintColor == nil)
    }
}
