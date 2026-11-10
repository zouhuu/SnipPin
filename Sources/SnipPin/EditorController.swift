import AppKit
import UniformTypeIdentifiers

final class EditorWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class EditorController: NSObject, CanvasDelegate, NSTextFieldDelegate {
    private let image: CGImage
    private let captureRect: CGRect
    private let scale: CGFloat

    private var imageWindow: EditorWindow?
    private var toolbarWindow: NSPanel?
    private var canvas: CanvasView?
    private var toolbar: ToolbarView?
    private var keyMonitor: Any?
    private var spaceMonitor: Any?
    private var textField: NSTextField?
    private var closed = false

    var onClose: (() -> Void)?

    /// Current on-screen frame of the image (it can be dragged around).
    private var currentRect: CGRect { imageWindow?.frame ?? captureRect }

    private var exportOptions = ExportOptions.load()
    private var originalKB = 0
    private var sizePopover: NSPopover?
    private var sizePanel: ExportSizePanel?
    private var sizeWork: DispatchWorkItem?
    private var sizeGeneration = 0

    private let palette: [NSColor] = [
        NSColor(calibratedRed: 0.94, green: 0.27, blue: 0.27, alpha: 1),
        NSColor(calibratedRed: 0.98, green: 0.75, blue: 0.18, alpha: 1),
        NSColor(calibratedRed: 0.22, green: 0.78, blue: 0.45, alpha: 1),
        NSColor(calibratedRed: 0.23, green: 0.51, blue: 0.96, alpha: 1),
        .white,
        NSColor(calibratedWhite: 0.1, alpha: 1)
    ]
    private var colorIndex = 0
    private(set) var currentColor: NSColor

    init(image: CGImage, captureRect: CGRect, scale: CGFloat) {
        self.image = image
        self.captureRect = captureRect
        self.scale = scale
        self.currentColor = palette[0]
        super.init()
    }

    // MARK: - Lifecycle

    func present() {
        guard imageWindow == nil else { return }
        NSApp.activate(ignoringOtherApps: true)

        let size = captureRect.size
        let window = EditorWindow(
            contentRect: CGRect(origin: captureRect.origin, size: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .statusBar
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.acceptsMouseMovedEvents = true

        let canvas = CanvasView(cgImage: image, pointSize: size)
        canvas.frame = CGRect(origin: .zero, size: size)
        canvas.delegate = self
        canvas.color = currentColor
        canvas.onChange = { [weak self] in self?.scheduleSizeRefresh() }
        window.contentView = canvas
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)

        self.imageWindow = window
        self.canvas = canvas

        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: CGSize(width: ToolbarView.width, height: ToolbarView.height)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let toolbar = ToolbarView(editor: self)
        toolbar.frame = CGRect(origin: .zero, size: CGSize(width: ToolbarView.width, height: ToolbarView.height))
        panel.contentView = toolbar
        position(toolbar: panel)
        panel.orderFrontRegardless()

        self.toolbarWindow = panel
        self.toolbar = toolbar
        toolbar.setSize(text: "…", warning: false)

        window.addChildWindow(panel, ordered: .above)

        installKeyMonitor()
        computeOriginalSize()
        scheduleSizeRefresh(immediate: true)
    }

    private func position(toolbar panel: NSPanel) {
        let rect = currentRect
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(rect) }) ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        var origin = CGPoint(
            x: rect.midX - size.width / 2,
            y: rect.minY - size.height - 10
        )
        if origin.y < visible.minY + 8 {
            origin.y = rect.maxY + 10
        }
        if origin.y + size.height > visible.maxY - 8 {
            origin.y = max(visible.minY + 8, rect.minY + 10)
        }
        origin.x = max(visible.minX + 8, min(origin.x, visible.maxX - size.width - 8))
        // The panel is a child window: coordinates are still screen coordinates.
        panel.setFrameOrigin(origin)
    }

    func close() {
        guard !closed else { return }
        closed = true
        sizeWork?.cancel()
        sizeWork = nil
        sizePopover?.close()
        sizePopover = nil
        sizePanel = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let spaceMonitor { NSEvent.removeMonitor(spaceMonitor) }
        spaceMonitor = nil
        textField?.removeFromSuperview()
        textField = nil
        if let toolbarWindow {
            imageWindow?.removeChildWindow(toolbarWindow)
            toolbarWindow.orderOut(nil)
            toolbarWindow.close()
        }
        toolbarWindow = nil
        toolbar = nil
        imageWindow?.orderOut(nil)
        imageWindow?.close()
        imageWindow = nil
        canvas = nil
        let callback = onClose
        onClose = nil
        callback?()
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, !self.closed else { return event }
            // Only react when one of the editor's own windows is key, otherwise typing in
            // the OCR panel / shortcut settings would switch tools instead.
            if let keyWindow = NSApp.keyWindow,
               keyWindow !== self.imageWindow,
               keyWindow !== self.toolbarWindow,
               keyWindow !== self.sizePopover?.contentViewController?.view.window {
                return event
            }
            if self.imageWindow?.attachedSheet != nil { return event }
            if self.textField != nil { return event }
            // Let the size panel's field receive typing; keep command shortcuts alive.
            if self.sizePopover?.isShown == true, !event.modifierFlags.contains(.command) {
                return event
            }
            if event.keyCode == 49 { // space = temporary hand tool
                self.canvas?.setSpaceHeld(true)
                return nil
            }

            if event.keyCode == 53 {
                self.close()
                return nil
            }
            if event.keyCode == 36 || event.keyCode == 76 {
                self.copyImage()
                return nil
            }

            let characters = event.charactersIgnoringModifiers?.lowercased() ?? ""
            if event.modifierFlags.contains(.command) {
                switch characters {
                case "z": self.undo(); return nil
                case "c": self.copyImage(); return nil
                case "s": self.saveImage(); return nil
                case "p": self.pinImage(); return nil
                case "o": self.runOCR(); return nil
                case "w": self.close(); return nil
                default: return event
                }
            }

            if event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
               let tool = ShortcutStore.shared.tool(forKeyCode: UInt32(event.keyCode)) {
                self.select(tool: tool)
                return nil
            }
            return event
        }

        spaceMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            if event.keyCode == 49 { self?.canvas?.setSpaceHeld(false) }
            return event
        }
    }

    // MARK: - Tools

    func select(tool: Tool) {
        canvas?.tool = tool
        toolbar?.selectedTool = tool
    }

    func cycleColor() {
        colorIndex = (colorIndex + 1) % palette.count
        currentColor = palette[colorIndex]
        canvas?.color = currentColor
        toolbar?.refreshColor(currentColor)
    }

    func undo() {
        canvas?.undo()
        toolbar?.canUndo = !(canvas?.annotations.isEmpty ?? true)
    }

    // MARK: - Export size

    func showSizePopover(relativeTo button: NSView) {
        if let popover = sizePopover, popover.isShown {
            popover.close()
            sizePopover = nil
            sizePanel = nil
            return
        }
        let panel = ExportSizePanel(
            options: exportOptions,
            originalKB: originalKB,
            width: canvas?.cgImage.width ?? 0,
            height: canvas?.cgImage.height ?? 0
        )
        panel.onChange = { [weak self] options in self?.applyExportOptions(options) }
        panel.onAuto = { [weak self] in self?.autoFitSize() }
        panel.onReset = { [weak self] in self?.resetExportOptions() }

        let popover = NSPopover()
        popover.contentViewController = panel
        popover.behavior = .semitransient
        popover.animates = true
        popover.contentSize = ExportSizePanel.panelSize
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        sizePopover = popover
        sizePanel = panel
        refreshSize()
        if originalKB <= 0 { computeOriginalSize() }
    }

    /// Moves the floating image (used by the live smoke test).
    func moveEditorForTesting(by delta: CGSize) {
        guard let window = imageWindow else { return }
        var frame = window.frame
        frame.origin.x += delta.width
        frame.origin.y += delta.height
        window.setFrame(frame, display: true)
        if let panel = toolbarWindow { position(toolbar: panel) }
    }

    /// Opens the size popover programmatically (used by the live smoke test).
    func showSizePanelForTesting() {
        guard let button = toolbar?.sizeButtonView else { return }
        showSizePopover(relativeTo: button)
    }

    private func applyExportOptions(_ options: ExportOptions) {
        exportOptions = options
        options.save()
        scheduleSizeRefresh()
    }

    private func resetExportOptions() {
        exportOptions = ExportOptions()
        exportOptions.save()
        sizePanel?.sync(exportOptions)
        scheduleSizeRefresh(immediate: true)
    }

    private func autoFitSize() {
        guard let target = exportOptions.maxKB, target > 0 else {
            Toast.show("请先填写目标大小（KB）", near: currentRect)
            return
        }
        guard let image = canvas?.exportImage() else { return }
        let options = exportOptions
        sizePanel?.setBusy(true)
        Task.detached(priority: .userInitiated) {
            let result = ImageExporter.fit(image, options: options, maxKB: target)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.sizePanel?.setBusy(false)
                guard let result else {
                    Toast.show("压缩失败", near: self.captureRect)
                    return
                }
                self.exportOptions.format = result.format
                self.exportOptions.quality = result.quality
                self.exportOptions.scale = result.scale
                self.exportOptions.save()
                self.sizeGeneration += 1
                self.sizePanel?.sync(self.exportOptions)
                self.sizePanel?.updateOutput(
                    "输出 \(result.kbText) · \(result.pixelWidth) × \(result.pixelHeight)",
                    warning: false
                )
                self.toolbar?.setSize(text: result.kbText, warning: false)
                Toast.show("已压缩到 \(result.kbText)", near: self.captureRect)
            }
        }
    }

    private func scheduleSizeRefresh(immediate: Bool = false) {
        sizeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refreshSize() }
        sizeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (immediate ? 0.02 : 0.35), execute: work)
    }

    private func refreshSize() {
        guard let image = canvas?.exportImage() else { return }
        let options = exportOptions
        sizeGeneration += 1
        let generation = sizeGeneration
        toolbar?.setSize(text: "…", warning: false)
        Task.detached(priority: .userInitiated) {
            let result = ImageExporter.encode(image, options: options)
            await MainActor.run { [weak self] in
                guard let self, generation == self.sizeGeneration else { return }
                guard let result else {
                    self.toolbar?.setSize(text: "—", warning: false)
                    self.sizePanel?.updateOutput("无法编码", warning: true)
                    return
                }
                let limit = (options.maxKB ?? 0) * 1024
                let over = limit > 0 && result.bytes > limit
                self.toolbar?.setSize(text: result.kbText, warning: over)
                let suffix = over ? " · 超出目标 \(options.maxKB ?? 0) KB" : ""
                self.sizePanel?.updateOutput(
                    "输出 \(result.kbText) · \(result.pixelWidth) × \(result.pixelHeight)\(suffix)",
                    warning: over
                )
            }
        }
    }

    private func computeOriginalSize() {
        guard let image = canvas?.exportImage() else { return }
        Task.detached(priority: .utility) {
            let kb = ImageExporter.encode(image, format: .png, quality: 1, scale: 1)
                .map { max(1, $0.bytes / 1024) }
            await MainActor.run { [weak self] in
                guard let self, let kb else { return }
                self.originalKB = kb
                self.sizePanel?.updateOriginal(kb: kb)
            }
        }
    }

    // MARK: - Output

    private func flattened() -> CGImage? {
        if textField != nil { commitText() }
        guard let flat = canvas?.exportImage() else {
            Toast.show("导出的图片为空")
            return nil
        }
        return flat
    }

    func copyImage() {
        guard let flat = flattened() else { return }
        let options = exportOptions
        if options.maxKB != nil { Toast.show("正在压缩…", near: currentRect) }
        Task.detached(priority: .userInitiated) {
            let result = ImageExporter.resolve(flat, options: options)
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard let result else {
                    Toast.show("导出失败", near: self.captureRect)
                    return
                }
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setData(result.data, forType: result.format.pasteboardType)
                Toast.show("已复制 · \(result.kbText)", near: self.captureRect)
                self.close()
            }
        }
    }

    func saveImage() {
        guard let flat = flattened() else { return }
        let format = exportOptions.format
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.utType]
        panel.nameFieldStringValue = ImageOutput.defaultFilename(ext: format.fileExtension)
        panel.directoryURL = ImageOutput.defaultDirectory()
        panel.canCreateDirectories = true
        guard let window = imageWindow else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            let options = self.exportOptions
            if options.maxKB != nil { Toast.show("正在压缩…", near: self.captureRect) }
            Task.detached(priority: .userInitiated) {
                let result = ImageExporter.resolve(flat, options: options)
                let written = result.flatMap { try? $0.data.write(to: url) } != nil
                await MainActor.run {
                    if written, let result {
                        Toast.show("已保存 · \(result.kbText)", near: self.captureRect)
                        self.close()
                    } else {
                        Toast.show("保存失败", near: self.captureRect)
                    }
                }
            }
        }
    }

    func pinImage() {
        guard let flat = flattened() else { return }
        let rect = currentRect
        PinController.shared.pin(image: flat, at: CGPoint(x: rect.minX, y: rect.maxY), scale: scale)
        Toast.show("已贴到屏幕", near: rect)
        close()
    }

    func runOCR() {
        guard let flat = flattened() else { return }
        let rect = captureRect
        Task { @MainActor in
            let result = await OCRService.recognize(in: flat)
            if result.text.isEmpty {
                Toast.show("没有识别到文字", near: rect)
            } else {
                OCRResultPanel.show(result.text, near: rect)
            }
        }
    }

    /// Adds a few annotations for the live smoke test.
    func loadDemoAnnotations() {
        guard let canvas else { return }
        canvas.addForPreview([
            Annotation(tool: .rect, points: [CGPoint(x: 30, y: 40), CGPoint(x: 300, y: 150)], color: currentColor, lineWidth: 3),
            Annotation(tool: .arrow, points: [CGPoint(x: 120, y: 250), CGPoint(x: 260, y: 190)], color: NSColor(calibratedRed: 0.23, green: 0.51, blue: 0.96, alpha: 1), lineWidth: 3),
            Annotation(tool: .text, points: [CGPoint(x: 34, y: 176)], color: currentColor, lineWidth: 3, text: "SnipPin 实机测试", fontSize: 20)
        ])
    }

    // MARK: - CanvasDelegate

    var canvasIsEditingText: Bool { textField != nil }

    func canvasDidDoubleClick() {
        copyImage()
    }

    func canvasDidFinishMoving() {
        if let panel = toolbarWindow { position(toolbar: panel) }
    }

    func canvasDidRequestText(at point: CGPoint) {
        commitText()
        guard let canvas else { return }
        let field = NSTextField(frame: CGRect(x: point.x, y: point.y, width: 140, height: 28))
        field.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        field.textColor = currentColor
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.placeholderString = "输入文字，回车确认"
        field.delegate = self
        field.cell?.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        canvas.addSubview(field)
        textField = field
        imageWindow?.makeFirstResponder(field)
        if let editor = field.currentEditor() {
            editor.selectedRange = NSRange(location: 0, length: 0)
        }
    }

    private func commitText() {
        guard let field = textField else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let origin = field.frame.origin
        textField = nil
        field.removeFromSuperview()
        imageWindow?.makeFirstResponder(canvas)
        if !text.isEmpty {
            canvas?.addText(text, at: origin)
        }
    }

    private func cancelText() {
        guard let field = textField else { return }
        textField = nil
        field.removeFromSuperview()
        imageWindow?.makeFirstResponder(canvas)
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        guard let field = textField, let font = field.font else { return }
        let width = (field.stringValue as NSString).size(withAttributes: [.font: font]).width
        var frame = field.frame
        frame.size.width = max(140, width + 16)
        frame.size.width = min(frame.size.width, (canvas?.bounds.width ?? captureRect.width) - frame.minX)
        field.frame = frame
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        if textField != nil { commitText() }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            commitText()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelText()
            return true
        }
        return false
    }
}
