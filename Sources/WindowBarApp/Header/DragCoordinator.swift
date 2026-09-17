import AppKit
import WindowBarCore

@MainActor
final class DragCoordinator {
    private final class Session {
        let id = UUID()
        let token: WindowToken
        let worker: AXAppWorker
        let origin: Rect
        let initialMouse: Point
        let permit = OperationPermit(lifetime: 180)
        var ready = false
        var released = false
        var inFlight = false
        var desired: Point?
        init(token: WindowToken, worker: AXAppWorker, origin: Rect, mouse: Point) {
            self.token = token; self.worker = worker; self.origin = origin; initialMouse = mouse
        }
    }
    var onStatus: ((String) -> Void)?
    var onMoved: ((WindowToken, Rect) -> Void)?
    private var session: Session?
    var target: WindowToken? { session?.token }

    func cancel() { session?.permit.cancel(); session = nil }
    func begin(token: WindowToken, worker: AXAppWorker, frame: Rect) {
        cancel()
        guard let geometry = ScreenGeometry.current(),
              let app = NSRunningApplication(processIdentifier: token.pid), !app.isTerminated else { return }
        _ = app.activate() // best effort; the AX path in focus() and validateFocus gate the drag
        let session = Session(token: token, worker: worker, origin: frame, mouse: geometry.globalMouse())
        self.session = session
        worker.focus(token, permit: session.permit) { [weak self, weak session] result in
            guard let self, let session, self.session?.id == session.id, session.permit.isValid() else { return }
            guard case .success = result else {
                if case .failure(let error) = result { self.onStatus?(error.localizedDescription) }
                self.cancel()
                return
            }
            session.ready = true
            self.pump()
        }
    }
    func moved() {
        guard let session, let geometry = ScreenGeometry.current() else { return }
        let mouse = geometry.globalMouse()
        var point = Point(x: session.origin.x + mouse.x - session.initialMouse.x,
                          y: session.origin.y + mouse.y - session.initialMouse.y)
        // When dragging this header, keep the header itself reachable on the destination screen.
        if let screen = geometry.visibleFrames.first(where: {
            mouse.x >= $0.x && mouse.x <= $0.maxX && mouse.y >= $0.y && mouse.y <= $0.maxY
        }) { point.y = max(point.y, screen.y + 30) }
        session.desired = point
        pump()
    }
    func ended() { session?.released = true; pump() }
    private func pump() {
        guard let session, session.ready, !session.inFlight else { return }
        guard let point = session.desired else { if session.released { cancel() }; return }
        session.desired = nil
        session.inFlight = true
        session.worker.move(session.token, to: point, permit: session.permit) { [weak self, weak session] result in
            guard let self, let session, self.session?.id == session.id else { return }
            session.inFlight = false
            switch result {
            case .success(let actual): self.onMoved?(session.token, actual)
            case .failure(let error): self.onStatus?(error.localizedDescription); self.cancel(); return
            }
            self.pump() // single in-flight write, latest requested point wins; no unbounded mouse queue
        }
    }
}
