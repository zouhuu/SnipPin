import AppKit

/// Window for recording the global hotkeys and the in-editor tool keys.
@MainActor
final class ShortcutSettingsWindow: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private var recorders: [ShortcutAction: ShortcutRecorderView] = [:]
    private let warningLabel = NSTextField(labelWithString: "")
    private let onApply: () -> [ShortcutAction]
    private let onClose: () -> Void
    private var isClosed = false
    private var hasPositioned = false

    private let contentWidth: CGFloat = 440
    private let contentHeight: CGFloat = 596

    init(onApply: @escaping () -> [ShortcutAction], onClose: @escaping () -> Void) {
        self.onApply = onApply
        self.onClose = onClose
        self.window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: contentWidth, height: contentHeight),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        self.window.identifier = NSUserInterfaceItemIdentifier("SnipPin.shortcuts")
        super.init()
        build()
    }

    var contentViewForTesting: NSView? { window.contentView }

    func closeForTesting() {
        window.close()
    }

    func show() {
        window.title = "快捷键设置"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.delegate = self
        if !hasPositioned {
            window.center()
            hasPositioned = true
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func build() {
        let content = NSView(frame: CGRect(x: 0, y: 0, width: contentWidth, height: contentHeight))
        window.contentView = content

        addHeader("全局快捷键", y: 556, to: content)
        addHint("在其它 App 里也能触发；至少需要 ⌘ / ⌃ / ⌥", y: 534, to: content)
        addRows(ShortcutAction.globals, startY: 500, to: content)

        addHeader("编辑窗口内的工具", y: 410, to: content)
        addHint("单个按键，按下即切换工具", y: 388, to: content)
        addRows(ShortcutAction.tools, startY: 354, to: content)

        addHint("点击右侧按钮后按下新快捷键；Esc 取消，⌫ 清除", y: 118, to: content)
        addHint("编辑器的 ⌘C / ⌘S / ⌘P / ⌘O / ⌘Z 保持不变", y: 96, to: content)

        warningLabel.font = NSFont.systemFont(ofSize: 11)
        warningLabel.textColor = .secondaryLabelColor
        warningLabel.lineBreakMode = .byWordWrapping
        warningLabel.maximumNumberOfLines = 2
        warningLabel.frame = CGRect(x: 20, y: 56, width: contentWidth - 40, height: 32)
        content.addSubview(warningLabel)

        let reset = NSButton(title: "恢复默认", target: self, action: #selector(resetTapped))
        reset.bezelStyle = .rounded
        reset.frame = CGRect(x: 20, y: 18, width: 100, height: 28)
        content.addSubview(reset)

        let done = NSButton(title: "完成", target: self, action: #selector(doneTapped))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        done.frame = CGRect(x: contentWidth - 120, y: 18, width: 100, height: 28)
        content.addSubview(done)

        warningLabel.stringValue = "修改会立即保存，关闭本窗口后生效"
    }

    private func addHeader(_ text: String, y: CGFloat, to view: NSView) {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .labelColor
        label.frame = CGRect(x: 20, y: y, width: contentWidth - 40, height: 16)
        view.addSubview(label)
    }

    private func addHint(_ text: String, y: CGFloat, to view: NSView) {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 10)
        label.textColor = .tertiaryLabelColor
        label.frame = CGRect(x: 20, y: y, width: contentWidth - 40, height: 14)
        view.addSubview(label)
    }

    private func addRows(_ actions: [ShortcutAction], startY: CGFloat, to view: NSView) {
        var y = startY
        for action in actions {
            let label = NSTextField(labelWithString: action.title)
            label.font = NSFont.systemFont(ofSize: 12)
            label.textColor = .labelColor
            label.frame = CGRect(x: 24, y: y + 5, width: 200, height: 16)
            view.addSubview(label)

            let recorder = ShortcutRecorderView(
                frame: CGRect(x: contentWidth - 190, y: y, width: 160, height: 26)
            )
            recorder.combo = ShortcutStore.shared.combo(for: action)
            recorder.onChange = { [weak self] combo in
                self?.recorded(combo, for: action)
            }
            view.addSubview(recorder)
            recorders[action] = recorder
            y -= 30
        }
    }

    private func recorded(_ combo: KeyCombo?, for action: ShortcutAction) {
        if let message = validate(combo, for: action) {
            warningLabel.stringValue = message
            warningLabel.textColor = .systemOrange
            recorders[action]?.combo = ShortcutStore.shared.combo(for: action)
            return
        }
        ShortcutStore.shared.set(combo, for: action)
        let failures = onApply()
        if !failures.isEmpty {
            warningLabel.stringValue = "注册失败（可能被其它 App 占用）：" + failures.map(\.title).joined(separator: "、")
            warningLabel.textColor = .systemRed
        } else if let combo {
            warningLabel.stringValue = "「\(action.title)」已设为 \(combo.display)"
            warningLabel.textColor = .secondaryLabelColor
        } else {
            warningLabel.stringValue = "已清除「\(action.title)」的快捷键"
            warningLabel.textColor = .secondaryLabelColor
        }
    }

    private func validate(_ combo: KeyCombo?, for action: ShortcutAction) -> String? {
        guard let combo else { return nil }
        if action.isGlobal {
            guard !combo.modifiers.intersection([.command, .control, .option]).isEmpty else {
                return "全局快捷键至少需要 ⌘ / ⌃ / ⌥ 中的一个"
            }
            for other in ShortcutAction.globals where other != action {
                if ShortcutStore.shared.combo(for: other) == combo {
                    return "与「\(other.title)」的快捷键重复"
                }
            }
        } else {
            guard combo.modifiers.isEmpty else {
                return "工具快捷键请使用单个按键，不要加修饰键"
            }
            let reserved: Set<UInt32> = [36, 48, 49, 51, 53, 76, 117]
            if reserved.contains(combo.keyCode) {
                return "空格 / 回车 / Tab / Esc / 删除 已被编辑器占用"
            }
            for other in ShortcutAction.tools where other != action {
                if ShortcutStore.shared.combo(for: other)?.keyCode == combo.keyCode {
                    return "与「\(other.title)」的快捷键重复"
                }
            }
        }
        return nil
    }

    @objc private func resetTapped() {
        ShortcutStore.shared.resetToDefaults()
        for (action, recorder) in recorders {
            recorder.combo = ShortcutStore.shared.combo(for: action)
        }
        _ = onApply()
        warningLabel.stringValue = "已恢复默认快捷键"
        warningLabel.textColor = .secondaryLabelColor
    }

    @objc private func doneTapped() {
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard !isClosed else { return }
        isClosed = true
        onClose()
    }
}
