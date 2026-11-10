import AppKit

/// Keeps screenshots pinned above other windows (Snipaste's signature "贴图").
@MainActor
final class PinController {
    static let shared = PinController()

    private var pins: [PinWindow] = []
    private var hiddenForCapture = false
    var hasPins: Bool { !pins.isEmpty }

    func pin(image: CGImage, at topLeft: CGPoint, scale: CGFloat) {
        let pointSize = CGSize(
            width: max(24, CGFloat(image.width) / max(scale, 0.5)),
            height: max(24, CGFloat(image.height) / max(scale, 0.5))
        )
        let screen = NSScreen.screens.first(where: { $0.frame.contains(topLeft) }) ?? NSScreen.main
        var frame = CGRect(
            x: topLeft.x,
            y: topLeft.y - pointSize.height,
            width: pointSize.width,
            height: pointSize.height
        )
        if let visible = screen?.visibleFrame {
            if frame.width > visible.width { frame.size.width = visible.width }
            if frame.height > visible.height { frame.size.height = visible.height }
            frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
            frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - frame.height)
        }

        let window = PinWindow(image: image, contentFrame: frame)
        window.onClose = { [weak self, weak window] in
            guard let self, let window else { return }
            self.pins.removeAll { $0 === window }
        }
        pins.append(window)
        if hiddenForCapture {
            window.alphaValue = 0
        } else {
            window.orderFrontRegardless()
        }
    }

    /// Hide pins so they do not appear inside a new capture.
    func hideForCapture() {
        guard !hiddenForCapture else { return }
        hiddenForCapture = true
        for pin in pins { pin.orderOut(nil) }
    }

    func restoreAfterCapture() {
        guard hiddenForCapture else { return }
        hiddenForCapture = false
        for pin in pins { pin.orderFrontRegardless() }
    }

    func closeAll() {
        for pin in pins { pin.closePin() }
        pins.removeAll()
    }
}

final class PinWindow: NSPanel {
    let image: CGImage
    var onClose: (() -> Void)?
    private var tempDragFile: URL?

    init(image: CGImage, contentFrame: CGRect) {
        self.image = image
        super.init(
            contentRect: contentFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        level = .floating
        isOpaque = true
        backgroundColor = .black
        hasShadow = true
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false

        let view = PinImageView(image: image, frame: CGRect(origin: .zero, size: contentFrame.size))
        view.windowRef = self
        contentView = view
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func closePin() {
        onClose?()
        onClose = nil
        if let tempDragFile { try? FileManager.default.removeItem(at: tempDragFile) }
        tempDragFile = nil
        orderOut(nil)
        close()
    }

    func prepareDragFile() -> URL? {
        if let tempDragFile, FileManager.default.fileExists(atPath: tempDragFile.path) {
            return tempDragFile
        }
        tempDragFile = ImageOutput.temporaryPNGFile(image)
        return tempDragFile
    }
}

@MainActor
final class PinImageView: NSView, NSDraggingSource {
    private let image: CGImage
    weak var windowRef: PinWindow?
    private var dragStartMouse: CGPoint = .zero
    private var dragStartOrigin: CGPoint = .zero
    private var isMoving = false
    private var isHovering = false {
        didSet { needsDisplay = true }
    }

    init(image: CGImage, frame: CGRect) {
        self.image = image
        super.init(frame: frame)
        wantsLayer = true
        toolTip = "拖动移动 · ⌥拖动拖出分享 · 滚轮缩放 · 双击关闭"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent) { isHovering = false }

    override func draw(_ dirtyRect: NSRect) {
        NSImage(cgImage: image, size: bounds.size).draw(in: bounds)
        let outer = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        outer.lineWidth = 1
        NSColor.black.withAlphaComponent(0.35).setStroke()
        outer.stroke()
        let inner = NSBezierPath(rect: bounds.insetBy(dx: 2, dy: 2))
        inner.lineWidth = 1
        NSColor.white.withAlphaComponent(isHovering ? 0.85 : 0.5).setStroke()
        inner.stroke()
    }

    // MARK: - Moving

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        if event.clickCount == 2 {
            windowRef?.closePin()
            return
        }
        if event.modifierFlags.contains(.option) {
            beginDragOut(with: event)
            return
        }
        dragStartMouse = NSEvent.mouseLocation
        dragStartOrigin = window?.frame.origin ?? .zero
        isMoving = true
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isMoving, let window else { return }
        let current = NSEvent.mouseLocation
        window.setFrameOrigin(CGPoint(
            x: dragStartOrigin.x + (current.x - dragStartMouse.x),
            y: dragStartOrigin.y + (current.y - dragStartMouse.y)
        ))
    }

    override func mouseUp(with event: NSEvent) {
        isMoving = false
        NSCursor.openHand.set()
    }

    // MARK: - Zoom / opacity

    override func scrollWheel(with event: NSEvent) {
        guard let window else { return }
        if event.modifierFlags.contains(.option) {
            let next = window.alphaValue - event.scrollingDeltaY * 0.03
            window.alphaValue = min(1, max(0.25, next))
            return
        }
        let factor = 1 + event.scrollingDeltaY * 0.02
        var frame = window.frame
        let center = CGPoint(x: frame.midX, y: frame.midY)
        frame.size.width = max(60, frame.width * factor)
        frame.size.height = max(40, frame.height * factor)
        frame.origin = CGPoint(x: center.x - frame.width / 2, y: center.y - frame.height / 2)
        if let screen = window.screen?.visibleFrame {
            frame.size.width = min(frame.size.width, screen.width)
            frame.size.height = min(frame.size.height, screen.height)
            frame.origin.x = min(max(frame.origin.x, screen.minX), screen.maxX - frame.width)
            frame.origin.y = min(max(frame.origin.y, screen.minY), screen.maxY - frame.height)
        }
        window.setFrame(frame, display: true)
        window.contentView?.needsDisplay = true
    }

    // MARK: - Context menu

    override func rightMouseDown(with event: NSEvent) {
        guard let window else { return }
        window.makeKey()
        let menu = NSMenu()

        let copy = NSMenuItem(title: "复制图片", action: #selector(copyImage), keyEquivalent: "c")
        copy.target = self
        menu.addItem(copy)

        let save = NSMenuItem(title: "保存为 PNG…", action: #selector(saveImage), keyEquivalent: "s")
        save.target = self
        menu.addItem(save)

        let ocr = NSMenuItem(title: "识别文字", action: #selector(recognizeText), keyEquivalent: "o")
        ocr.target = self
        menu.addItem(ocr)

        menu.addItem(.separator())

        let opacityItem = NSMenuItem(title: "透明度", action: nil, keyEquivalent: "")
        let opacityMenu = NSMenu()
        for value in [1.0, 0.8, 0.6, 0.4, 0.25] {
            let item = NSMenuItem(title: "\(Int(value * 100))%", action: #selector(setOpacity(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int(value * 100)
            opacityMenu.addItem(item)
        }
        opacityItem.submenu = opacityMenu
        menu.addItem(opacityItem)

        menu.addItem(.separator())

        let close = NSMenuItem(title: "关闭", action: #selector(closeSelf), keyEquivalent: "w")
        close.target = self
        menu.addItem(close)

        let closeAll = NSMenuItem(title: "关闭全部贴图", action: #selector(closeAllPins), keyEquivalent: "")
        closeAll.target = self
        menu.addItem(closeAll)

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func copyImage() {
        ImageOutput.copyToPasteboard(image)
        if let window { Toast.show("已复制", near: window.frame) }
    }

    @objc private func saveImage() {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = ImageOutput.defaultFilename()
        panel.directoryURL = ImageOutput.defaultDirectory()
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            if ImageOutput.writePNG(self.image, to: url) {
                Toast.show("已保存", near: window.frame)
            }
        }
    }

    @objc private func recognizeText() {
        guard let window else { return }
        let rect = window.frame
        Task { @MainActor in
            let result = await OCRService.recognize(in: self.image)
            if result.text.isEmpty {
                Toast.show("没有识别到文字", near: rect)
            } else {
                OCRResultPanel.show(result.text, near: rect)
            }
        }
    }

    @objc private func setOpacity(_ sender: NSMenuItem) {
        window?.alphaValue = CGFloat(sender.tag) / 100
    }

    @objc private func closeSelf() {
        windowRef?.closePin()
    }

    @objc private func closeAllPins() {
        PinController.shared.closeAll()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            windowRef?.closePin()
            return
        }
        super.keyDown(with: event)
    }

    // MARK: - Drag out to other apps

    private func beginDragOut(with event: NSEvent) {
        guard let window, let url = windowRef?.prepareDragFile() else { return }
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(bounds, contents: ImageOutput.tiffData(image).flatMap { NSImage(data: $0) })
        beginDraggingSession(with: [item], event: event, source: self)
    }

    nonisolated func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}
