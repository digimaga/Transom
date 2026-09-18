import AppKit
import ApplicationServices
import OSLog
import TransomCore

@MainActor
private final class WorkerState {
    let worker: AXAppWorker
    let icon: NSImage?
    var scanning = false
    var lastScan: TimeInterval = 0
    var snapshots: [WindowSnapshot] = []
    var hidden = Set<WindowToken>()
    var failed = false
    init(worker: AXAppWorker, icon: NSImage?) { self.worker = worker; self.icon = icon }
}

@MainActor
final class AppController: NSObject {
    private let server = WindowServer()
    private let menus = MenuCoordinator()
    private let drag = DragCoordinator()
    private let tracker = FrameTracker()
    private let logger = Logger(subsystem: "dev.local.Transom", category: "runtime")
    private var workers: [Int32: WorkerState] = [:]
    private var panels: [WindowToken: HeaderPanel] = [:]
    private var metadata: ServerSnapshot?
    private var statusItem: NSStatusItem!
    private var statusLine: NSMenuItem!
    private var toggleItem: NSMenuItem!
    private var timer: Timer?
    private var notificationTokens: [(NotificationCenter, NSObjectProtocol)] = []
    private var enabled = true
    private var trusted = false
    private var running = false
    private var sleeping = false
    private var inactiveSession = false
    private var quarantineUntil: TimeInterval = 0
    private var lastApplicationsRefresh: TimeInterval = 0
    private var lastMetadataRequest: TimeInterval = 0
    private var lastPermissionCheck: TimeInterval = 0
    /// Until when the per-frame tracker and the fast metadata poll stay on after the last mouse-down/drag.
    private var interactionUntil: TimeInterval = 0
    /// Until when metadata is re-read at the fast cadence because an ordering change is being confirmed
    /// (a header was just re-ordered above its target, or the frontmost application changed).
    private var fastPollUntil: TimeInterval = 0
    private var lastMessage = NSLocalizedString("準備中", comment: "Status message shown while the app is starting up")
    private var dirtyApplications = Set<Int32>()
    private var reservePermit: OperationPermit?
    private var reserveTarget: WindowToken?
    /// Frames recorded by the header's maximize button, restored by pressing it again.
    private var restoreFrames: [WindowToken: Rect] = [:]
    private var extraPermits: [OperationPermit] = []
    private var lastFrontmostPID: Int32?
    /// nil means the bar follows the system accent; a stored colour overrides it for the focused window.
    private var accentColor: NSColor?
    /// nil means the system window background; a stored colour recolours every bar.
    private var baseColor: NSColor?
    private var fillWhenFocused = false
    /// Thickness of the accent line on the focused bar, 0–5 points; 0 draws no line.
    private var lineWidth = 2
    private var appearanceItem: NSMenuItem?
    private var systemAccentItem: NSMenuItem!
    private var lineStyleItem: NSMenuItem!
    private var fillStyleItem: NSMenuItem!
    private var lineWidthItems: [NSMenuItem] = []
    private var baseColorItem: NSMenuItem?
    private var systemBaseItem: NSMenuItem!
    private let ownPID = Int32(ProcessInfo.processInfo.processIdentifier)
    private var excluded: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: "excludedBundleIDs") ?? [])
    }

    func start() {
        precondition(Thread.isMainThread)
        UserDefaults.standard.register(defaults: ["enabled": true, "activeBarFill": false, "activeBarLineWidth": 2])
        enabled = UserDefaults.standard.bool(forKey: "enabled")
        fillWhenFocused = UserDefaults.standard.bool(forKey: "activeBarFill")
        lineWidth = min(5, max(0, UserDefaults.standard.integer(forKey: "activeBarLineWidth")))
        if let data = UserDefaults.standard.data(forKey: "activeBarColor"),
           let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
            accentColor = color
        }
        if let data = UserDefaults.standard.data(forKey: "barBaseColor"),
           let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
            baseColor = color
        }
        createStatusMenu()
        menus.workerFor = { [weak self] token in self?.worker(for: token) }
        menus.isTargetValid = { [weak self] token in self?.valid(token) ?? false }
        menus.onStatus = { [weak self] message in self?.status(message) }
        drag.onStatus = { [weak self] message in self?.status(message) }
        // The AX raise just brought the drag target to the front, possibly past other windows of its app
        // that now sit between it and the header: put the header directly behind it again now instead of
        // waiting for the metadata pass to notice, and confirm the order at the fast cadence.
        drag.onReady = { [weak self] token in
            guard let self, let panel = self.panels[token], panel.isVisible else { return }
            self.server.order(panel, behind: token.windowID)
            self.fastPollUntil = max(self.fastPollUntil, ProcessInfo.processInfo.systemUptime + 0.15)
        }
        // Place the header on the frame the window just took, in the same frame when possible. The regular
        // metadata pass is not forced per step (it would only add main-thread work during the drag).
        drag.onMoved = { [weak self] token, frame in self?.follow([token.windowID: frame]) }
        drag.onFinished = { [weak self] token in self?.dirtyApplications.insert(token.pid); self?.requestMetadata() }
        AXObserverHub.shared.onChange = { [weak self] pid in self?.dirtyApplications.insert(pid) }
        tracker.windowIDs = { [weak self] in self?.trackedWindowIDs() ?? [] }
        tracker.onFrames = { [weak self] frames in self?.follow(frames) }
        observeWorkspace()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        trusted = AXIsProcessTrusted()
        if !trusted && enabled { requestPermission() }
        if !server.exactIdentity {
            status(NSLocalizedString("正確なウィンドウID APIが使えないため、表示を停止しています。",
                                      comment: "Status: shown when the exact window ID API is unavailable"))
        }
        tick()
    }
    func stop() {
        timer?.invalidate()
        timer = nil
        suspend()
        for (center, token) in notificationTokens { center.removeObserver(token) }
        notificationTokens.removeAll()
        AXObserverHub.shared.onChange = nil
    }
    private func observeWorkspace() {
        let workspace = NSWorkspace.shared.notificationCenter
        func observe(_ center: NotificationCenter, _ name: Notification.Name, _ block: @escaping @MainActor (Notification) -> Void) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { note in
                MainActor.assumeIsolated { block(note) }
            }
            notificationTokens.append((center, token))
        }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification] {
            observe(workspace, name) { [weak self] _ in self?.lastApplicationsRefresh = 0; self?.requestMetadata() }
        }
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { [weak self] notification in
            guard let self else { return }
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let pid = app?.processIdentifier
            self.lastFrontmostPID = pid
            if let target = self.menus.target, target.pid != pid { self.menus.cancel() }
            if let target = self.drag.target, target.pid != pid { self.drag.cancel() }
            if let target = self.reserveTarget, target.pid != pid { self.reservePermit?.cancel() }
            if let pid { self.dirtyApplications.insert(pid) }
            self.fastPollUntil = ProcessInfo.processInfo.systemUptime + 0.3
            self.requestMetadata()
        }
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { [weak self] _ in self?.transition() }
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { [weak self] _ in self?.transition() }
        observe(workspace, NSWorkspace.willSleepNotification) { [weak self] _ in self?.sleeping = true; self?.suspend() }
        observe(workspace, NSWorkspace.didWakeNotification) { [weak self] _ in self?.sleeping = false; self?.transition() }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { [weak self] _ in
            self?.inactiveSession = true; self?.suspend()
        }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] _ in
            self?.inactiveSession = false; self?.transition()
        }
    }
    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastPermissionCheck > 1 {
            lastPermissionCheck = now
            trusted = AXIsProcessTrusted()
        }
        let shouldRun = enabled && trusted && server.exactIdentity && !sleeping && !inactiveSession
        if !shouldRun {
            if running { suspend() }
            updateStatusLine()
            return
        }
        if !running { running = true; lastApplicationsRefresh = 0 }
        if now - lastApplicationsRefresh > 2 { refreshApplications(); lastApplicationsRefresh = now }
        // A held mouse button may be a native move/resize of any window; a header drag moves one through AX.
        // Both keep the per-frame tracker and the fast metadata poll on, plus a short tail after release
        // so the final position (and any snap the app applies afterwards) is caught without delay.
        if NSEvent.pressedMouseButtons != 0 || drag.target != nil { interactionUntil = now + 0.3 }
        let interacting = now < interactionUntil
        for (pid, state) in workers where !state.scanning {
            // Every move raises AXMoved and marks the application dirty. During an interaction the scan
            // (titles, focus, sheets) is not urgent, and for the header-drag target it would sit on the same
            // serial AX queue as the move steps, delaying each step behind a whole window read.
            let dirty = dirtyApplications.contains(pid) && drag.target?.pid != pid
            let dirtyInterval = interacting ? 0.3 : 0.08
            if (dirty && now - state.lastScan > dirtyInterval) || now - state.lastScan > 1.5 { scan(pid: pid) }
        }
        if interacting != tracker.isRunning { interacting ? tracker.start() : tracker.stop() }
        let interval = interacting || now < fastPollUntil ? 0.05 : 0.5
        if now - lastMetadataRequest >= interval { requestMetadata() }
        extraPermits.removeAll { !$0.isValid() }
    }
    private func refreshApplications() {
        let denied = excluded.union(["com.apple.loginwindow", "com.apple.SecurityAgent"])
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.processIdentifier != ownPID && $0.activationPolicy == .regular && !$0.isTerminated &&
            !denied.contains($0.bundleIdentifier ?? "")
        }
        let pids = Set(apps.map(\.processIdentifier))
        for pid in Array(workers.keys) where !pids.contains(pid) { retire(pid) }
        for app in apps {
            let pid = app.processIdentifier
            if let state = workers[pid], state.worker.descriptor.launchDate != app.launchDate { retire(pid) }
            guard workers[pid] == nil else { continue }
            let descriptor = ApplicationDescriptor(instance: UUID(), pid: pid,
                name: app.localizedName ?? "Application", bundleIdentifier: app.bundleIdentifier, launchDate: app.launchDate)
            let worker = AXAppWorker(descriptor: descriptor)
            workers[pid] = WorkerState(worker: worker, icon: app.icon)
            if let observer = AXObserverHub.shared.add(pid: pid) { worker.installObserver(observer) }
            dirtyApplications.insert(pid)
        }
    }
    private func retire(_ pid: Int32) {
        guard let state = workers.removeValue(forKey: pid) else { return }
        state.worker.stop()
        AXObserverHub.shared.remove(pid: pid)
        dirtyApplications.remove(pid)
        for token in Array(panels.keys) where token.pid == pid { removePanel(token) }
        if menus.target?.pid == pid { menus.cancel() }
        if drag.target?.pid == pid { drag.cancel() }
        if reserveTarget?.pid == pid { reservePermit?.cancel() }
    }
    private func scan(pid: Int32) {
        guard let state = workers[pid], !state.scanning else { return }
        state.scanning = true
        state.lastScan = ProcessInfo.processInfo.systemUptime
        dirtyApplications.remove(pid)
        state.worker.scan { [weak self, weak state] result in
            guard let self, let state, self.workers[pid] === state, self.running else { return }
            state.scanning = false
            switch result {
            case .success(let scan):
                guard scan.instance == state.worker.descriptor.instance else { return }
                state.snapshots = scan.windows
                state.hidden = scan.hidden
                state.failed = false
            case .failure:
                state.failed = true // hide, do not interpret an AX failure as a mass close
            }
            self.render()
        }
    }
    private func requestMetadata() {
        guard running else { return }
        lastMetadataRequest = ProcessInfo.processInfo.systemUptime
        let own = Set(panels.values.compactMap { UInt32(exactly: $0.windowNumber) })
        metadata = server.read(own: (pid: ownPID, windows: own))
        render()
    }
    /// Windows whose bounds are polled several times per frame during an interaction: the frontmost
    /// application's windows (a native move/resize goes to the clicked window, which activates its
    /// application) and the current header-drag target. The query cost grows with the count, so headers of
    /// background applications stay on the regular metadata cadence (a Cmd-drag of a background window
    /// is followed at that cadence, as before).
    private func trackedWindowIDs() -> [UInt32] {
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? lastFrontmostPID
        var ids: [UInt32] = []
        for (token, panel) in panels where panel.isVisible && (token.pid == frontmost || token == drag.target) {
            ids.append(token.windowID)
        }
        return ids
    }
    /// Per-frame path while the user is moving or resizing: only repositions headers that are already
    /// shown, using the same placement rules as `render`. Eligibility, ordering and focus are NOT decided
    /// here; the regular metadata pass keeps doing that at its own cadence and hides what must be hidden.
    private func follow(_ frames: [UInt32: Rect]) {
        let now = ProcessInfo.processInfo.systemUptime
        guard running, now >= quarantineUntil else { return }
        var geometry: ScreenGeometry?
        for (token, panel) in panels {
            guard panel.isVisible, let frame = frames[token.windowID], let previous = panel.targetFrame,
                  !previous.approximatelyEquals(frame, tolerance: 0.25) else { continue }
            if geometry == nil { geometry = ScreenGeometry.current() }
            guard let geometry else { return }
            panel.targetFrame = frame
            panel.followedAt = now
            if menus.target == token { menus.cancel() }
            guard Geometry.isEligibleSize(frame),
                  let screen = Geometry.bestScreen(for: frame, visibleFrames: geometry.visibleFrames),
                  let external = Geometry.externalHeader(for: frame, in: screen) else {
                panel.hide()
                continue
            }
            panel.globalHeaderFrame = external
            let desired = geometry.appKit(Geometry.panelFrame(forHeader: external))
            let resized = abs(desired.width - panel.frame.width) > 0.25 || abs(desired.height - panel.frame.height) > 0.25
            if resized { panel.setFrame(desired, display: true) } else { panel.setFrameOrigin(desired.origin) }
        }
    }
    private func transition() {
        quarantineUntil = ProcessInfo.processInfo.systemUptime + 0.45
        menus.cancel(); drag.cancel(); reservePermit?.cancel()
        panels.values.forEach { $0.hide() }
        metadata = nil
        dirtyApplications.formUnion(workers.keys)
        requestMetadata()
    }
    private func suspend() {
        running = false
        tracker.stop()
        menus.cancel(); drag.cancel(); reservePermit?.cancel()
        extraPermits.forEach { $0.cancel() }; extraPermits.removeAll()
        for pid in Array(workers.keys) { retire(pid) }
        panels.values.forEach { $0.close() }; panels.removeAll()
        metadata = nil
        AXObserverHub.shared.removeAll()
    }
    private func worker(for token: WindowToken) -> AXAppWorker? {
        guard let worker = workers[token.pid]?.worker, worker.descriptor.instance == token.processInstance else { return nil }
        return worker
    }
    private func snapshot(for token: WindowToken) -> WindowSnapshot? {
        workers[token.pid]?.snapshots.first(where: { $0.token == token })
    }
    private func valid(_ token: WindowToken) -> Bool {
        guard running, enabled, trusted, let state = workers[token.pid], !state.failed,
              !state.hidden.contains(token), let snapshot = snapshot(for: token),
              snapshot.eligible, !snapshot.modal, !snapshot.minimized, !snapshot.fullscreen,
              ProcessInfo.processInfo.systemUptime - snapshot.observedAt < 4,
              let serverWindow = metadata?.byID[token.windowID], serverWindow.pid == token.pid,
              serverWindow.layer == 0, serverWindow.alpha > 0 else { return false }
        return state.worker.descriptor.instance == token.processInstance
    }
    private func render() {
        let now = ProcessInfo.processInfo.systemUptime
        guard running, now >= quarantineUntil, let metadata, now - metadata.readAt < 2,
              let geometry = ScreenGeometry.current() else {
            panels.values.forEach { $0.hide() }
            return
        }
        let byID = metadata.byID
        let ordering = metadata.ordering
        let current = NSWorkspace.shared.frontmostApplication?.processIdentifier
        lastFrontmostPID = current
        let snapshots = workers.values.flatMap(\.snapshots)
        let known = Set(snapshots.map(\.token))
        for token in Array(panels.keys) where !known.contains(token) { removePanel(token) }
        for snapshot in snapshots {
            let token = snapshot.token
            // While the per-frame tracker is on, its reading of this window is newer than this snapshot:
            // placing from the snapshot would pull the header back to a stale position for one frame.
            let followed = panels[token].flatMap { $0.followedAt > metadata.readAt ? $0.targetFrame : nil }
            guard valid(token), let target = byID[token.windowID],
                  // The on-screen frame must ALSO be a real window: Stage Manager strip thumbnails keep the
                  // AX frame at full size while the CG frame shrinks to ~100pt (observed on macOS 26).
                  case let frame = followed ?? target.frame,
                  Geometry.isEligibleSize(frame),
                  !geometry.fullFrames.contains(where: { $0.approximatelyEquals(frame, tolerance: 1) }),
                  let screen = Geometry.bestScreen(for: frame, visibleFrames: geometry.visibleFrames),
                  let external = Geometry.externalHeader(for: frame, in: screen) else {
                panels[token]?.hide()
                menus.cancel(ifTarget: token)
                continue
            }
            let panel: HeaderPanel
            if let existing = panels[token] { panel = existing }
            else {
                panel = makePanel(token)
                panels[token] = panel
            }
            if let menuTarget = menus.target, menuTarget == token, let previous = panel.targetFrame,
               !previous.approximatelyEquals(frame, tolerance: 1) { menus.cancel() }
            panel.targetFrame = frame
            panel.globalHeaderFrame = external
            // The panel is taller than the header: an opaque backfill band that runs on behind the target and
            // shows only through its rounded corners. It is safe only while the target is in front of it.
            let panelFrame = Geometry.panelFrame(forHeader: external)
            let desired = geometry.appKit(panelFrame)
            if !Rect(panel.frame).approximatelyEquals(Rect(desired), tolerance: 0.25) { panel.setFrame(desired, display: true) }
            let focused = snapshot.focused && current == token.pid
            if panel.renderedAt != snapshot.observedAt || panel.renderedFocused != focused {
                panel.headerView.update(snapshot, icon: workers[token.pid]?.icon, focused: focused)
                panel.renderedAt = snapshot.observedAt
                panel.renderedFocused = focused
            }
            let panelID = UInt32(exactly: panel.windowNumber) ?? 0
            let safe = OrderingPolicy.isDirectlyBehind(headerID: panelID, targetID: token.windowID,
                ownPID: ownPID, headerFrame: panelFrame, frontToBack: ordering)
            if safe, panel.isVisible {
                if panel.alphaValue < 1 { logger.debug("reveal panel=\(panelID, privacy: .public) target=\(token.windowID, privacy: .public) unsafeCount=\(panel.unsafeCount, privacy: .public)") }
                panel.unsafeCount = 0
                panel.reveal()
            } else {
                if panel.alphaValue >= 1 { logger.debug("conceal panel=\(panelID, privacy: .public) target=\(token.windowID, privacy: .public) safe=\(safe, privacy: .public) visible=\(panel.isVisible, privacy: .public)") }
                panel.probe()
                if now - panel.orderRequestedAt > 0.12 {
                    panel.orderRequestedAt = now
                    panel.unsafeCount += 1
                    // Confirm the new order at the fast cadence so the header is back within about a frame
                    // or two instead of waiting for the idle poll. Bounded: a header that keeps failing
                    // the check (covered by a foreign window) drops back to the idle cadence.
                    if panel.unsafeCount <= 2 { fastPollUntil = max(fastPollUntil, now + 0.15) }
                    logger.debug("order panel=\(panelID, privacy: .public) behind=\(token.windowID, privacy: .public) unsafeCount=\(panel.unsafeCount, privacy: .public)")
                    if !server.order(panel, behind: token.windowID) { panel.hide() }
                }
            }
        }
        if let target = menus.target, !valid(target) { menus.cancel() }
        updateStatusLine()
    }
    private func makePanel(_ token: WindowToken) -> HeaderPanel {
        let panel = HeaderPanel(token: token)
        panel.headerView.setAppearance(accent: accentColor, base: baseColor,
                                       fill: fillWhenFocused, lineWidth: CGFloat(lineWidth))
        panel.headerView.onMenu = { [weak self, weak panel] headings, anchor in
            guard let self, let panel else { return }
            self.drag.cancel()
            self.menus.request(target: token, headings: headings, panel: panel, anchor: anchor)
        }
        panel.headerView.onActivate = { [weak self] in self?.activate(token) }
        panel.headerView.onDragBegan = { [weak self, weak panel] in
            guard let self, let panel, self.valid(token), let worker = self.worker(for: token), let frame = panel.targetFrame else { return }
            self.menus.cancel()
            self.drag.begin(token: token, worker: worker, frame: frame)
        }
        panel.headerView.onDragMoved = { [weak self] in self?.drag.moved() }
        panel.headerView.onDragEnded = { [weak self] in self?.drag.ended() }
        panel.headerView.onMinimize = { [weak self] in self?.pressWindowButton(token, attribute: "AXMinimizeButton") }
        panel.headerView.onClose = { [weak self] in self?.pressWindowButton(token, attribute: "AXCloseButton") }
        panel.headerView.onMaximize = { [weak self] in self?.toggleMaximize(token) }
        return panel
    }
    /// Minimize / close through the window's own standard button. Only the exact window can be hit; the
    /// request is sent once and never retried (a close may be answered by the app's own save dialog).
    private func pressWindowButton(_ token: WindowToken, attribute: String) {
        guard valid(token), let worker = worker(for: token) else { return }
        menus.cancel(); drag.cancel()
        let permit = OperationPermit(lifetime: 3)
        extraPermits.append(permit)
        worker.pressWindowButton(token, attribute: attribute, permit: permit) { [weak self] result in
            permit.cancel()
            guard let self else { return }
            if case .failure(let error) = result { self.status(error.localizedDescription) }
            self.dirtyApplications.insert(token.pid)
            self.fastPollUntil = ProcessInfo.processInfo.systemUptime + 0.3
            self.requestMetadata()
        }
    }
    /// Windows-style maximize: fill the usable screen area below the header; pressing again restores the
    /// frame recorded here. This is the explicit user command that authorizes moving/resizing this window.
    private func toggleMaximize(_ token: WindowToken) {
        guard valid(token), let worker = worker(for: token),
              let actual = metadata?.byID[token.windowID]?.frame,
              let geometry = ScreenGeometry.current(),
              let screen = Geometry.bestScreen(for: actual, visibleFrames: geometry.visibleFrames),
              let maximized = Geometry.maximizedFrame(in: screen) else {
            status(NSLocalizedString("このウィンドウは最大化できません。",
                                      comment: "Status: the target window can't be maximized"))
            return
        }
        menus.cancel(); drag.cancel(); reservePermit?.cancel()
        let restoring = actual.approximatelyEquals(maximized, tolerance: 2)
        guard let desired = restoring ? restoreFrames[token] : maximized else {
            status(NSLocalizedString("元のサイズが記録されていないため戻せません。ドラッグで調整してください。",
                                      comment: "Status: no recorded size to restore to"))
            return
        }
        let permit = OperationPermit(lifetime: 5)
        reservePermit = permit; reserveTarget = token
        _ = NSRunningApplication(processIdentifier: token.pid)?.activate() // best effort; focus() verifies
        worker.focus(token, permit: permit) { [weak self] focusResult in
            guard let self, permit.isValid() else { return }
            if case .failure(let error) = focusResult { self.status(error.localizedDescription); permit.cancel(); return }
            worker.reserve(token, expected: actual, desired: desired, permit: permit) { [weak self] result in
                guard let self else { return }
                permit.cancel()
                self.reserveTarget = nil
                switch result {
                case .success:
                    if restoring { self.restoreFrames[token] = nil } else { self.restoreFrames[token] = actual }
                    self.status(restoring
                        ? NSLocalizedString("元のサイズに戻しました。", comment: "Status: window restored to its original size")
                        : NSLocalizedString("最大化しました。", comment: "Status: window maximized"))
                case .failure(let error): self.status(error.localizedDescription)
                }
                self.dirtyApplications.insert(token.pid)
                self.fastPollUntil = ProcessInfo.processInfo.systemUptime + 0.3
                self.requestMetadata()
            }
        }
    }
    private func removePanel(_ token: WindowToken) {
        menus.cancel(ifTarget: token)
        if drag.target == token { drag.cancel() }
        panels.removeValue(forKey: token)?.close()
        restoreFrames[token] = nil
    }
    private func activate(_ token: WindowToken) {
        guard valid(token), let worker = worker(for: token) else { return }
        let permit = OperationPermit(lifetime: 3)
        extraPermits.append(permit)
        _ = NSRunningApplication(processIdentifier: token.pid)?.activate() // best effort; focus() verifies
        worker.focus(token, permit: permit) { [weak self] result in
            if case .failure(let error) = result { self?.status(error.localizedDescription) }
            permit.cancel()
        }
    }
    private func createStatusMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "TR"
        let menu = NSMenu()
        menu.autoenablesItems = false
        statusLine = NSMenuItem(title: "Transom", action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())
        func item(_ title: String, _ selector: Selector) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self; menu.addItem(item); return item
        }
        toggleItem = item(NSLocalizedString("外付けバーを有効にする", comment: "Menu item: toggles the external bar on/off"), #selector(toggle))
        _ = item(NSLocalizedString("最前面の1枚にバー用の空間を確保", comment: "Menu item: reserve bar space on the frontmost window"), #selector(reserveFocused))
        _ = item(NSLocalizedString("最前面のアプリを除外", comment: "Menu item: exclude the frontmost app"), #selector(excludeFocusedApplication))
        _ = item(NSLocalizedString("除外設定をすべて解除", comment: "Menu item: clear all app exclusions"), #selector(clearExclusions))
        let appearance = NSMenuItem(title: NSLocalizedString("アクティブ時のバー", comment: "Menu: appearance of the bar on the focused window"), action: nil, keyEquivalent: "")
        let appearanceMenu = NSMenu()
        appearanceMenu.autoenablesItems = false
        func sub(_ title: String, _ selector: Selector) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            i.target = self; appearanceMenu.addItem(i); return i
        }
        systemAccentItem = sub(NSLocalizedString("システムアクセントに合わせる", comment: "Menu item: use the system accent color"), #selector(useSystemAccent))
        _ = sub(NSLocalizedString("色を選択…", comment: "Menu item: pick a custom color for the active bar"), #selector(chooseAccentColor))
        appearanceMenu.addItem(.separator())
        lineStyleItem = sub(NSLocalizedString("上端ライン", comment: "Menu item: mark the active bar with a thin top line"), #selector(useLineStyle))
        fillStyleItem = sub(NSLocalizedString("バー全体", comment: "Menu item: paint the whole active bar"), #selector(useFillStyle))
        let thickness = NSMenuItem(title: NSLocalizedString("ラインの太さ", comment: "Menu: thickness of the active bar's top line"), action: nil, keyEquivalent: "")
        let thicknessMenu = NSMenu()
        thicknessMenu.autoenablesItems = false
        for width in 0...5 {
            let i = NSMenuItem(title: width == 0
                ? NSLocalizedString("なし", comment: "Menu item: no top line on the active bar")
                : "\(width)px", action: #selector(setLineWidth(_:)), keyEquivalent: "")
            i.target = self; i.tag = width; thicknessMenu.addItem(i); lineWidthItems.append(i)
        }
        thickness.submenu = thicknessMenu
        appearanceMenu.addItem(thickness)
        appearance.submenu = appearanceMenu
        menu.addItem(appearance)
        appearanceItem = appearance
        let base = NSMenuItem(title: NSLocalizedString("バーの色", comment: "Menu: base colour of every bar"), action: nil, keyEquivalent: "")
        let baseMenu = NSMenu()
        baseMenu.autoenablesItems = false
        func baseSub(_ title: String, _ selector: Selector) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            i.target = self; baseMenu.addItem(i); return i
        }
        systemBaseItem = baseSub(NSLocalizedString("システム標準に合わせる", comment: "Menu item: use the system window background for bars"), #selector(useSystemBase))
        _ = baseSub(NSLocalizedString("色を選択…", comment: "Menu item: pick a custom colour for all bars"), #selector(chooseBaseColor))
        base.submenu = baseMenu
        menu.addItem(base)
        baseColorItem = base
        menu.addItem(.separator())
        _ = item(NSLocalizedString("アクセシビリティの許可を確認", comment: "Menu item: check accessibility permission"), #selector(requestPermission))
        _ = item(NSLocalizedString("アクセシビリティ設定を開く", comment: "Menu item: open Accessibility settings"), #selector(openAccessibilitySettings))
        _ = item(NSLocalizedString("診断情報をコピー（文書名を含まない）", comment: "Menu item: copy diagnostics without document names"), #selector(copyDiagnostics))
        menu.addItem(.separator())
        _ = item(NSLocalizedString("Transomを終了", comment: "Menu item: quit the app"), #selector(quit))
        statusItem.menu = menu
        updateAppearanceMenu()
    }
    @objc private func useSystemAccent() {
        accentColor = nil
        UserDefaults.standard.removeObject(forKey: "activeBarColor")
        applyAppearance()
    }
    @objc private func chooseAccentColor() {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.setTarget(self)
        panel.setAction(#selector(accentColorChanged(_:)))
        panel.color = accentColor ?? .controlAccentColor
        NSApp.activate()
        panel.orderFront(nil)
        panel.makeKey()
    }
    @objc private func accentColorChanged(_ sender: NSColorPanel) {
        accentColor = sender.color
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: sender.color, requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: "activeBarColor")
        }
        applyAppearance()
    }
    @objc private func useLineStyle() { setBarFill(false) }
    @objc private func useFillStyle() { setBarFill(true) }
    private func setBarFill(_ fill: Bool) {
        fillWhenFocused = fill
        UserDefaults.standard.set(fill, forKey: "activeBarFill")
        applyAppearance()
    }
    @objc private func setLineWidth(_ sender: NSMenuItem) {
        lineWidth = sender.tag
        UserDefaults.standard.set(lineWidth, forKey: "activeBarLineWidth")
        applyAppearance()
    }
    @objc private func useSystemBase() {
        baseColor = nil
        UserDefaults.standard.removeObject(forKey: "barBaseColor")
        applyAppearance()
    }
    @objc private func chooseBaseColor() {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.setTarget(self)
        panel.setAction(#selector(baseColorChanged(_:)))
        panel.color = baseColor ?? .windowBackgroundColor
        NSApp.activate()
        panel.orderFront(nil)
        panel.makeKey()
    }
    @objc private func baseColorChanged(_ sender: NSColorPanel) {
        baseColor = sender.color
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: sender.color, requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: "barBaseColor")
        }
        applyAppearance()
    }
    private func applyAppearance() {
        for panel in panels.values {
            panel.headerView.setAppearance(accent: accentColor, base: baseColor,
                                           fill: fillWhenFocused, lineWidth: CGFloat(lineWidth))
        }
        updateAppearanceMenu()
    }
    private func updateAppearanceMenu() {
        guard systemAccentItem != nil else { return }
        systemAccentItem.state = accentColor == nil ? .on : .off
        lineStyleItem.state = fillWhenFocused ? .off : .on
        fillStyleItem.state = fillWhenFocused ? .on : .off
        for item in lineWidthItems { item.state = item.tag == lineWidth ? .on : .off }
        appearanceItem?.image = swatch(accentColor ?? .controlAccentColor)
        systemBaseItem.state = baseColor == nil ? .on : .off
        baseColorItem?.image = swatch(baseColor ?? .windowBackgroundColor)
    }
    private func swatch(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
            (color.usingColorSpace(.sRGB) ?? color).setFill()
            path.fill()
            NSColor.separatorColor.setStroke()
            path.lineWidth = 1
            path.stroke()
            return true
        }
    }
    private func status(_ message: String) {
        if lastMessage != message { logger.info("\(message, privacy: .public)") }
        lastMessage = message
        updateStatusLine()
    }
    private func updateStatusLine() {
        guard statusItem != nil else { return }
        toggleItem.state = enabled ? .on : .off
        let visible = panels.values.filter { $0.isVisible && $0.alphaValue > 0.9 }.count
        let tracked = workers.values.reduce(0) { $0 + $1.snapshots.filter(\.eligible).count }
        let state = !enabled ? NSLocalizedString("停止中", comment: "State: disabled")
            : !trusted ? NSLocalizedString("権限待ち", comment: "State: awaiting accessibility permission")
            : !server.exactIdentity ? NSLocalizedString("ID取得非対応", comment: "State: exact window ID unsupported")
            : String(format: NSLocalizedString("%d/%d 枚表示", comment: "State: visible/tracked window count, e.g. 2/3 shown"), visible, tracked)
        statusLine.title = "Transom 0.1 — \(state)"
        statusItem.button?.toolTip = "\(state)\n\(lastMessage)"
    }
    @objc private func toggle() {
        enabled.toggle()
        UserDefaults.standard.set(enabled, forKey: "enabled")
        if !enabled { suspend() }
        else if !AXIsProcessTrusted() { requestPermission() }
        tick()
    }
    @objc private func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        trusted = AXIsProcessTrustedWithOptions(options)
        status(trusted
            ? NSLocalizedString("アクセシビリティは許可されています。", comment: "Status: accessibility permission granted")
            : NSLocalizedString("システム設定でTransomのアクセシビリティを許可してください。", comment: "Status: prompts the user to grant accessibility permission"))
    }
    @objc private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
    private func focusedCandidate() -> WindowSnapshot? {
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? lastFrontmostPID
        return workers.values.flatMap(\.snapshots).first { $0.token.pid == pid && $0.focused && valid($0.token) }
    }
    @objc private func reserveFocused() {
        menus.cancel(); drag.cancel(); reservePermit?.cancel()
        guard let snapshot = focusedCandidate(), let worker = worker(for: snapshot.token),
              let actual = metadata?.byID[snapshot.token.windowID]?.frame,
              let geometry = ScreenGeometry.current(),
              let screen = Geometry.bestScreen(for: actual, visibleFrames: geometry.visibleFrames),
              let desired = Geometry.reserveSpace(for: actual, in: screen) else {
            status(NSLocalizedString("空間を確保できる通常ウィンドウを選択してください。",
                                      comment: "Status: no eligible window to reserve space on"))
            return
        }
        if actual.approximatelyEquals(desired) {
            status(NSLocalizedString("このウィンドウには既に空間があります。位置は変更しませんでした。",
                                      comment: "Status: window already has reserved space"))
            return
        }
        let permit = OperationPermit(lifetime: 5)
        reservePermit = permit; reserveTarget = snapshot.token
        // This menu item is the explicit authorization to move/resize this one window.
        worker.reserve(snapshot.token, expected: actual, desired: desired, permit: permit) { [weak self] result in
            guard let self else { return }
            permit.cancel()
            self.reserveTarget = nil
            switch result {
            case .success:
                self.status(NSLocalizedString("最前面の1枚にバー用の空間を確保しました。",
                                               comment: "Status: reserved bar space on the frontmost window"))
            case .failure(let error): self.status(error.localizedDescription)
            }
            self.dirtyApplications.insert(snapshot.token.pid)
            self.requestMetadata()
        }
    }
    @objc private func excludeFocusedApplication() {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ownPID,
              let bundle = app.bundleIdentifier else { return }
        var values = excluded
        values.insert(bundle)
        UserDefaults.standard.set(Array(values).sorted(), forKey: "excludedBundleIDs")
        retire(app.processIdentifier)
        status(NSLocalizedString("最前面のアプリを除外しました。", comment: "Status: excluded the frontmost app"))
    }
    @objc private func clearExclusions() {
        UserDefaults.standard.removeObject(forKey: "excludedBundleIDs")
        lastApplicationsRefresh = 0
        status(NSLocalizedString("除外設定を解除しました。", comment: "Status: cleared the app exclusions"))
    }
    @objc private func copyDiagnostics() {
        let info: [String: Any] = [
            "version": "0.1.0-dev", "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "enabled": enabled, "accessibilityTrusted": trusted,
            "exactWindowIDAvailable": server.exactIdentity, "privateOrderingAvailable": server.privateOrdering,
            "privateOrderingLastCode": server.lastPrivateOrderCode, "privateOrderingLastCGError": server.lastPrivateCGError,
            "privateOrderingFailures": server.privateOrderFailures, "privateOrderingDisabled": server.privateOrderingDisabled,
            "applicationCount": workers.count, "trackedWindowCount": workers.values.reduce(0) { $0 + $1.snapshots.count },
            "visibleHeaderCount": panels.values.filter { $0.alphaValue > 0.9 && $0.isVisible }.count,
            "orderingQuarantinedCount": panels.values.filter { $0.unsafeCount > 2 }.count,
            "screenCount": NSScreen.screens.count,
            "privacy": "No window titles, document URLs, menu titles, clipboard content or screenshots included."
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        status(NSLocalizedString("文書名を含まない診断情報をコピーしました。", comment: "Status: copied diagnostics without document names"))
    }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
