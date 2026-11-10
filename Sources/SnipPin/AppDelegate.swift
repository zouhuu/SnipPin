import AppKit
import Carbon.HIToolbox
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var editor: EditorController?
    private var colorSampler: NSColorSampler?
    private var isCapturing = false
    private var isSimulating = false
    private var permissionWatchTask: Task<Void, Never>?

    private var shortcutSettingsWindow: ShortcutSettingsWindow?

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--selftest") {
            Task { @MainActor in
                let code = await SelfTest.run()
                exit(code)
            }
            return
        }
        // File-based triggers make automated testing reliable when launched via LaunchServices.
        DebugLog.write("launch argv=\(CommandLine.arguments)")
        if FileManager.default.fileExists(atPath: "/tmp/snippin-run-live-test") {
            DebugLog.write("live-test trigger found")
            try? FileManager.default.removeItem(atPath: "/tmp/snippin-run-live-test")
            Task { @MainActor in
                let code = await LiveTest.run()
                exit(code)
            }
            return
        }
        if FileManager.default.fileExists(atPath: "/tmp/snippin-run-export-test") {
            try? FileManager.default.removeItem(atPath: "/tmp/snippin-run-export-test")
            Task { @MainActor in
                let code = await ExportSelfTest.run()
                DebugLog.write("export-test exit=\(code)")
                exit(code)
            }
            return
        }
        if FileManager.default.fileExists(atPath: "/tmp/snippin-run-shortcut-test") {
            try? FileManager.default.removeItem(atPath: "/tmp/snippin-run-shortcut-test")
            Task { @MainActor in
                let code = await ShortcutSelfTest.run()
                DebugLog.write("shortcut-test exit=\(code)")
                exit(code)
            }
            return
        }
        if CommandLine.arguments.contains("--shortcut-test") {
            Task { @MainActor in
                let code = await ShortcutSelfTest.run()
                exit(code)
            }
            return
        }

        if CommandLine.arguments.contains("--export-test") {
            Task { @MainActor in
                let code = await ExportSelfTest.run()
                exit(code)
            }
            return
        }

        if FileManager.default.fileExists(atPath: "/tmp/snippin-run-render-demo") {
            try? FileManager.default.removeItem(atPath: "/tmp/snippin-run-render-demo")
            Task { @MainActor in
                let code = await SnapshotDemo.run()
                exit(code)
            }
            return
        }

        if CommandLine.arguments.contains("--live-test") {
            Task { @MainActor in
                let code = await LiveTest.run()
                exit(code)
            }
            return
        }
        if CommandLine.arguments.contains("--render-demo") {
            Task { @MainActor in
                let code = await SnapshotDemo.run()
                exit(code)
            }
            return
        }

        prewarmTextRendering()
        setUpStatusItem()
        registerHotKeys()

        if CommandLine.arguments.contains("--demo") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.captureRegion()
            }
        }

        if FileManager.default.fileExists(atPath: "/tmp/snippin-run-permission") {
            try? FileManager.default.removeItem(atPath: "/tmp/snippin-run-permission")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                _ = self?.ensureScreenPermission()
            }
        }

        let firstLaunch = !UserDefaults.standard.bool(forKey: "SnipPin.didShowWelcome")
        if firstLaunch {
            UserDefaults.standard.set(true, forKey: "SnipPin.didShowWelcome")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.showWelcome()
            }
        }
    }

    /// Touching CoreText once at launch avoids a rare first-draw font resolution failure.
    private func prewarmTextRendering() {
        let fonts = [
            NSFont.systemFont(ofSize: 12),
            NSFont.systemFont(ofSize: 18, weight: .semibold),
            NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        ]
        for font in fonts {
            _ = ("SnipPin 预热 0123" as NSString).size(withAttributes: [.font: font])
        }
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let symbol = NSImage(systemSymbolName: "viewfinder.circle", accessibilityDescription: "SnipPin")
                ?? NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "SnipPin")
                ?? NSImage(systemSymbolName: "crop", accessibilityDescription: "SnipPin")
            button.image = symbol
            button.image?.isTemplate = true
            button.toolTip = "SnipPin · 区域截图 ⌘⇧A"
        }
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        statusItem = item
    }

    /// (Re-)register the global hotkeys from the shortcut store. Returns actions that
    /// could not be registered (usually because another app owns the combination).
    @discardableResult
    func registerHotKeys() -> [ShortcutAction] {
        HotKeyManager.shared.unregisterAll()
        var failures: [ShortcutAction] = []

        func apply(_ action: ShortcutAction, _ handler: @escaping () -> Void) {
            guard let combo = ShortcutStore.shared.combo(for: action) else { return }
            if !HotKeyManager.shared.register(combo.keyCode, combo.modifiers, handler) {
                failures.append(action)
            }
        }

        apply(.capture) { [weak self] in self?.captureRegion() }
        apply(.pinClipboard) { [weak self] in self?.pinFromClipboard() }
        apply(.colorPicker) { [weak self] in self?.pickColor() }

        if !failures.isEmpty {
            NSLog("SnipPin: failed to register hotkeys for \(failures.map(\.rawValue).joined(separator: ", "))")
        }
        statusItem?.button?.toolTip = "SnipPin · 区域截图 \(shortcutText(.capture))"
        return failures
    }

    private func shortcutText(_ action: ShortcutAction) -> String {
        ShortcutStore.shared.combo(for: action)?.display ?? "未设置"
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(item("区域截图   \(shortcutText(.capture))", #selector(captureRegion), "", []))
        let delayItem = item("延时截图", nil, "", [])
        let delayMenu = NSMenu()
        for seconds in [3, 5, 10] {
            let sub = item("\(seconds) 秒后截图", #selector(captureDelayed(_:)), "", [])
            sub.tag = seconds
            delayMenu.addItem(sub)
        }
        delayItem.submenu = delayMenu
        menu.addItem(delayItem)

        menu.addItem(item("贴图剪贴板图片   \(shortcutText(.pinClipboard))", #selector(pinFromClipboard), "", []))
        menu.addItem(item("取色器   \(shortcutText(.colorPicker))", #selector(pickColor), "", []))
        menu.addItem(.separator())

        let closeAll = item("关闭全部贴图", #selector(closeAllPins), "", [])
        closeAll.isEnabled = PinController.shared.hasPins
        menu.addItem(closeAll)
        menu.addItem(item("打开截图文件夹", #selector(openScreenshotsFolder), "", []))
        menu.addItem(.separator())

        let permission = item(
            CaptureService.hasScreenCapturePermission ? "屏幕录制权限：已允许" : "⚠️ 屏幕录制权限：未允许",
            #selector(openPermissionSettings),
            "",
            []
        )
        menu.addItem(permission)
        menu.addItem(item("重新检查权限并重启", #selector(checkPermissionAndRestart), "", []))
        menu.addItem(item("快捷键设置…", #selector(openShortcutSettings), "", []))
        menu.addItem(item("快捷键说明…", #selector(showShortcuts), "", []))
        menu.addItem(.separator())
        menu.addItem(item("关于 SnipPin", #selector(showAbout), "", []))
        menu.addItem(item("退出 SnipPin", #selector(NSApplication.terminate(_:)), "q", [.command]))
    }

    private func item(_ title: String, _ action: Selector?, _ key: String, _ modifiers: NSEvent.ModifierFlags) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.keyEquivalentModifierMask = modifiers
        menuItem.target = action == nil ? nil : self
        return menuItem
    }

    // MARK: - Capture flow

    @objc func captureRegion() {
        startCapture(delay: 0)
    }

    @objc private func captureDelayed(_ sender: NSMenuItem) {
        startCapture(delay: TimeInterval(sender.tag))
    }

    private func startCapture(delay: TimeInterval) {
        Task { @MainActor in
            guard !isCapturing, !SelectionController.shared.active else { return }
            guard ensureScreenPermission() else { return }

            isCapturing = true
            defer { isCapturing = false }

            if delay > 0 {
                Toast.show("\(Int(delay)) 秒后开始截图…")
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            PinController.shared.hideForCapture()
            do {
                let shots = try await CaptureService.shared.captureAllScreens()
                NSApp.activate(ignoringOtherApps: true)
                SelectionController.shared.begin(shots: shots) { [weak self] result in
                    PinController.shared.restoreAfterCapture()
                    guard let self, let result else { return }
                    self.openEditor(result)
                }
            } catch {
                PinController.shared.restoreAfterCapture()
                self.presentError(error)
            }
        }
    }

    private func openEditor(_ result: SelectionResult) {
        editor?.close()
        let controller = EditorController(image: result.image, captureRect: result.screenRect, scale: result.scale)
        controller.onClose = { [weak self] in
            if self?.editor === controller { self?.editor = nil }
        }
        editor = controller
        controller.present()
    }

    /// Capture without asking (used by --demo / tests): show overlay only.
    func simulateCaptureForDemo() {
        guard !isSimulating else { return }
        isSimulating = true
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor in
            do {
                let shots = try await CaptureService.shared.captureAllScreens()
                SelectionController.shared.begin(shots: shots) { result in
                    self.isSimulating = false
                    if let result { self.openEditor(result) }
                }
            } catch {
                self.isSimulating = false
                self.presentError(error)
            }
        }
    }

    // MARK: - Clipboard pin & colour picker

    @objc func pinFromClipboard() {
        guard let (image, pointSize) = clipboardImage() else {
            Toast.show("剪贴板里没有图片")
            return
        }
        let mouse = NSEvent.mouseLocation
        let scale = CGFloat(image.width) / max(pointSize.width, 1)
        PinController.shared.pin(
            image: image,
            at: CGPoint(x: mouse.x - 20, y: mouse.y + 20),
            scale: scale
        )
        Toast.show("已贴到屏幕")
    }

    private func clipboardImage() -> (CGImage, CGSize)? {
        let pasteboard = NSPasteboard.general
        func from(_ image: NSImage) -> (CGImage, CGSize)? {
            guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            let size = image.size.width > 1 ? image.size : CGSize(width: cg.width, height: cg.height)
            return (cg, size)
        }
        if let data = pasteboard.data(forType: .png), let image = NSImage(data: data) {
            return from(image)
        }
        if let objects = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = objects.first, let result = from(image) {
            return result
        }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            for url in urls {
                if let image = NSImage(contentsOf: url), let result = from(image) {
                    return result
                }
            }
        }
        return nil
    }

    @objc func pickColor() {
        let sampler = NSColorSampler()
        colorSampler = sampler
        sampler.show { [weak self] color in
            defer { self?.colorSampler = nil }
            guard let color, let rgb = color.usingColorSpace(.sRGB) else { return }
            let hex = rgb.hexString
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(hex, forType: .string)
            Toast.show("已复制颜色 \(hex)")
        }
    }

    // MARK: - Menu actions

    @objc private func closeAllPins() {
        PinController.shared.closeAll()
    }

    @objc private func openScreenshotsFolder() {
        NSWorkspace.shared.open(ImageOutput.defaultDirectory())
    }

    @objc private func openPermissionSettings() {
        if !CaptureService.hasScreenCapturePermission {
            CaptureService.requestScreenCapturePermission()
            watchForPermissionGrant()
        }
        openScreenRecordingSettings()
    }

    @objc private func checkPermissionAndRestart() {
        if CaptureService.hasScreenCapturePermission {
            relaunch()
        } else {
            openPermissionSettings()
        }
    }

    /// macOS only re-reads the screen-recording grant for a fresh process,
    /// so poll after sending the user to System Settings and restart automatically.
    private func watchForPermissionGrant() {
        guard permissionWatchTask == nil else { return }
        permissionWatchTask = Task { @MainActor in
            for _ in 0..<60 {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if CaptureService.hasScreenCapturePermission {
                    self.relaunch()
                    return
                }
            }
            self.permissionWatchTask = nil
        }
    }

    private func relaunch() {
        permissionWatchTask = nil
        Toast.show("已获得屏幕录制权限，正在重启…")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-n", Bundle.main.bundlePath]
            try? task.run()
            NSApp.terminate(nil)
        }
    }

    private func openScreenRecordingSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    @objc private func openShortcutSettings() {
        if let existing = shortcutSettingsWindow {
            existing.show()
            return
        }
        // Suspend global hotkeys while recording, otherwise they would swallow the new keys.
        HotKeyManager.shared.unregisterAll()
        let controller = ShortcutSettingsWindow(
            onApply: { [] },
            onClose: { [weak self] in
                guard let self else { return }
                self.shortcutSettingsWindow = nil
                let failures = self.registerHotKeys()
                if !failures.isEmpty { self.alertHotKeyFailures(failures) }
            }
        )
        shortcutSettingsWindow = controller
        controller.show()
    }

    func openShortcutSettingsForTesting() {
        openShortcutSettings()
    }

    func closeShortcutSettingsForTesting() {
        shortcutSettingsWindow?.closeForTesting()
    }

    private func alertHotKeyFailures(_ failures: [ShortcutAction]) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "部分快捷键注册失败"
        alert.informativeText = failures.map(\.title).joined(separator: "、")
            + " 的组合键可能被系统或其它 App 占用，请换一个。"
        alert.addButton(withTitle: "重新设置")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            openShortcutSettings()
        }
    }

    @objc private func showShortcuts() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "SnipPin 快捷键"
        alert.informativeText = """
        ⌘⇧A    区域截图
        ⌃⌥V    把剪贴板里的图片贴到屏幕
        ⌃⌥C    取色器（复制 HEX）

        截图后：
        R/O/A/P/H/M/T  矩形 / 椭圆 / 箭头 / 画笔 / 高亮 / 马赛克 / 文字
        ⌘Z 撤销 · ⌘C 复制 · ⌘S 保存 · ⌘P 贴图 · ⌘O 识别文字 · Esc 取消

        贴图窗口：拖动移动 · ⌥拖动拖出分享 · 滚轮缩放 · ⌥滚轮透明度 · 双击关闭
        """
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "SnipPin 1.0"
        alert.informativeText = "macOS 原生截图 · 标注 · 贴图工具\nScreenCaptureKit + Vision OCR，无第三方依赖。"
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    private func showWelcome() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "欢迎使用 SnipPin"
        if CaptureService.hasScreenCapturePermission {
            alert.informativeText = "按 ⌘⇧A 框选截图，截图后可以标注、复制、保存或「贴」在屏幕上。\n快捷菜单在右上角菜单栏的取景框图标里。"
            alert.addButton(withTitle: "开始使用")
        } else {
            alert.informativeText = "首次使用需要「屏幕录制」权限才能截图。\n\n点击「去授权」后，在系统设置里勾选 SnipPin；授权后请退出并重新打开 SnipPin。"
            alert.addButton(withTitle: "去授权")
            alert.addButton(withTitle: "稍后")
        }
        let response = alert.runModal()
        if !CaptureService.hasScreenCapturePermission, response == .alertFirstButtonReturn {
            CaptureService.requestScreenCapturePermission()
            openScreenRecordingSettings()
        }
    }

    // MARK: - Permission / errors

    private func ensureScreenPermission() -> Bool {
        if CaptureService.hasScreenCapturePermission { return true }
        CaptureService.requestScreenCapturePermission()

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "SnipPin 需要「屏幕录制」权限"
        alert.informativeText = "在「系统设置 → 隐私与安全性 → 屏幕与系统音频录制」中勾选 SnipPin。\n授权后请退出并重新打开 SnipPin（⌘Q 后再启动）。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            watchForPermissionGrant()
            openScreenRecordingSettings()
        }
        return false
    }

    private func presentError(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "截图失败"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
