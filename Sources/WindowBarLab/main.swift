import AppKit

/// Separate development fixture. Not linked into WindowBar and not built by default.
@MainActor
final class LabDelegate: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []
    private var editors: [Int: NSTextView] = [:]
    private var names: [Int: String] = [:]
    private let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("WindowBarLab", isDirectory: true)

    func applicationDidFinishLaunching(_ notification: Notification) {
        makeMenus()
        for (offset, name) in ["A", "B"].enumerated() {
            let window = NSWindow(contentRect: NSRect(x: 140 + offset * 100, y: 160 + offset * 70, width: 680, height: 420),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "同名.txt" // Deliberately identical titles: identify by window, never by text.
            window.isReleasedWhenClosed = false
            let scroll = NSScrollView(frame: window.contentView!.bounds)
            scroll.autoresizingMask = [.width, .height]
            scroll.hasVerticalScroller = true
            let text = NSTextView(frame: scroll.bounds)
            text.isRichText = false
            text.isVerticallyResizable = true
            text.isHorizontallyResizable = false
            text.autoresizingMask = [.width]
            text.textContainer?.widthTracksTextView = true
            text.allowsUndo = true
            text.font = .monospacedSystemFont(ofSize: 16, weight: .regular)
            text.string = "Window \(name)\n\nこのウィンドウは \(name) です。\nこの行を選択し、外付けの「編集 → コピー」を試してください。\n\n「ファイル → 検証保存」で、このウィンドウだけを\nApplication Support/WindowBarLab/\(name).txt に保存します。"
            scroll.documentView = text
            window.contentView = scroll
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(text)
            windows.append(window)
            editors[window.windowNumber] = text
            names[window.windowNumber] = name
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    private func makeMenus() {
        let main = NSMenu()
        let app = NSMenu()
        app.addItem(withTitle: "WindowBarLabを終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appRoot = NSMenuItem(); appRoot.submenu = app; main.addItem(appRoot)
        let file = NSMenu(title: "ファイル")
        let save = NSMenuItem(title: "検証保存", action: #selector(saveFixture(_:)), keyEquivalent: "s")
        save.target = self; file.addItem(save)
        let show = NSMenuItem(title: "検証用シートを開く", action: #selector(showSheet(_:)), keyEquivalent: "")
        show.target = self; file.addItem(show)
        let root = NSMenuItem(title: "ファイル", action: nil, keyEquivalent: ""); root.submenu = file; main.addItem(root)
        let edit = NSMenu(title: "編集")
        edit.addItem(withTitle: "取り消す", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "カット", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "コピー", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "ペースト", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let editRoot = NSMenuItem(title: "編集", action: nil, keyEquivalent: ""); editRoot.submenu = edit; main.addItem(editRoot)
        let windowMenu = NSMenu(title: "ウインドウ")
        let windowRoot = NSMenuItem(title: "ウインドウ", action: nil, keyEquivalent: "")
        windowRoot.submenu = windowMenu; main.addItem(windowRoot)
        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }
    @objc private func saveFixture(_ sender: Any?) {
        guard let window = NSApp.mainWindow, let name = names[window.windowNumber],
              let text = editors[window.windowNumber] else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try text.string.write(to: directory.appendingPathComponent("\(name).txt"), atomically: true, encoding: .utf8)
            let event = "\(ISO8601DateFormatter().string(from: Date())) SAVE window=\(name) id=\(window.windowNumber)\n"
            let url = directory.appendingPathComponent("events.log")
            if !FileManager.default.fileExists(atPath: url.path) { try Data().write(to: url) }
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(event.utf8))
            try handle.close()
        } catch {
            let alert = NSAlert(error: error)
            alert.beginSheetModal(for: window)
        }
    }
    @objc private func showSheet(_ sender: Any?) {
        guard let window = NSApp.mainWindow else { return }
        let alert = NSAlert()
        alert.messageText = "モーダル中は外付け操作を止める検証"
        alert.informativeText = "このシートの表示中、対象ウィンドウの外付けバーは非表示になる設計です。"
        alert.addButton(withTitle: "閉じる")
        alert.beginSheetModal(for: window)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = LabDelegate()
    app.setActivationPolicy(.regular)
    app.delegate = delegate
    app.run()
    withExtendedLifetime(delegate) {}
}
