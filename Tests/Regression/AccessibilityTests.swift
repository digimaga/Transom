import AppKit
import ApplicationServices
import Foundation
import TransomCore

private struct AXTestContext {
    let worker: AXAppWorker
    let application: AXFixtureNode
    let window: AXFixtureNode
    let button: AXFixtureNode
    let token: WindowToken
}

private enum AXRegression {
    static var count = 0
    static var failures: [String] = []

    static func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        count += 1
        if !condition() { failures.append(name); print("FAIL \(name)") }
    }

    static func context() -> AXTestContext {
        AXFixture.reset()
        let application = AXFixture.application()
        let window = AXFixture.make(windowID: 777)
        let button = AXFixture.make()
        let descriptor = ApplicationDescriptor(instance: UUID(), pid: AXFixture.pid,
                                               name: "Fixture", bundleIdentifier: nil, launchDate: nil)
        let worker = AXAppWorker(descriptor: descriptor)
        let token = WindowToken(processInstance: descriptor.instance, pid: descriptor.pid,
                                windowID: 777, incarnation: 1)
        window.fields[kAXRoleAttribute] = kAXWindowRole as NSString
        window.fields[kAXSubroleAttribute] = kAXStandardWindowSubrole as NSString
        window.fields[kAXTitleAttribute] = "Document" as NSString
        window.fields[kAXDocumentAttribute] = "fixture://one" as NSString
        window.fields[kAXMinimizedAttribute] = NSNumber(value: false)
        window.fields["AXFullScreen"] = NSNumber(value: false)
        window.fields["AXModal"] = NSNumber(value: false)
        window.fields[kAXPositionAttribute] = NSValue(point: NSPoint(x: 100, y: 100))
        window.fields[kAXSizeAttribute] = NSValue(size: NSSize(width: 400, height: 300))
        window.fields[kAXCloseButtonAttribute] = button.reference
        window.fields[kAXMinimizeButtonAttribute] = button.reference
        window.settable.insert(kAXPositionAttribute)
        window.settable.insert(kAXSizeAttribute)
        button.fields[kAXEnabledAttribute] = NSNumber(value: true)
        button.actions = [kAXPressAction]
        application.fields[kAXFocusedWindowAttribute] = window.reference
        application.fields[kAXWindowsAttribute] = [window.reference] as NSArray
        application.fields[kAXFocusedUIElementAttribute] = window.reference
        let snapshot = WindowSnapshot(token: token, appName: "Fixture", bundleIdentifier: nil,
                                      title: "Document", frame: AXFixture.frameValue,
                                      focused: true, minimized: false, fullscreen: false,
                                      modal: false, eligible: true, headings: [], observedAt: 0)
        worker.records[777] = AXAppWorker.Record(token: token, element: window.reference,
                                                  snapshot: snapshot)
        return AXTestContext(worker: worker, application: application, window: window,
                             button: button, token: token)
    }

    @MainActor static func submitted<T>(_ worker: AXAppWorker,
                                        _ body: @escaping (AXAppWorker) throws -> T) async -> Result<T, Error> {
        await withCheckedContinuation { continuation in
            worker.submit(body) { continuation.resume(returning: $0) }
        }
    }
    @MainActor static func pressed(_ context: AXTestContext, permit: OperationPermit) async -> Result<Void, Error> {
        await withCheckedContinuation { continuation in
            context.worker.pressWindowButton(context.token, attribute: kAXCloseButtonAttribute,
                                             permit: permit) { continuation.resume(returning: $0) }
        }
    }
    @MainActor static func focused(_ context: AXTestContext, permit: OperationPermit) async -> Result<Void, Error> {
        await withCheckedContinuation { continuation in
            context.worker.focus(context.token, permit: permit) { continuation.resume(returning: $0) }
        }
    }
    @MainActor static func moved(_ context: AXTestContext, permit: OperationPermit) async -> Result<Rect, Error> {
        await withCheckedContinuation { continuation in
            context.worker.move(context.token, to: Point(x: 120, y: 130), thorough: true,
                                permit: permit) { continuation.resume(returning: $0) }
        }
    }
    @MainActor static func reserved(_ context: AXTestContext, permit: OperationPermit,
                                    expected: Rect? = nil, desired: Rect? = nil) async -> Result<Rect, Error> {
        await withCheckedContinuation { continuation in
            context.worker.reserve(context.token, expected: expected ?? AXFixture.frameValue,
                                   desired: desired ?? AXFixture.frameValue, permit: permit) {
                continuation.resume(returning: $0)
            }
        }
    }
    @MainActor static func scanned(_ worker: AXAppWorker) async -> Result<ApplicationScan, Error> {
        await withCheckedContinuation { continuation in
            worker.scan { continuation.resume(returning: $0) }
        }
    }
    @MainActor static func prepared(_ context: AXTestContext, permit: OperationPermit) async -> Result<PreparedMenu, Error> {
        await withCheckedContinuation { continuation in
            context.worker.prepareMenu(for: context.token, headings: [MenuHeading(index: 0, title: "File")],
                                       permit: permit) { continuation.resume(returning: $0) }
        }
    }
    @MainActor static func executed(_ context: AXTestContext, sessionID: UUID,
                                    commandID: UUID) async -> Result<Void, Error> {
        await withCheckedContinuation { continuation in
            context.worker.execute(sessionID: sessionID, commandID: commandID) {
                continuation.resume(returning: $0)
            }
        }
    }
    static func failed<T>(_ result: Result<T, Error>) -> Bool {
        if case .failure = result { return true }
        return false
    }
    static func succeeded<T>(_ result: Result<T, Error>) -> Bool {
        if case .success = result { return true }
        return false
    }
    static func actions() -> Int { AXFixture.writes.filter { $0.hasPrefix("action:") }.count }

    @MainActor static func focusCases() async {
        let variants: [(String, (AXTestContext) -> Void)] = [
            ("different PID", { _ in AXFixture.frontmostPID = AXFixture.pid + 99 }),
            ("different focus", { context in
                context.application.fields[kAXFocusedWindowAttribute] = AXFixture.make(windowID: 778).reference
            }),
            ("minimized", { $0.window.fields[kAXMinimizedAttribute] = NSNumber(value: true) }),
            ("fullscreen", { $0.window.fields["AXFullScreen"] = NSNumber(value: true) }),
            ("modal", { $0.window.fields["AXModal"] = NSNumber(value: true) }),
            ("sheet", { $0.window.hasSheet = true }),
            ("role", { $0.window.fields[kAXRoleAttribute] = "AXDialog" as NSString }),
            ("subrole", { $0.window.fields[kAXSubroleAttribute] = "AXDialog" as NSString })
        ]
        for (name, mutate) in variants {
            let context = context()
            mutate(context)
            let result = await submitted(context.worker) { try $0.validateFocus(context.token) }
            check(failed(result), "validateFocus rejects \(name)")
            check(AXFixture.writes.isEmpty, "validateFocus has no side effects for \(name)")
        }
        let good = context()
        let result = await submitted(good.worker) { try $0.validateFocus(good.token) }
        check(succeeded(result), "validateFocus normal control")
        check(AXFixture.writes.isEmpty, "validateFocus normal is read only")

        let stale = context()
        let replacement = AXFixture.make(windowID: stale.token.windowID)
        stale.worker.records[stale.token.windowID] = AXAppWorker.Record(
            token: stale.token, element: replacement.reference,
            snapshot: stale.worker.records[stale.token.windowID]!.snapshot)
        let sameID = await submitted(stale.worker) { try $0.validateFocus(stale.token) }
        check(failed(sameID), "same ID different AX reference rejects")
        let nextInstance = WindowToken(processInstance: UUID(), pid: stale.token.pid,
                                       windowID: stale.token.windowID, incarnation: stale.token.incarnation)
        let wrongProcess = await submitted(stale.worker) { try $0.exactRecord(nextInstance) }
        check(failed(wrongProcess), "new process instance rejects")
        let nextIncarnation = WindowToken(processInstance: stale.token.processInstance, pid: stale.token.pid,
                                          windowID: stale.token.windowID, incarnation: 2)
        let wrongIncarnation = await submitted(stale.worker) { try $0.exactRecord(nextIncarnation) }
        check(failed(wrongIncarnation), "different incarnation rejects")
    }

    @MainActor static func actionCases() async {
        for (name, answer) in [("success", AXError.success), ("uncertain", AXError.cannotComplete),
                               ("error", AXError.failure)] {
            let context = context()
            AXFixture.actionResult = answer
            let permit = OperationPermit()
            let first = await pressed(context, permit: permit)
            let second = await pressed(context, permit: permit)
            check(answer == .success ? succeeded(first) : failed(first), "button \(name) response")
            check(failed(second), "button \(name) same permit refused")
            check(actions() == 1, "button \(name) single AXPress")
        }
        let cancelled = context()
        let permit = OperationPermit()
        AXFixture.readHook = { if $0 == "bool:\(kAXEnabledAttribute)" { permit.cancel() } }
        let result = await pressed(cancelled, permit: permit)
        check(failed(result), "button cancellation after last read")
        check(actions() == 0, "cancelled button no AXPress")
    }

    @MainActor static func cancellationCases() async {
        for lifetime in [false, true] {
            let focusContext = context()
            let focusPermit = OperationPermit()
            AXFixture.readHook = { key in
                if key == "settable:\(kAXFrontmostAttribute)" {
                    if lifetime { focusContext.worker.stop() } else { focusPermit.cancel() }
                }
            }
            let focusResult = await focused(focusContext, permit: focusPermit)
            check(failed(focusResult), "focus cancellation \(lifetime)")
            check(AXFixture.writes.isEmpty, "focus cancellation zero writes \(lifetime)")

            let moveContext = context()
            let movePermit = OperationPermit()
            AXFixture.readHook = { key in
                if key == "settable:\(kAXPositionAttribute)" {
                    if lifetime { moveContext.worker.stop() } else { movePermit.cancel() }
                }
            }
            let moveResult = await moved(moveContext, permit: movePermit)
            check(failed(moveResult), "move cancellation \(lifetime)")
            check(AXFixture.writes.isEmpty, "move cancellation zero writes \(lifetime)")

            let reserveContext = context()
            let reservePermit = OperationPermit()
            AXFixture.readHook = { key in
                if key == "settable:\(kAXPositionAttribute)" {
                    if lifetime { reserveContext.worker.stop() } else { reservePermit.cancel() }
                }
            }
            let reserveResult = await reserved(reserveContext, permit: reservePermit)
            check(failed(reserveResult), "reserve cancellation \(lifetime)")
            check(AXFixture.writes.isEmpty, "reserve cancellation zero writes \(lifetime)")
        }
        let focusContext = context()
        focusContext.application.settable.insert(kAXFrontmostAttribute)
        focusContext.window.settable.insert(kAXMainAttribute)
        focusContext.application.settable.insert(kAXFocusedWindowAttribute)
        let focusResult = await focused(focusContext, permit: OperationPermit())
        check(succeeded(focusResult), "focus normal control")
        check(AXFixture.writes.contains("action:777:\(kAXRaiseAction)"), "focus normal sends raise")
        let moveContext = context()
        let moveResult = await moved(moveContext, permit: OperationPermit())
        check(succeeded(moveResult), "move normal control")
        check(AXFixture.writes == ["position"], "move normal one position write")
        let reserveContext = context()
        let reserveResult = await reserved(reserveContext, permit: OperationPermit())
        check(succeeded(reserveResult), "reserve normal control")
        check(AXFixture.writes == ["position"], "reserve normal one position write")
    }

    @MainActor static func placementCases() async {
        let expected = Rect(x: 100, y: 100, width: 400, height: 300)
        let growing = Rect(x: 80, y: 70, width: 800, height: 600)
        let growContext = context()
        let growResult = await reserved(growContext, permit: OperationPermit(),
                                        expected: expected, desired: growing)
        if case .success(let actual) = growResult {
            check(actual == growing, "growing reserve returns accepted frame")
        } else { check(false, "growing reserve succeeds") }
        check(AXFixture.writes == ["position", "size"], "growing reserve moves then resizes once")
        check(AXFixture.describedIDs == [[growContext.token.windowID], [growContext.token.windowID]],
              "growing reserve confirms exact CG ID after both writes")
        check(AXFixture.flushCount == 2, "growing reserve flushes both placement checks")

        let shrinking = Rect(x: 120, y: 140, width: 300, height: 200)
        let shrinkContext = context()
        let shrinkResult = await reserved(shrinkContext, permit: OperationPermit(),
                                          expected: expected, desired: shrinking)
        if case .success(let actual) = shrinkResult {
            check(actual == shrinking, "shrinking reserve returns accepted frame")
        } else { check(false, "shrinking reserve succeeds") }
        check(AXFixture.writes == ["size", "position"], "shrinking reserve resizes then moves once")
        check(AXFixture.describedIDs == [[shrinkContext.token.windowID], [shrinkContext.token.windowID]],
              "shrinking reserve confirms exact CG ID after both writes")

        let acceptedContext = context()
        let accepted = Rect(x: 80, y: 70, width: 760, height: 540)
        AXFixture.acceptedAfterWrite = 2
        AXFixture.acceptedFrame = accepted
        let acceptedResult = await reserved(acceptedContext, permit: OperationPermit(),
                                            expected: expected, desired: growing)
        if case .success(let actual) = acceptedResult {
            check(actual == accepted && actual != growing, "reserve reports app-clamped accepted frame")
        } else { check(false, "app-clamped reserve succeeds") }
        check(AXFixture.writes == ["position", "size"], "app-clamped reserve does not retry writes")
        check(AXFixture.describedIDs.count == 2, "app-clamped frame confirmed at both CG steps")

        let foreignContext = context()
        AXFixture.serverPID = AXFixture.pid + 1
        let foreignResult = await reserved(foreignContext, permit: OperationPermit(),
                                           expected: expected, desired: growing)
        check(failed(foreignResult), "foreign CG owner rejects placement")
        check(AXFixture.writes == ["position"], "foreign CG owner prevents second AX write")
        check(AXFixture.describedIDs == [[foreignContext.token.windowID]],
              "foreign CG owner was checked for exact requested ID")
    }

    @MainActor static func mainRunLoopCase() {
        let trackingMode = CFRunLoopMode(rawValue: RunLoop.Mode.eventTracking.rawValue as CFString)
        CFRunLoopAddCommonMode(CFRunLoopGetMain(), trackingMode)
        var delivered = false
        var deliveredMode: String?
        var direct = false
        RunLoop.main.perform(inModes: [.eventTracking]) { direct = true }
        MainRunLoop.perform {
            delivered = true
            deliveredMode = CFRunLoopCopyCurrentMode(CFRunLoopGetMain())?.rawValue as String?
        }
        _ = CFRunLoopRunInMode(trackingMode, 0.5, false)
        check(direct && delivered && deliveredMode == RunLoop.Mode.eventTracking.rawValue,
              "MainRunLoop completion reaches event tracking common mode")
    }

    @MainActor static func scanCases() async {
        let context = context()
        context.worker.records.removeAll()
        let first = await scanned(context.worker)
        check(succeeded(first), "scan complete list succeeds")
        guard case .success(let initial) = first, let scannedToken = initial.windows.first?.token else {
            check(false, "scan provides initial token")
            return
        }
        if case .success(let scan) = first {
            check(scan.complete && scan.hidden.isEmpty && scan.windows.count == 1, "scan complete refreshes")
        }
        context.window.failBatch = true
        let partial = await scanned(context.worker)
        if case .success(let scan) = partial {
            check(!scan.complete && scan.hidden == [scannedToken] && scan.windows.count == 1,
                  "partial attribute failure hides but retains")
        } else { check(false, "partial attribute failure returns scan") }
        context.window.failBatch = false
        AXFixture.listFails = true
        let unavailable = await scanned(context.worker)
        check(failed(unavailable), "window list failure returns error")
        check(context.worker.records[777] != nil, "window list failure retains record")
        AXFixture.listFails = false
        context.application.fields[kAXWindowsAttribute] = [] as NSArray
        let missingOnce = await scanned(context.worker)
        if case .success(let scan) = missingOnce {
            check(scan.hidden == [scannedToken] && scan.windows.count == 1, "first missing list hides")
        } else { check(false, "first missing list succeeds") }
        let missingTwice = await scanned(context.worker)
        if case .success(let scan) = missingTwice {
            check(scan.windows.isEmpty && context.worker.records[777] == nil, "second missing list removes")
        } else { check(false, "second missing list succeeds") }
        let replacement = AXFixture.make(windowID: 777)
        replacement.fields = context.window.fields
        context.application.fields[kAXWindowsAttribute] = [replacement.reference] as NSArray
        context.application.fields[kAXFocusedWindowAttribute] = replacement.reference
        let returned = await scanned(context.worker)
        if case .success(let scan) = returned {
            check(scan.windows.count == 1 && scan.windows[0].token.incarnation > scannedToken.incarnation,
                  "reappeared window gets new incarnation")
        } else { check(false, "reappeared window succeeds") }
    }

    static func menuTree(_ context: AXTestContext) -> (AXFixtureNode, AXFixtureNode, AXFixtureNode) {
        let root = AXFixture.make()
        let heading = AXFixture.make()
        let item = AXFixture.make()
        context.application.fields[kAXMenuBarAttribute] = root.reference
        root.children = [heading.reference]
        heading.fields[kAXTitleAttribute] = "File" as NSString
        heading.fields[kAXRoleAttribute] = kAXMenuBarItemRole as NSString
        heading.children = [item.reference]
        item.fields[kAXTitleAttribute] = "Save" as NSString
        item.fields[kAXRoleAttribute] = kAXMenuItemRole as NSString
        item.fields[kAXEnabledAttribute] = NSNumber(value: true)
        item.actions = [kAXPressAction]
        return (root, heading, item)
    }
    @MainActor static func menuCases() async {
        let changedDuringRead = context()
        _ = menuTree(changedDuringRead)
        AXFixture.readHook = { key in
            if key == "batch" {
                changedDuringRead.window.fields[kAXDocumentAttribute] = "fixture://changed" as NSString
                AXFixture.readHook = nil
            }
        }
        let changedResult = await prepared(changedDuringRead, permit: OperationPermit())
        check(failed(changedResult), "prepareMenu rejects document change during tree read")
        check(changedDuringRead.worker.menus.isEmpty, "prepareMenu does not retain stale session")
        check(actions() == 0, "prepareMenu change has no AXPress")

        let variants: [(String, (AXTestContext, AXFixtureNode, AXFixtureNode, AXFixtureNode) -> Void)] = [
            ("different focused window", { context, _, _, _ in
                context.application.fields[kAXFocusedWindowAttribute] = AXFixture.make(windowID: 778).reference
            }),
            ("different document", { context, _, _, _ in
                context.window.fields[kAXDocumentAttribute] = "fixture://two" as NSString
            }),
            ("different focused element", { context, _, _, _ in
                context.application.fields[kAXFocusedUIElementAttribute] = AXFixture.make().reference
            }),
            ("different selection range", { context, _, _, _ in
                context.window.fields[kAXSelectedTextRangeAttribute] = NSValue(range: NSRange(location: 1, length: 2))
            }),
            ("different root", { context, _, _, _ in
                context.application.fields[kAXMenuBarAttribute] = AXFixture.make().reference
            }),
            ("different path reference", { _, root, _, _ in
                root.children = [AXFixture.make().reference]
            }),
            ("different role", { _, _, _, item in item.fields[kAXRoleAttribute] = "AXButton" as NSString }),
            ("different title", { _, _, _, item in item.fields[kAXTitleAttribute] = "Open" as NSString }),
            ("disabled", { _, _, _, item in item.fields[kAXEnabledAttribute] = NSNumber(value: false) })
        ]
        for (name, mutate) in variants {
            let context = context()
            let (root, heading, item) = menuTree(context)
            let prepared = await prepared(context, permit: OperationPermit())
            guard case .success(let menu) = prepared,
                  let commandID = context.worker.menus[menu.sessionID]?.commands.keys.first else {
                check(false, "prepareMenu normal before \(name)")
                continue
            }
            mutate(context, root, heading, item)
            let result = await executed(context, sessionID: menu.sessionID, commandID: commandID)
            check(failed(result), "execute rejects \(name)")
            check(actions() == 0, "execute has no AXPress for \(name)")
        }
        for (name, answer) in [("success", AXError.success), ("uncertain", AXError.cannotComplete),
                               ("error", AXError.failure)] {
            let context = context()
            _ = menuTree(context)
            let permit = OperationPermit()
            let prepared = await prepared(context, permit: permit)
            guard case .success(let menu) = prepared,
                  let commandID = context.worker.menus[menu.sessionID]?.commands.keys.first else {
                check(false, "prepareMenu normal for \(name)")
                continue
            }
            AXFixture.actionResult = answer
            let first = await executed(context, sessionID: menu.sessionID, commandID: commandID)
            let second = await executed(context, sessionID: menu.sessionID, commandID: commandID)
            check(answer == .success ? succeeded(first) : failed(first), "menu \(name) response")
            check(failed(second), "menu \(name) same session refused")
            check(actions() == 1, "menu \(name) single AXPress")
        }
    }
}

@main struct AccessibilityTests {
    @MainActor static func main() async {
        DispatchQueue.global().asyncAfter(deadline: .now() + 20) {
            fputs("Accessibility regression timed out\n", stderr)
            exit(124)
        }
        await AXRegression.focusCases()
        await AXRegression.actionCases()
        await AXRegression.cancellationCases()
        await AXRegression.placementCases()
        await AXRegression.scanCases()
        await AXRegression.menuCases()
        AXRegression.mainRunLoopCase()
        print("RESULT accessibility passed=\(AXRegression.count - AXRegression.failures.count) total=\(AXRegression.count)")
        if !AXRegression.failures.isEmpty { exit(1) }
    }
}
