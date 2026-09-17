import Foundation
import ApplicationServices
import WindowBarCore

/// Queue-confined references. Never exported to the UI or serialized.
struct AXPathStep {
    let index: Int
    let element: AXUIElement
    let role: String
    let title: String
}
struct AXCommandReference {
    let root: AXUIElement
    let path: [AXPathStep]
    let element: AXUIElement
    let title: String
}
struct AXContextWitness {
    let stamp: ContextStamp
    let focusedElement: AXUIElement?
    let selectionRange: CFTypeRef?
}
final class AXMenuSession {
    let id: UUID
    let target: WindowToken
    let witness: AXContextWitness
    let permit: OperationPermit
    var commands: [UUID: AXCommandReference] = [:]
    init(target: WindowToken, witness: AXContextWitness, permit: OperationPermit) {
        id = UUID(); self.target = target; self.witness = witness; self.permit = permit
    }
}

extension AXAppWorker {
    func readHeadings(budget: AXBudget) throws -> [MenuHeading] {
        guard let bar = AX.element(try AX.value(application, kAXMenuBarAttribute, budget: budget)) else { return [] }
        let children = try AX.children(bar, budget: budget)
        var headings: [MenuHeading] = []
        for (index, element) in children.enumerated().prefix(40) {
            guard let title = try AX.string(element, kAXTitleAttribute, budget: budget), !title.isEmpty else { continue }
            if index == 0 && ["Apple", "アップル", ""].contains(title) { continue }
            headings.append(MenuHeading(index: index, title: title))
        }
        return headings
    }
    private func witness(_ token: WindowToken) throws -> AXContextWitness {
        let record = try validateFocus(token)
        let title = try AX.string(record.element, kAXTitleAttribute) ?? ""
        let document = try AX.string(record.element, kAXDocumentAttribute)
        let focused = AX.element(try AX.value(application, kAXFocusedUIElementAttribute))
        let range = try focused.flatMap { try AX.value($0, kAXSelectedTextRangeAttribute) }
        return AXContextWitness(stamp: ContextStamp(token: token, title: title, document: document),
                                focusedElement: focused, selectionRange: range)
    }
    private func validateWitness(_ session: AXMenuSession) throws {
        let current = try witness(session.target)
        guard FocusPolicy.permits(expected: session.witness.stamp, current: current.stamp,
                                  frontmostPID: try AX.focusedPID(), isModal: false, isMinimized: false),
              AX.equal(current.focusedElement, session.witness.focusedElement),
              AX.equal(current.selectionRange, session.witness.selectionRange) else { throw WindowBarError.stale }
    }
    func prepareMenu(for target: WindowToken, headings requested: [MenuHeading],
                     permit: OperationPermit, completion: @escaping @MainActor (Result<PreparedMenu, Error>) -> Void) {
        submit({ worker in
            guard permit.isValid(), !requested.isEmpty else { throw WindowBarError.cancelled }
            let witness = try worker.witness(target)
            let session = AXMenuSession(target: target, witness: witness, permit: permit)
            let reader = AXMenuReader(application: worker.application, session: session)
            let entries = try reader.read(headings: requested)
            guard permit.isValid() else { throw WindowBarError.cancelled }
            // Focus/document state may have changed while the tree was being fetched.
            try worker.validateWitness(session)
            worker.menus[session.id] = session
            return PreparedMenu(sessionID: session.id, target: target, entries: entries,
                                truncated: reader.truncated)
        }, completion: completion)
    }
    func discardMenu(_ id: UUID) {
        queue.async { self.menus.removeValue(forKey: id)?.permit.cancel() }
    }
    func execute(sessionID: UUID, commandID: UUID, completion: @escaping @MainActor (Result<Void, Error>) -> Void) {
        submit({ worker in
            guard let session = worker.menus[sessionID], session.permit.isValid(),
                  let command = session.commands[commandID] else { throw WindowBarError.stale }
            defer { worker.menus.removeValue(forKey: sessionID) }
            try worker.validateWitness(session)
            let budget = AXBudget(seconds: 1.4)
            guard let currentRoot = AX.element(try AX.value(worker.application, kAXMenuBarAttribute, budget: budget)),
                  CFEqual(command.root, currentRoot) else { throw WindowBarError.stale }
            var current = currentRoot
            for step in command.path {
                let children = try AX.children(current, budget: budget)
                guard children.indices.contains(step.index) else { throw WindowBarError.stale }
                current = children[step.index]
                // Strict reference AND signature equality. Never search for a similarly named item.
                guard CFEqual(current, step.element),
                      try AX.string(current, kAXRoleAttribute, budget: budget) == step.role,
                      (try AX.string(current, kAXTitleAttribute, budget: budget) ?? "") == step.title else {
                    throw WindowBarError.stale
                }
            }
            guard CFEqual(current, command.element),
                  try AX.bool(current, kAXEnabledAttribute, budget: budget) == true,
                  try AX.actions(current, budget: budget).contains(kAXPressAction) else { throw WindowBarError.stale }
            try worker.validateWitness(session)
            // Last check immediately before dispatch. Cross-process UI actions cannot be atomic.
            guard worker.lifetime.isValid(), session.permit.commitOnce() else { throw WindowBarError.cancelled }
            AX.configure(current)
            let result = AXUIElementPerformAction(current, kAXPressAction as CFString)
            if result == .cannotComplete { throw WindowBarError.actionUncertain }
            guard result == .success else { throw WindowBarError.ax(result.rawValue) }
            // Success means the AX request was accepted, not that a save operation finished.
        }, completion: completion)
    }
}

private final class AXMenuReader {
    let application: AXUIElement
    let session: AXMenuSession
    let budget = AXBudget(seconds: 1.2)
    var count = 0
    var truncated = false
    private var root: AXUIElement?
    init(application: AXUIElement, session: AXMenuSession) { self.application = application; self.session = session }

    func read(headings: [MenuHeading]) throws -> [MenuEntry] {
        guard let root = AX.element(try AX.value(application, kAXMenuBarAttribute, budget: budget)) else {
            throw WindowBarError.unavailable("このアプリはメニュー情報を公開していません。")
        }
        self.root = root
        let tops = try AX.children(root, budget: budget)
        var entries: [MenuEntry] = []
        for heading in headings {
            guard tops.indices.contains(heading.index) else { throw WindowBarError.stale }
            let top = tops[heading.index]
            guard try AX.string(top, kAXTitleAttribute, budget: budget) == heading.title else { throw WindowBarError.stale }
            let role = try AX.string(top, kAXRoleAttribute, budget: budget) ?? ""
            let step = AXPathStep(index: heading.index, element: top, role: role, title: heading.title)
            var children = readChildren(of: top, path: [step], depth: 0)
            if children.isEmpty { children = [.notice("未展開または非対応のメニューです。元のMacメニューを使用してください。") ] }
            if headings.count == 1 { entries = children }
            else { entries.append(MenuEntry(title: heading.title, enabled: true, children: children)) }
            if truncated { break }
        }
        if truncated { entries.append(.notice("取得上限に達しました。残りは元のMacメニューを使用してください。")) }
        return entries
    }
    private func readChildren(of parent: AXUIElement, path: [AXPathStep], depth: Int) -> [MenuEntry] {
        guard depth <= 8, count < 500, session.permit.isValid() else { truncated = true; return [] }
        do {
            let children = try AX.children(parent, budget: budget)
            var entries: [MenuEntry] = []
            for (index, element) in children.enumerated() {
                try budget.check()
                guard count < 500, session.permit.isValid() else { truncated = true; break }
                count += 1
                let fields = try AX.batch(element, attributes: [kAXRoleAttribute, kAXTitleAttribute,
                    kAXEnabledAttribute, kAXMenuItemMarkCharAttribute, kAXMenuItemCmdCharAttribute,
                    kAXMenuItemCmdModifiersAttribute, kAXChildrenAttribute, "AXHasPopup"], budget: budget)
                let role = fields[kAXRoleAttribute] as? String ?? ""
                let title = fields[kAXTitleAttribute] as? String ?? ""
                let enabled = (fields[kAXEnabledAttribute] as? NSNumber)?.boolValue ?? false
                let step = AXPathStep(index: index, element: element, role: role, title: title)
                let childPath = path + [step]
                // AXMenu is a container, not a selectable item; preserve it in the validation path.
                if role == kAXMenuRole {
                    entries += readChildren(of: element, path: childPath, depth: depth + 1)
                    if truncated { break }
                    continue
                }
                guard role == kAXMenuItemRole else {
                    entries.append(.notice(title.isEmpty ? "非対応のメニュー部品" : title))
                    continue
                }
                let hasContainer = !AX.elements(fields[kAXChildrenAttribute]).isEmpty ||
                    ((fields["AXHasPopup"] as? NSNumber)?.boolValue ?? false)
                let nested = readChildren(of: element, path: childPath, depth: depth + 1)
                if truncated && nested.isEmpty { break }
                if title.isEmpty && !enabled && nested.isEmpty {
                    entries.append(MenuEntry(title: "", isSeparator: true))
                    continue
                }
                let mark = fields[kAXMenuItemMarkCharAttribute] as? String ?? ""
                let char = fields[kAXMenuItemCmdCharAttribute] as? String ?? ""
                let modifiers = (fields[kAXMenuItemCmdModifiersAttribute] as? NSNumber)?.intValue ?? 0
                let shortcut = shortcutString(char: char, modifiers: modifiers)
                if !nested.isEmpty {
                    entries.append(MenuEntry(title: title.isEmpty ? "メニュー" : title, enabled: enabled,
                                             mark: mark, shortcut: shortcut, children: nested))
                } else if hasContainer {
                    // Do not accidentally AXPress an unmaterialized submenu as though it were a command.
                    entries.append(MenuEntry(title: title.isEmpty ? "未展開のメニュー" : title, enabled: false))
                } else if enabled, !title.isEmpty,
                          try AX.actions(element, budget: budget).contains(kAXPressAction), let root {
                    let id = UUID()
                    session.commands[id] = AXCommandReference(root: root, path: childPath,
                                                              element: element, title: title)
                    entries.append(MenuEntry(commandID: id, title: title, enabled: true, mark: mark, shortcut: shortcut))
                } else {
                    entries.append(MenuEntry(title: title.isEmpty ? "名称なし（非対応）" : title,
                                             enabled: false, mark: mark, shortcut: shortcut))
                }
            }
            return entries
        } catch {
            truncated = true
            return [.notice("メニューの取得に失敗しました。元のMacメニューを使用してください。")]
        }
    }
    private func shortcutString(char: String, modifiers: Int) -> String {
        guard !char.isEmpty else { return "" }
        // AXMenuItemModifiers: Shift=1, Option=2, Control=4, NoCommand=8.
        return (modifiers & 4 != 0 ? "⌃" : "") + (modifiers & 2 != 0 ? "⌥" : "") +
               (modifiers & 1 != 0 ? "⇧" : "") + (modifiers & 8 == 0 ? "⌘" : "") + char.uppercased()
    }
}
