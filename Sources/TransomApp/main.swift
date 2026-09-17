import AppKit
import TransomBridge

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = AppController()
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
            NSApp.terminate(nil)
            return
        }
        controller.start()
    }
    func applicationWillTerminate(_ notification: Notification) { controller.stop() }
}

if CommandLine.arguments.contains("--capabilities") {
    print("exact-window-id=\(WBHasAXWindowID())")
    print("private-relative-ordering=\(WBHasRelativeOrdering())")
} else {
    MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.setActivationPolicy(.accessory)
    application.delegate = delegate
    application.run()
    withExtendedLifetime(delegate) {}
    }
}
