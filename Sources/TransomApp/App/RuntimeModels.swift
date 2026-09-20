import AppKit
import TransomCore

struct ApplicationDescriptor {
    let instance: UUID
    let pid: Int32
    let name: String
    let bundleIdentifier: String?
    let launchDate: Date?
}

struct WindowSnapshot {
    let token: WindowToken
    let appName: String
    let bundleIdentifier: String?
    let title: String
    let frame: Rect
    let focused: Bool
    let minimized: Bool
    let fullscreen: Bool
    let modal: Bool
    let eligible: Bool
    let headings: [MenuHeading]
    let observedAt: TimeInterval
}

struct ApplicationScan {
    let instance: UUID
    let windows: [WindowSnapshot]
    let hidden: Set<WindowToken>
    let complete: Bool
}

enum TransomError: LocalizedError {
    case ax(Int32)
    case unavailable(String)
    case stale
    case cancelled
    case deadline
    case focusMismatch
    case actionUncertain

    var errorDescription: String? {
        switch self {
        case .ax(let code):
            return String(format: NSLocalizedString("アクセシビリティ応答エラー (%d)", comment: "Error: AX API returned an error code"), code)
        case .unavailable(let reason): return reason
        case .stale:
            return NSLocalizedString("対象またはメニューの状態が変わったため、操作を中止しました。",
                                      comment: "Error: target or menu state changed, action cancelled")
        case .cancelled:
            return NSLocalizedString("操作を中止しました。", comment: "Error: action cancelled")
        case .deadline:
            return NSLocalizedString("応答が遅いため、処理を中止しました。元のMacメニューをご利用ください。",
                                      comment: "Error: timed out, suggests using the original Mac menu")
        case .focusMismatch:
            return NSLocalizedString("対象ウィンドウのフォーカスを確認できないため、操作しませんでした。",
                                      comment: "Error: couldn't confirm the target window's focus")
        case .actionUncertain:
            return NSLocalizedString("実行要求への応答がありません。実行済みの可能性があるため自動再試行しません。元アプリを確認してください。",
                                      comment: "Error: no response to the action request, won't auto-retry")
        }
    }
}

extension Rect {
    init(_ rect: CGRect) {
        self.init(x: Double(rect.origin.x), y: Double(rect.origin.y),
                  width: Double(rect.width), height: Double(rect.height))
    }
    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

/// Main-thread delivery that keeps working while an NSMenu is tracking. DispatchQueue.main blocks are
/// NOT drained during menu tracking (observed on macOS 26: no render for the whole menu lifetime), but
/// run-loop blocks in common modes are. Every worker→UI completion goes through here.
enum MainRunLoop {
    static func perform(_ block: @escaping @MainActor () -> Void) {
        RunLoop.main.perform(inModes: [.common]) { MainActor.assumeIsolated { block() } }
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }
}

struct ScreenGeometry {
    let primaryHeight: Double
    let visibleFrames: [Rect]
    let fullFrames: [Rect]

    @MainActor static func current() -> ScreenGeometry? {
        // NSScreen.main is the screen containing the key window, not the global origin.
        guard let primary = NSScreen.screens.first else { return nil }
        let height = Double(primary.frame.height)
        return ScreenGeometry(primaryHeight: height,
            visibleFrames: NSScreen.screens.map { Geometry.flip(Rect($0.visibleFrame), primaryHeight: height) },
            fullFrames: NSScreen.screens.map { Geometry.flip(Rect($0.frame), primaryHeight: height) })
    }
    func appKit(_ rect: Rect) -> NSRect { Geometry.flip(rect, primaryHeight: primaryHeight).cgRect }
    func globalMouse(at appKitPoint: NSPoint) -> Point {
        Geometry.flip(Point(x: Double(appKitPoint.x), y: Double(appKitPoint.y)),
                      primaryHeight: primaryHeight)
    }
    @MainActor func globalMouse() -> Point {
        globalMouse(at: NSEvent.mouseLocation)
    }
}
