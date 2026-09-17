import AppKit
import ApplicationServices
import OSLog
import WindowBarCore

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
    private let logger = Logger(subsystem: "dev.local.WindowBar", category: "runtime")
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
    private var lastMessage = "準備中"
    private var currentEpoch = UUID()
    private var dirtyApplications = Set<Int32>()
    private var reservePermit: OperationPermit?
    private var reserveTarget: WindowToken?
    private var extraPermits: [OperationPermit] = []
    private var lastFrontmostPID: Int32?
    private let ownPID = Int32(ProcessInfo.processInfo.processIdentifier)
    private var excluded: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: "excludedBundleIDs") ?? [])
    }

    func start() {
        precondition(Thread.isMainThread)
        UserDefaults.standard.register(defaults: ["enabled": true])
        enabled = UserDefaults.standard.bool(forKey: "enabled")
        createStatusMenu()
        menus.workerFor = { [weak self] token in self?.worker(for: token) }
        menus.isTargetValid = { [weak self] token in self?.valid(token) ?? false }
        menus.onStatus = { [weak self] message in self?.status(message) }
        drag.onStatus = { [weak self] message in self?.status(message) }
        drag.onMoved = { [weak self] token, _ in self?.dirtyApplications.insert(token.pid); self?.requestMetadata() }
        AXObserverHub.shared.onChange = { [weak self] pid in self?.dirtyApplications.insert(pid) }
        observeWorkspace()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        trusted = AXIsProcessTrusted()
        if !trusted && enabled { requestPermission() }
        if !server.exactIdentity { status("正確なウィンドウID APIが使えないため、表示を停止しています。") }
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
        if !running { running = true; currentEpoch = UUID(); lastApplicationsRefresh = 0 }
        if now - lastApplicationsRefresh > 2 { refreshApplications(); lastApplicationsRefresh = now }
        for (pid, state) in workers where !state.scanning {
            let dirty = dirtyApplications.contains(pid)
            if (dirty && now - state.lastScan > 0.08) || now - state.lastScan > 1.5 { scan(pid: pid) }
        }
        let interval = NSEvent.pressedMouseButtons != 0 || drag.target != nil ? 0.05 : 0.5
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
        let epoch = currentEpoch
        server.read { [weak self] snapshot in
            guard let self, self.running, epoch == self.currentEpoch else { return }
            self.metadata = snapshot
            self.render()
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
        currentEpoch = UUID()
        running = false
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
            guard valid(token), let target = byID[token.windowID],
                  // The on-screen frame must ALSO be a real window: Stage Manager strip thumbnails keep the
                  // AX frame at full size while the CG frame shrinks to ~100pt (observed on macOS 26).
                  Geometry.isEligibleSize(target.frame),
                  !geometry.fullFrames.contains(where: { $0.approximatelyEquals(target.frame, tolerance: 1) }),
                  let screen = Geometry.bestScreen(for: target.frame, visibleFrames: geometry.visibleFrames),
                  let external = Geometry.externalHeader(for: target.frame, in: screen) else {
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
               !previous.approximatelyEquals(target.frame, tolerance: 1) { menus.cancel() }
            panel.targetFrame = target.frame
            panel.globalHeaderFrame = external
            let desired = geometry.appKit(external)
            if !Rect(panel.frame).approximatelyEquals(Rect(desired), tolerance: 0.25) { panel.setFrame(desired, display: true) }
            let focused = snapshot.focused && current == token.pid
            if panel.renderedAt != snapshot.observedAt || panel.renderedFocused != focused {
                panel.headerView.update(snapshot, icon: workers[token.pid]?.icon, focused: focused)
                panel.renderedAt = snapshot.observedAt
                panel.renderedFocused = focused
            }
            let panelID = UInt32(exactly: panel.windowNumber) ?? 0
            let safe = OrderingPolicy.isSafe(headerID: panelID, targetID: token.windowID,
                ownPID: ownPID, headerFrame: external, frontToBack: ordering)
            if safe, panel.isVisible {
                panel.unsafeCount = 0
                panel.reveal()
            } else {
                panel.probe()
                if now - panel.orderRequestedAt > 0.12 {
                    panel.orderRequestedAt = now
                    panel.unsafeCount += 1
                    let wasDisabled = server.privateOrderingDisabled
                    if !server.order(panel, above: token.windowID) { panel.hide() }
                    else if server.privateOrderingDisabled && !wasDisabled {
                        // Logged once, when the private path is first given up on. No per-frame spam.
                        let code = server.lastPrivateOrderCode, cgError = server.lastPrivateCGError
                        logger.info("非公開order経路がコード \(code, privacy: .public)（CGError \(cgError, privacy: .public)）で繰り返し失敗したため、以後は公開経路とメタデータ照合のみで並び順を確認します。")
                    }
                }
            }
        }
        if let target = menus.target, !valid(target) { menus.cancel() }
        updateStatusLine()
    }
    private func makePanel(_ token: WindowToken) -> HeaderPanel {
        let panel = HeaderPanel(token: token)
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
        return panel
    }
    private func removePanel(_ token: WindowToken) {
        menus.cancel(ifTarget: token)
        if drag.target == token { drag.cancel() }
        panels.removeValue(forKey: token)?.close()
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
        statusItem.button?.title = "WB"
        let menu = NSMenu()
        menu.autoenablesItems = false
        statusLine = NSMenuItem(title: "WindowBar", action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())
        func item(_ title: String, _ selector: Selector) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self; menu.addItem(item); return item
        }
        toggleItem = item("外付けバーを有効にする", #selector(toggle))
        _ = item("最前面の1枚にバー用の空間を確保", #selector(reserveFocused))
        _ = item("最前面のアプリを除外", #selector(excludeFocusedApplication))
        _ = item("除外設定をすべて解除", #selector(clearExclusions))
        menu.addItem(.separator())
        _ = item("アクセシビリティの許可を確認", #selector(requestPermission))
        _ = item("アクセシビリティ設定を開く", #selector(openAccessibilitySettings))
        _ = item("診断情報をコピー（文書名を含まない）", #selector(copyDiagnostics))
        menu.addItem(.separator())
        _ = item("WindowBarを終了", #selector(quit))
        statusItem.menu = menu
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
        let state = !enabled ? "停止中" : !trusted ? "権限待ち" : !server.exactIdentity ? "ID取得非対応" : "\(visible)/\(tracked) 枚表示"
        statusLine.title = "WindowBar 0.1 — \(state)"
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
        status(trusted ? "アクセシビリティは許可されています。" : "システム設定でWindowBarのアクセシビリティを許可してください。")
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
            status("空間を確保できる通常ウィンドウを選択してください。")
            return
        }
        if actual.approximatelyEquals(desired) { status("このウィンドウには既に空間があります。位置は変更しませんでした。"); return }
        let permit = OperationPermit(lifetime: 5)
        reservePermit = permit; reserveTarget = snapshot.token
        // This menu item is the explicit authorization to move/resize this one window.
        worker.reserve(snapshot.token, expected: actual, desired: desired, permit: permit) { [weak self] result in
            guard let self else { return }
            permit.cancel()
            self.reserveTarget = nil
            switch result {
            case .success: self.status("最前面の1枚にバー用の空間を確保しました。")
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
        status("最前面のアプリを除外しました。")
    }
    @objc private func clearExclusions() {
        UserDefaults.standard.removeObject(forKey: "excludedBundleIDs")
        lastApplicationsRefresh = 0
        status("除外設定を解除しました。")
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
        status("文書名を含まない診断情報をコピーしました。")
    }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
