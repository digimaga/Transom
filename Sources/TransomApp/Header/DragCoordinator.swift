import AppKit
import OSLog
import TransomCore

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
        var lastThoroughCheck: TimeInterval = 0
        init(token: WindowToken, worker: AXAppWorker, origin: Rect, mouse: Point) {
            self.token = token; self.worker = worker; self.origin = origin; initialMouse = mouse
        }
    }
    private static let logger = Logger(subsystem: "dev.local.Transom", category: "drag")
    var onStatus: ((String) -> Void)?
    /// The target was raised and focus-validated; move steps start now.
    var onReady: ((WindowToken) -> Void)?
    /// One step landed: the frame the window actually took.
    var onMoved: ((WindowToken, Rect) -> Void)?
    /// The session ended (release, failure or cancellation) after at least one step was attempted.
    var onFinished: ((WindowToken) -> Void)?
    private var session: Session?
    /// Height of the external header; a drag keeps this much of the bar reachable on the target screen.
    var headerHeight = Geometry.headerHeight
    var target: WindowToken? { session?.token }

    func cancel() {
        guard let session else { return }
        session.permit.cancel()
        self.session = nil
        if session.ready { onFinished?(session.token) }
    }
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
            self.onReady?(session.token)
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
        }) { point.y = max(point.y, screen.y + headerHeight) }
        session.desired = point
        pump()
    }
    func ended() { session?.released = true; pump() }
    private func pump() {
        guard let session, session.ready, !session.inFlight else { return }
        guard let point = session.desired else { if session.released { cancel() }; return }
        session.desired = nil
        session.inFlight = true
        // Full validation on the first step and periodically; the cheap identity check in between.
        let now = ProcessInfo.processInfo.systemUptime
        let thorough = now - session.lastThoroughCheck > 0.25
        if thorough { session.lastThoroughCheck = now }
        session.worker.move(session.token, to: point, thorough: thorough, permit: session.permit) { [weak self, weak session] result in
            guard let self, let session, self.session?.id == session.id else { return }
            session.inFlight = false
            let elapsed = (ProcessInfo.processInfo.systemUptime - now) * 1000
            DragCoordinator.logger.debug("move step \(thorough ? "thorough" : "quick", privacy: .public) \(elapsed, format: .fixed(precision: 1), privacy: .public) ms")
            switch result {
            case .success(let actual): self.onMoved?(session.token, actual)
            case .failure(let error): self.onStatus?(error.localizedDescription); self.cancel(); return
            }
            self.pump() // single in-flight write, latest requested point wins; no unbounded mouse queue
        }
    }
}
