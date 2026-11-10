import AppKit

@MainActor
final class ExportSizePanel: NSViewController, NSTextFieldDelegate {
    var onChange: ((ExportOptions) -> Void)?
    var onAuto: (() -> Void)?
    var onReset: (() -> Void)?

    private(set) var options: ExportOptions
    private let originalKB: Int
    private let pixelSize: (width: Int, height: Int)

    private let originalLabel = NSTextField(labelWithString: "")
    private let formatControl = NSSegmentedControl(
        labels: ["PNG", "JPEG"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let qualitySlider = NSSlider()
    private let qualityValue = NSTextField(labelWithString: "80%")
    private let scaleSlider = NSSlider()
    private let scaleValue = NSTextField(labelWithString: "100%")
    private let targetField = NSTextField()
    private let autoButton = NSButton()
    private let outputLabel = NSTextField(labelWithString: "正在计算…")
    private let resetButton = NSButton()

    static let panelSize = CGSize(width: 324, height: 292)

    init(options: ExportOptions, originalKB: Int, width: Int, height: Int) {
        self.options = options
        self.originalKB = originalKB
        self.pixelSize = (width, height)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = NSView(frame: CGRect(origin: .zero, size: Self.panelSize))
        root.wantsLayer = true
        view = root

        let title = NSTextField(labelWithString: "图片大小")
        title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        title.frame = CGRect(x: 16, y: 258, width: 200, height: 18)
        root.addSubview(title)

        originalLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        originalLabel.textColor = .secondaryLabelColor
        originalLabel.frame = CGRect(x: 16, y: 238, width: 292, height: 15)
        root.addSubview(originalLabel)
        updateOriginalLabel()

        let formatLabel = makeRowLabel("格式", y: 206)
        root.addSubview(formatLabel)
        formatControl.target = self
        formatControl.action = #selector(formatChanged)
        formatControl.selectedSegment = options.format == .png ? 0 : 1
        formatControl.frame = CGRect(x: 68, y: 199, width: 154, height: 24)
        root.addSubview(formatControl)

        let qualityLabel = makeRowLabel("质量", y: 172)
        root.addSubview(qualityLabel)
        qualitySlider.minValue = 5
        qualitySlider.maxValue = 100
        qualitySlider.doubleValue = options.quality * 100
        qualitySlider.isContinuous = true
        qualitySlider.target = self
        qualitySlider.action = #selector(sliderChanged)
        qualitySlider.frame = CGRect(x: 68, y: 173, width: 154, height: 20)
        root.addSubview(qualitySlider)
        styleValueLabel(qualityValue, y: 172)
        qualityValue.stringValue = "\(Int((options.quality * 100).rounded()))%"
        root.addSubview(qualityValue)

        let scaleLabel = makeRowLabel("缩放", y: 140)
        root.addSubview(scaleLabel)
        scaleSlider.minValue = 20
        scaleSlider.maxValue = 100
        scaleSlider.doubleValue = options.scale * 100
        scaleSlider.isContinuous = true
        scaleSlider.target = self
        scaleSlider.action = #selector(sliderChanged)
        scaleSlider.frame = CGRect(x: 68, y: 141, width: 154, height: 20)
        root.addSubview(scaleSlider)
        styleValueLabel(scaleValue, y: 140)
        scaleValue.stringValue = "\(Int((options.scale * 100).rounded()))%"
        root.addSubview(scaleValue)

        let targetLabel = makeRowLabel("目标", y: 105)
        targetLabel.stringValue = "目标 ≤"
        root.addSubview(targetLabel)
        targetField.frame = CGRect(x: 68, y: 102, width: 68, height: 22)
        targetField.alignment = .right
        targetField.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        targetField.placeholderString = "不限"
        targetField.delegate = self
        targetField.target = self
        targetField.action = #selector(targetCommitted)
        if let maxKB = options.maxKB { targetField.stringValue = "\(maxKB)" }
        root.addSubview(targetField)
        let kbLabel = NSTextField(labelWithString: "KB")
        kbLabel.font = NSFont.systemFont(ofSize: 11)
        kbLabel.textColor = .secondaryLabelColor
        kbLabel.frame = CGRect(x: 140, y: 107, width: 24, height: 15)
        root.addSubview(kbLabel)

        autoButton.title = "自动压缩"
        autoButton.bezelStyle = .rounded
        autoButton.controlSize = .small
        autoButton.font = NSFont.systemFont(ofSize: 11)
        autoButton.target = self
        autoButton.action = #selector(autoTapped)
        autoButton.frame = CGRect(x: 168, y: 99, width: 88, height: 26)
        root.addSubview(autoButton)

        outputLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        outputLabel.frame = CGRect(x: 16, y: 62, width: 292, height: 18)
        root.addSubview(outputLabel)

        resetButton.title = "恢复原图"
        resetButton.bezelStyle = .inline
        resetButton.controlSize = .small
        resetButton.font = NSFont.systemFont(ofSize: 11)
        resetButton.target = self
        resetButton.action = #selector(resetTapped)
        resetButton.frame = CGRect(x: 12, y: 24, width: 88, height: 22)
        root.addSubview(resetButton)

        let hint = NSTextField(labelWithString: "复制与保存都使用这里的设置")
        hint.font = NSFont.systemFont(ofSize: 10)
        hint.textColor = .tertiaryLabelColor
        hint.frame = CGRect(x: 104, y: 28, width: 210, height: 14)
        root.addSubview(hint)

        updateQualityEnabled()
    }

    private func makeRowLabel(_ text: String, y: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.frame = CGRect(x: 16, y: y, width: 46, height: 16)
        return label
    }

    private func styleValueLabel(_ label: NSTextField, y: CGFloat) {
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        label.frame = CGRect(x: 228, y: y, width: 76, height: 16)
    }

    // MARK: - Updates from the editor

    func sync(_ options: ExportOptions) {
        self.options = options
        _ = view
        formatControl.selectedSegment = options.format == .png ? 0 : 1
        qualitySlider.doubleValue = options.quality * 100
        scaleSlider.doubleValue = options.scale * 100
        qualityValue.stringValue = "\(Int((options.quality * 100).rounded()))%"
        scaleValue.stringValue = "\(Int((options.scale * 100).rounded()))%"
        targetField.stringValue = options.maxKB.map(String.init) ?? ""
        updateQualityEnabled()
    }

    func updateOriginal(kb: Int) {
        if kb > 0 {
            originalLabel.stringValue = "原图 PNG \(kb) KB · \(pixelSize.width) × \(pixelSize.height)"
        } else {
            originalLabel.stringValue = "原图 PNG 计算中… · \(pixelSize.width) × \(pixelSize.height)"
        }
    }

    func updateOutput(_ text: String, warning: Bool) {
        outputLabel.stringValue = text
        outputLabel.textColor = warning ? .systemOrange : .labelColor
    }

    func setBusy(_ busy: Bool) {
        autoButton.title = busy ? "压缩中…" : "自动压缩"
        autoButton.isEnabled = !busy
        formatControl.isEnabled = !busy
        qualitySlider.isEnabled = !busy && options.format == .jpeg
        scaleSlider.isEnabled = !busy
    }

    private func updateOriginalLabel() {
        updateOriginal(kb: originalKB)
    }

    private func updateQualityEnabled() {
        qualitySlider.isEnabled = options.format == .jpeg
        qualityValue.textColor = options.format == .jpeg ? .secondaryLabelColor : .tertiaryLabelColor
    }

    // MARK: - Actions

    @objc private func formatChanged() {
        options.format = formatControl.selectedSegment == 0 ? .png : .jpeg
        updateQualityEnabled()
        emit()
    }

    @objc private func sliderChanged() {
        options.quality = qualitySlider.doubleValue / 100
        options.scale = scaleSlider.doubleValue / 100
        qualityValue.stringValue = "\(Int(qualitySlider.doubleValue.rounded()))%"
        scaleValue.stringValue = "\(Int(scaleSlider.doubleValue.rounded()))%"
        emit()
    }

    @objc private func targetCommitted() {
        view.window?.makeFirstResponder(nil)
        emit()
    }

    @objc private func autoTapped() {
        onAuto?()
    }

    @objc private func resetTapped() {
        onReset?()
    }

    private func emit() {
        let raw = targetField.stringValue.trimmingCharacters(in: .whitespaces)
        options.maxKB = Int(raw).flatMap { $0 > 0 ? $0 : nil }
        onChange?(options)
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        emit()
    }
}
