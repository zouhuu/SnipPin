import AppKit

/// Small icon button used inside the floating editor toolbar.
final class ToolButton: NSView {
    private let iconView = NSImageView()
    private let symbol: String
    var onClick: (() -> Void)?
    var isActive = false { didSet { needsDisplay = true } }
    var isEnabled = true { didSet { needsDisplay = true; iconView.alphaValue = isEnabled ? 1 : 0.35 } }
    private var isHovered = false { didSet { needsDisplay = true } }

    init(symbol: String, tooltip: String, pointSize: CGFloat = 14, size: CGFloat = 28) {
        self.symbol = symbol
        super.init(frame: CGRect(x: 0, y: 0, width: size, height: size))
        toolTip = tooltip

        let base = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
            ?? NSImage(systemSymbolName: "hand.raised", accessibilityDescription: tooltip)
        iconView.image = base?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium))
        iconView.image?.isTemplate = true
        iconView.contentTintColor = NSColor.white.withAlphaComponent(0.92)
        iconView.imageScaling = .scaleProportionallyDown
        iconView.frame = bounds.insetBy(dx: 7, dy: 7)
        iconView.autoresizingMask = [.width, .height]
        addSubview(iconView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

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
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func mouseDown(with event: NSEvent) {
        // Consume; the action fires on mouse-up so closing the editor is safe.
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        let action = onClick
        DispatchQueue.main.async { action?() }
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        if isActive {
            NSColor(calibratedRed: 0.23, green: 0.51, blue: 0.96, alpha: 1).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        } else if isHovered, isEnabled {
            NSColor.white.withAlphaComponent(0.16).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        }
    }
}

final class ColorButton: NSView {
    var color: NSColor = .systemRed { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?
    private var isHovered = false { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = "颜色（点击切换）"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

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
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func mouseDown(with event: NSEvent) { onClick?() }

    override func draw(_ dirtyRect: NSRect) {
        if isHovered {
            NSColor.white.withAlphaComponent(0.16).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6).fill()
        }
        let dot = bounds.insetBy(dx: 8, dy: 8)
        color.setFill()
        NSBezierPath(ovalIn: dot).fill()
        NSColor.white.withAlphaComponent(0.75).setStroke()
        let ring = NSBezierPath(ovalIn: dot.insetBy(dx: -0.5, dy: -0.5))
        ring.lineWidth = 1
        ring.stroke()
    }
}


/// Shows the current output size in KB; clicking opens the export-size panel.
final class SizeButton: NSView {
    var text = "…" { didSet { needsDisplay = true } }
    var warning = false { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?
    private var isHovered = false { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = "图片大小 · 点击调整保存大小（KB）"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

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
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        let action = onClick
        DispatchQueue.main.async { action?() }
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        if isHovered {
            NSColor.white.withAlphaComponent(0.16).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        }
        let color: NSColor = warning
            ? NSColor.systemOrange
            : NSColor.white.withAlphaComponent(text == "…" ? 0.45 : 0.95)
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(
            at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
            withAttributes: attributes
        )
    }
}

/// The floating tool palette that sits under (or above) the capture.
final class ToolbarView: NSView {
    static let height: CGFloat = 38
    static let width: CGFloat = 546

    weak var editor: EditorController?
    private var toolButtons: [Tool: ToolButton] = [:]
    private var colorButton = ColorButton(frame: .zero)
    private var undoButton: ToolButton!
    private var actionButtons: [ToolButton] = []
    private let separator = NSView()
    private let sizeButton = SizeButton(frame: .zero)

    var selectedTool: Tool = .rect {
        didSet {
            for (tool, button) in toolButtons { button.isActive = (tool == selectedTool) }
        }
    }

    var canUndo: Bool = false {
        didSet { undoButton?.isEnabled = canUndo }
    }

    init(editor: EditorController) {
        self.editor = editor
        super.init(frame: CGRect(x: 0, y: 0, width: Self.width, height: Self.height))
        wantsLayer = true

        sizeButton.onClick = { [weak self] in
            guard let self else { return }
            self.editor?.showSizePopover(relativeTo: self.sizeButton)
        }
        addSubview(sizeButton)

        colorButton.color = editor.currentColor
        colorButton.onClick = { [weak self] in self?.editor?.cycleColor() }
        addSubview(colorButton)

        for tool in Tool.allCases {
            let key = ShortcutStore.shared.display(forTool: tool) ?? "—"
            let hint = tool == .move ? "移动  \(key)（或按住空格拖动）" : "\(tool.title)  \(key)"
            let button = ToolButton(symbol: tool.symbol, tooltip: hint)
            button.onClick = { [weak self] in self?.editor?.select(tool: tool) }
            button.isActive = (tool == selectedTool)
            toolButtons[tool] = button
            addSubview(button)
        }

        undoButton = ToolButton(symbol: "arrow.uturn.backward", tooltip: "撤销  ⌘Z")
        undoButton.isEnabled = false
        undoButton.onClick = { [weak self] in self?.editor?.undo() }
        addSubview(undoButton)
        actionButtons.append(undoButton)

        let copy = ToolButton(symbol: "doc.on.doc", tooltip: "复制  ⌘C / 回车")
        copy.onClick = { [weak self] in self?.editor?.copyImage() }
        addSubview(copy)
        actionButtons.append(copy)

        let save = ToolButton(symbol: "square.and.arrow.down", tooltip: "保存  ⌘S")
        save.onClick = { [weak self] in self?.editor?.saveImage() }
        addSubview(save)
        actionButtons.append(save)

        let pin = ToolButton(symbol: "pin", tooltip: "贴图到屏幕  ⌘P")
        pin.onClick = { [weak self] in self?.editor?.pinImage() }
        addSubview(pin)
        actionButtons.append(pin)

        let ocr = ToolButton(symbol: "text.viewfinder", tooltip: "识别文字  ⌘O")
        ocr.onClick = { [weak self] in self?.editor?.runOCR() }
        addSubview(ocr)
        actionButtons.append(ocr)

        let close = ToolButton(symbol: "xmark", tooltip: "关闭  Esc")
        close.onClick = { [weak self] in self?.editor?.close() }
        addSubview(close)
        actionButtons.append(close)

        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
        addSubview(separator)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        NSColor(calibratedWhite: 0.11, alpha: 0.94).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    func refreshColor(_ color: NSColor) {
        colorButton.color = color
    }

    func setSize(text: String, warning: Bool) {
        sizeButton.text = text
        sizeButton.warning = warning
    }

    var sizeButtonView: NSView { sizeButton }

    override func layout() {
        super.layout()
        var x: CGFloat = 9
        let size: CGFloat = 28
        let y: CGFloat = (Self.height - size) / 2

        sizeButton.frame = CGRect(x: x, y: y, width: 58, height: size)
        x += 58 + 6

        colorButton.frame = CGRect(x: x, y: y, width: size, height: size)
        x += size + 4

        for tool in Tool.allCases {
            guard let button = toolButtons[tool] else { continue }
            button.frame = CGRect(x: x, y: y, width: size, height: size)
            x += size + 2
        }

        x += 8
        separator.frame = CGRect(x: x, y: 8, width: 1, height: Self.height - 16)
        x += 9

        for button in actionButtons {
            button.frame = CGRect(x: x, y: y, width: size, height: size)
            x += size + 1
        }
    }

}
