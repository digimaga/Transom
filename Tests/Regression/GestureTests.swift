import AppKit
import TransomCore

@MainActor enum FixturePointer {
    static var location = NSPoint.zero
}

@main struct GestureTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        var passed = 0
        for titleSurface in [false, true] {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 30),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            let header = HeaderView(frame: NSRect(x: 0, y: 0, width: 600, height: 30))
            window.contentView = header
            header.layoutSubtreeIfNeeded()
            let surface = titleSurface ? header.subviews[1] : header
            var beginnings: [NSPoint] = []
            var actions: [String] = []
            header.onDragBegan = { beginnings.append($0); actions.append("begin") }
            header.onDragMoved = { actions.append("move") }
            header.onDragEnded = { actions.append("end") }
            header.onMaximize = { actions.append("maximize") }
            header.onVerticalMaximize = { actions.append("vertical") }
            func event(_ type: NSEvent.EventType, x: CGFloat) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: 15), modifierFlags: [],
                    timestamp: 1, windowNumber: window.windowNumber, context: nil, eventNumber: 1,
                    clickCount: 2, pressure: 1)!
            }
            FixturePointer.location = NSPoint(x: -300, y: 1500)
            surface.mouseDown(with: event(.leftMouseDown, x: 300))
            FixturePointer.location = NSPoint(x: -280, y: 1470)
            surface.mouseDragged(with: event(.leftMouseDragged, x: 310))
            header.isHidden = true
            surface.mouseUp(with: event(.leftMouseUp, x: 310))
            guard beginnings == [NSPoint(x: -300, y: 1500)], actions == ["begin", "move", "end"] else {
                fputs("FAIL mouse-down pointer or direct hidden mouse-up; titleSurface=\(titleSurface)\n", stderr)
                exit(1)
            }
            passed += 1
        }
        print("RESULT gesture passed=\(passed) total=2")
    }
}
