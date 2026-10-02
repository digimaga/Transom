import AppKit
import TransomCore

@MainActor
private final class MenuSelection: NSObject {
    var commandID: UUID?
    @objc func choose(_ sender: NSMenuItem) { commandID = sender.representedObject as? UUID }
}

/// Native popup menus provide tracking, Escape, keyboard navigation and accessibility.
/// This does not assume NSMenu is focus-safe: all AX context is revalidated AFTER dismissal.
@MainActor
final class MenuCoordinator {
    var workerFor: ((WindowToken) -> AXAppWorker?)?
    var isTargetValid: ((WindowToken) -> Bool)?
    var onStatus: ((String) -> Void)?
    private(set) var target: WindowToken?
    private var permit: OperationPermit?
    private var activeMenu: NSMenu?
    private var requestID = UUID()

    func cancel() {
        requestID = UUID()
        permit?.cancel()
        activeMenu?.cancelTrackingWithoutAnimation()
        activeMenu = nil
        permit = nil
        target = nil
    }
    func cancel(ifTarget token: WindowToken) { if target == token { cancel() } }

    func request(target: WindowToken, headings: [MenuHeading], panel: HeaderPanel, anchor: NSPoint) {
        cancel()
        guard let worker = workerFor?(target), isTargetValid?(target) == true else { return }
        let request = UUID()
        requestID = request
        self.target = target
        let permit = OperationPermit(lifetime: 45)
        self.permit = permit
        let originalFrame = panel.frame
        guard let app = NSRunningApplication(processIdentifier: target.pid), !app.isTerminated else {
            onStatus?(NSLocalizedString("対象アプリをアクティブにできませんでした。", comment: "Status: failed to activate the target app"))
            cancel()
            return
        }
        // Best effort only: cooperative activation may refuse this from a non-active accessory app.
        // The AX frontmost/raise path in focus() and its strict validateFocus decide the outcome.
        _ = app.activate()
        worker.focus(target, permit: permit) { [weak self, weak panel] focusResult in
            guard let self, let panel, self.requestID == request, permit.isValid() else { return }
            guard case .success = focusResult else { self.fail(focusResult); return }
            worker.prepareMenu(for: target, headings: headings, permit: permit) { [weak self, weak panel] result in
                guard let self, let panel, self.requestID == request, permit.isValid() else {
                    if case .success(let model) = result { worker.discardMenu(model.sessionID) }
                    return
                }
                guard case .success(let model) = result else { self.fail(result); return }
                guard self.isTargetValid?(target) == true,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid,
                      Rect(panel.frame).approximatelyEquals(Rect(originalFrame), tolerance: 1) else {
                    worker.discardMenu(model.sessionID)
                    self.cancel()
                    return
                }
                let selection = MenuSelection()
                let menu = self.makeMenu(model.entries, selection: selection)
                self.activeMenu = menu
                // The panel remains non-key and this app is never explicitly activated here.
                // A view-bound popup joins the header's ordering group. Reordering that header
                // behind the target can then put the lower menu rows behind the target too.
                // Screen coordinates keep the native menu independent of the non-key header.
                let screenAnchor = panel.convertPoint(toScreen: panel.headerView.convert(anchor, to: nil))
                menu.popUp(positioning: nil, at: screenAnchor, in: nil)
                self.activeMenu = nil
                guard self.requestID == request, permit.isValid(), self.isTargetValid?(target) == true,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid,
                      let command = selection.commandID else {
                    worker.discardMenu(model.sessionID)
                    self.cancel()
                    return
                }
                worker.execute(sessionID: model.sessionID, commandID: command) { [weak self] result in
                    guard let self else { return }
                    if case .failure(let error) = result { self.onStatus?(error.localizedDescription) }
                    else { self.onStatus?(NSLocalizedString("元アプリへ実行要求を送りました。", comment: "Status: sent the action to the original app")) }
                    if self.requestID == request { self.cancel() }
                }
            }
        }
    }
    private func fail<T>(_ result: Result<T, Error>) {
        if case .failure(let error) = result { onStatus?(error.localizedDescription) }
        cancel()
    }
    private func makeMenu(_ entries: [MenuEntry], selection: MenuSelection) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.font = .systemFont(ofSize: 13)
        for entry in entries {
            if entry.isSeparator { menu.addItem(.separator()); continue }
            let title = entry.title + (entry.shortcut.isEmpty ? "" : "    \(entry.shortcut)")
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = entry.enabled
            if !entry.mark.isEmpty { item.state = ["-", "–", "−"].contains(entry.mark) ? .mixed : .on }
            if !entry.children.isEmpty { item.submenu = makeMenu(entry.children, selection: selection) }
            else if let id = entry.commandID, entry.enabled {
                item.target = selection
                item.action = #selector(MenuSelection.choose(_:))
                item.representedObject = id
            }
            // Never bind the source shortcut to Transom's own responder chain.
            menu.addItem(item)
        }
        return menu
    }
}
