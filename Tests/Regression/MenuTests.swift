
extension Rect {
    init(_ frame: CGRect) {
        self.init(x: Double(frame.minX), y: Double(frame.minY), width: Double(frame.width), height: Double(frame.height))
    }
}

@MainActor final class FixtureHeaderView {
    func convert(_ point: NSPoint, to view: Any?) -> NSPoint { point }
}

@MainActor final class HeaderPanel: NSObject {
    var frame = CGRect(x: 100, y: 100, width: 500, height: 30)
    let headerView = FixtureHeaderView()
    func convertPoint(toScreen point: NSPoint) -> NSPoint { point }
}

@MainActor final class FixtureRunningApplication {
    static var availablePID: Int32 = 123
    let processIdentifier: Int32
    let isTerminated = false
    init?(processIdentifier: Int32) {
        guard processIdentifier == Self.availablePID else { return nil }
        self.processIdentifier = processIdentifier
    }
    func activate() -> Bool { true }
}

@MainActor final class FixtureWorkspace {
    static let shared = FixtureWorkspace()
    var frontmostApplication: FixtureRunningApplication?
}

@MainActor final class FixtureMenuItem: NSObject {
    let title: String
    let keyEquivalent: String
    var isEnabled = true
    var state: NSControl.StateValue = .off
    var submenu: FixtureMenu?
    var target: NSObject?
    var action: Selector?
    var representedObject: Any?
    var isSeparatorItem = false
    init(title: String, action: Selector?, keyEquivalent: String) {
        self.title = title
        self.action = action
        self.keyEquivalent = keyEquivalent
    }
    static func separator() -> FixtureMenuItem {
        let item = FixtureMenuItem(title: "", action: nil, keyEquivalent: "")
        item.isSeparatorItem = true
        return item
    }
    func select() {
        guard isEnabled, let action, let target else { return }
        _ = target.perform(action, with: self)
    }
}

@MainActor final class FixtureMenu {
    static var onPopup: ((FixtureMenu) -> Void)?
    var autoenablesItems = true
    var font: NSFont?
    private(set) var items: [FixtureMenuItem] = []
    private(set) var cancelled = false
    func addItem(_ item: FixtureMenuItem) { items.append(item) }
    func popUp(positioning: FixtureMenuItem?, at point: NSPoint, in view: Any?) {
        Self.onPopup?(self)
    }
    func cancelTrackingWithoutAnimation() { cancelled = true }
}

@MainActor final class AXAppWorker {
    var focusCalls: [(WindowToken, OperationPermit, (Result<Void, Error>) -> Void)] = []
    var prepareCalls: [(WindowToken, [MenuHeading], OperationPermit, (Result<PreparedMenu, Error>) -> Void)] = []
    var executeCalls: [(UUID, UUID, (Result<Void, Error>) -> Void)] = []
    var discarded: [UUID] = []
    func focus(_ token: WindowToken, permit: OperationPermit,
               completion: @escaping @MainActor (Result<Void, Error>) -> Void) {
        focusCalls.append((token, permit, completion))
    }
    func prepareMenu(for token: WindowToken, headings: [MenuHeading], permit: OperationPermit,
                     completion: @escaping @MainActor (Result<PreparedMenu, Error>) -> Void) {
        prepareCalls.append((token, headings, permit, completion))
    }
    func execute(sessionID: UUID, commandID: UUID,
                 completion: @escaping @MainActor (Result<Void, Error>) -> Void) {
        executeCalls.append((sessionID, commandID, completion))
    }
    func discardMenu(_ sessionID: UUID) { discarded.append(sessionID) }
}

@MainActor private final class MenuHarness {
    let coordinator = MenuCoordinator()
    let worker = AXAppWorker()
    let panel = HeaderPanel()
    let processInstance = UUID()
    let heading = MenuHeading(index: 0, title: "App")
    init() {
        FixtureRunningApplication.availablePID = 123
        FixtureWorkspace.shared.frontmostApplication = FixtureRunningApplication(processIdentifier: 123)
        FixtureMenu.onPopup = nil
        coordinator.workerFor = { [weak self] _ in self?.worker }
        coordinator.isTargetValid = { _ in true }
    }
    func token(_ id: UInt32) -> WindowToken {
        WindowToken(processInstance: processInstance, pid: 123, windowID: id, incarnation: 1)
    }
    func request(_ token: WindowToken) {
        coordinator.request(target: token, headings: [heading], panel: panel, anchor: .zero)
    }
    func prepare(_ index: Int, token: WindowToken, entries: [MenuEntry]) -> UUID {
        let sessionID = UUID()
        worker.prepareCalls[index].3(.success(PreparedMenu(sessionID: sessionID, target: token,
                                                            entries: entries, truncated: false)))
        return sessionID
    }
}

@MainActor private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError("Menu regression: \(message)") }
}

@MainActor private func testSelectionExecutesAfterPopupDismissal() {
    let harness = MenuHarness()
    let token = harness.token(1)
    let command = UUID()
    harness.request(token)
    check(harness.worker.focusCalls.count == 1, "focus requested once")
    harness.worker.focusCalls[0].2(.success(()))
    check(harness.worker.prepareCalls.count == 1, "prepare follows focus")
    FixtureMenu.onPopup = { menu in
        check(harness.worker.executeCalls.isEmpty, "no execution during popup")
        menu.items[0].select()
        check(harness.worker.executeCalls.isEmpty, "selection waits for dismissal")
    }
    let sessionID = harness.prepare(0, token: token, entries: [MenuEntry(commandID: command, title: "Open", enabled: true)])
    check(harness.worker.executeCalls.count == 1, "one execution after dismissal")
    check(harness.worker.executeCalls[0].0 == sessionID && harness.worker.executeCalls[0].1 == command,
          "exact session and command")
    harness.worker.executeCalls[0].2(.success(()))
    check(harness.coordinator.target == nil, "completed request released")
}

@MainActor private func testDismissalAndContextChangesDiscard() {
    for reason in 0..<6 {
        let harness = MenuHarness()
        let token = harness.token(1)
        harness.request(token)
        harness.worker.focusCalls[0].2(.success(()))
        if reason == 1 { harness.coordinator.isTargetValid = { _ in false } }
        if reason == 2 { FixtureWorkspace.shared.frontmostApplication = nil }
        if reason == 3 { harness.panel.frame.origin.x += 3 }
        FixtureMenu.onPopup = { menu in
            guard reason != 0 else { return }
            menu.items[0].select()
            if reason == 1 { harness.coordinator.isTargetValid = { _ in true } }
            if reason == 2 {
                FixtureWorkspace.shared.frontmostApplication = FixtureRunningApplication(processIdentifier: 123)
            }
            if reason == 4 { harness.coordinator.isTargetValid = { _ in false } }
            if reason == 5 { FixtureWorkspace.shared.frontmostApplication = nil }
        }
        let sessionID = harness.prepare(0, token: token,
                                        entries: [MenuEntry(commandID: UUID(), title: "Open", enabled: true)])
        check(harness.worker.executeCalls.isEmpty, "context change or dismissal never executes: \(reason)")
        check(harness.worker.discarded == [sessionID], "session discarded: \(reason)")
        check(harness.coordinator.target == nil, "request cancelled: \(reason)")
    }
}

@MainActor private func testOldFocusAndPreparationCannotCorruptSuccessor() {
    let harness = MenuHarness()
    let old = harness.token(1)
    let successor = harness.token(2)
    harness.request(old)
    harness.request(successor)
    harness.worker.focusCalls[0].2(.success(()))
    check(harness.worker.prepareCalls.isEmpty, "stale focus ignored")
    check(harness.coordinator.target == successor, "successor target retained after old focus")
    harness.worker.focusCalls[1].2(.success(()))
    harness.request(old)
    let oldSession = harness.prepare(0, token: successor, entries: [])
    check(harness.worker.discarded == [oldSession], "late prepared session discarded")
    check(harness.coordinator.target == old, "new target retained after old preparation")
}

@MainActor private func testPopupStartsNewRequestWithoutClearingIt() {
    let harness = MenuHarness()
    let old = harness.token(1)
    let successor = harness.token(2)
    harness.request(old)
    harness.worker.focusCalls[0].2(.success(()))
    FixtureMenu.onPopup = { _ in harness.request(successor) }
    let oldSession = harness.prepare(0, token: old, entries: [])
    check(harness.worker.discarded == [oldSession], "old session discarded after nested request")
    check(harness.coordinator.target == successor, "nested target retained")
    check(harness.worker.focusCalls.count == 2, "nested focus remains pending")
    harness.worker.focusCalls[1].2(.success(()))
    check(harness.worker.prepareCalls.count == 2, "nested permit remains usable")
}

@MainActor private func testOldExecuteCompletionDoesNotCancelSuccessor() {
    let harness = MenuHarness()
    let old = harness.token(1)
    let successor = harness.token(2)
    harness.request(old)
    harness.worker.focusCalls[0].2(.success(()))
    FixtureMenu.onPopup = { $0.items[0].select() }
    _ = harness.prepare(0, token: old, entries: [MenuEntry(commandID: UUID(), title: "Open", enabled: true)])
    check(harness.worker.executeCalls.count == 1, "old command submitted")
    harness.request(successor)
    harness.worker.executeCalls[0].2(.success(()))
    check(harness.coordinator.target == successor, "late execute completion preserves successor")
    harness.worker.focusCalls[1].2(.success(()))
    check(harness.worker.prepareCalls.count == 2, "successor still prepares")
}

@MainActor private func testMenuSafetyAndNestedCommand() {
    let harness = MenuHarness()
    let token = harness.token(1)
    let disabled = UUID()
    let nested = UUID()
    let entries = [
        MenuEntry(commandID: disabled, title: "Disabled", enabled: false),
        MenuEntry(title: "Unexpanded", enabled: false),
        MenuEntry(title: "Parent", enabled: true, children: [MenuEntry(commandID: nested, title: "Child", enabled: true)]),
        MenuEntry(title: "", isSeparator: true),
        MenuEntry(title: "Mixed", enabled: true, mark: "–", shortcut: "⌘M"),
        MenuEntry(title: "Checked", enabled: true, mark: "✓")
    ]
    harness.request(token)
    harness.worker.focusCalls[0].2(.success(()))
    FixtureMenu.onPopup = { menu in
        check(!menu.autoenablesItems, "automatic enabling disabled")
        check(menu.items.count == 6, "all entries retained")
        check(!menu.items[0].isEnabled && menu.items[0].action == nil, "disabled command unbound")
        check(menu.items[1].action == nil, "notice unbound")
        check(menu.items[2].action == nil && menu.items[2].submenu?.items.count == 1, "parent submenu")
        check(menu.items[3].isSeparatorItem, "separator retained")
        check(menu.items[4].state == .mixed && menu.items[4].title == "Mixed    ⌘M", "mixed mark and inert shortcut")
        check(menu.items[4].keyEquivalent.isEmpty && menu.items[4].action == nil, "shortcut not rebound")
        check(menu.items[5].state == .on, "checked mark")
        menu.items[0].select()
        menu.items[1].select()
        menu.items[2].submenu?.items[0].select()
    }
    _ = harness.prepare(0, token: token, entries: entries)
    check(harness.worker.executeCalls.count == 1 && harness.worker.executeCalls[0].1 == nested,
          "only nested enabled command executes")
}

@main @MainActor struct MenuRegressionMain {
    static func main() {
        testSelectionExecutesAfterPopupDismissal()
        testDismissalAndContextChangesDiscard()
        testOldFocusAndPreparationCannotCorruptSuccessor()
        testPopupStartsNewRequestWithoutClearingIt()
        testOldExecuteCompletionDoesNotCancelSuccessor()
        testMenuSafetyAndNestedCommand()
        print("RESULT menu passed=6 total=6")
    }
}
