import AppKit

@MainActor
final class OCRResultPanel: NSObject, NSWindowDelegate {
    private static var retained: OCRResultPanel?
    private let window: NSWindow
    private let textView: NSTextView
    private let text: String

    private init(text: String, near rect: CGRect) {
        self.text = text
        let size = CGSize(width: 480, height: 300)
        self.window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        self.textView = NSTextView(frame: CGRect(origin: .zero, size: size))
        super.init()
        buildUI(size: size, near: rect)
    }

    private func buildUI(size: CGSize, near rect: CGRect) {
        window.title = "识别结果 · \(text.count) 个字符"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.delegate = self

        let content = NSView(frame: CGRect(origin: .zero, size: size))
        content.autoresizingMask = [.width, .height]

        let scroll = NSScrollView(frame: content.bounds.insetBy(dx: 0, dy: 44))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        textView.frame = scroll.bounds
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.string = text
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.autoresizingMask = [.width]
        textView.isRichText = false
        textView.allowsUndo = true
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView
        content.addSubview(scroll)

        let bar = NSView(frame: CGRect(x: 0, y: 0, width: size.width, height: 44))
        bar.autoresizingMask = [.width, .maxYMargin]
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        content.addSubview(bar)

        let copyButton = NSButton(title: "复制全部", target: self, action: #selector(copyAll))
        copyButton.bezelStyle = .rounded
        copyButton.keyEquivalent = "\r"
        copyButton.frame = CGRect(x: size.width - 210, y: 8, width: 96, height: 28)
        copyButton.autoresizingMask = [.minXMargin]
        bar.addSubview(copyButton)

        let closeButton = NSButton(title: "关闭", target: self, action: #selector(closePanel))
        closeButton.bezelStyle = .rounded
        closeButton.frame = CGRect(x: size.width - 106, y: 8, width: 96, height: 28)
        closeButton.autoresizingMask = [.minXMargin]
        bar.addSubview(closeButton)

        let hint = NSTextField(labelWithString: "可直接编辑后复制")
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.frame = CGRect(x: 14, y: 14, width: 200, height: 16)
        bar.addSubview(hint)

        window.contentView = content
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(rect) }) {
            var origin = CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
            origin.x = max(screen.visibleFrame.minX + 10, min(origin.x, screen.visibleFrame.maxX - size.width - 10))
            origin.y = max(screen.visibleFrame.minY + 10, min(origin.y, screen.visibleFrame.maxY - size.height - 10))
            window.setFrameOrigin(origin)
        } else {
            window.center()
        }
    }

    static func show(_ text: String, near rect: CGRect) {
        retained?.window.close()
        let panel = OCRResultPanel(text: text, near: rect)
        retained = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.window.makeKeyAndOrderFront(nil)
        panel.window.makeFirstResponder(panel.textView)
        panel.textView.selectAll(nil)
    }

    @objc private func copyAll() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textView.string, forType: .string)
        Toast.show("文字已复制", near: window.frame)
        window.close()
    }

    @objc private func closePanel() {
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        if OCRResultPanel.retained === self { OCRResultPanel.retained = nil }
    }
}
