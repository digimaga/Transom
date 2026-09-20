/// Resolves the ambiguity between a title-bar double click and a drag that starts on the
/// second click. The double-click action is deferred until mouse-up; moving far enough first
/// turns the same gesture into a drag instead.
public struct TitleBarGesture: Sendable {
    public enum Action: Equatable, Sendable {
        case beginDrag
        case moveDrag
        case endDrag
        case doubleClick
    }

    private enum Phase: Sendable {
        case idle
        case dragging
        case pendingDoubleClick
    }

    private var phase = Phase.idle

    public init() {}

    public mutating func mouseDown(clickCount: Int) -> [Action] {
        if clickCount >= 2 {
            phase = .pendingDoubleClick
            return []
        }
        phase = .dragging
        return [.beginDrag]
    }

    public mutating func mouseDragged(distance: Double, threshold: Double = 3) -> [Action] {
        switch phase {
        case .idle:
            return []
        case .dragging:
            return [.moveDrag]
        case .pendingDoubleClick:
            guard distance >= threshold else { return [] }
            phase = .dragging
            return [.beginDrag, .moveDrag]
        }
    }

    public mutating func mouseUp() -> [Action] {
        defer { phase = .idle }
        switch phase {
        case .idle:
            return []
        case .dragging:
            return [.endDrag]
        case .pendingDoubleClick:
            return [.doubleClick]
        }
    }
}
