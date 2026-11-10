import AppKit

/// A small field that records a key combination when clicked.
@MainActor
final class ShortcutRecorderView: NSView {
    var combo: KeyCombo? {
        didSet { needsDisplay = true }
    }

    /// Called after a new combination is recorded (nil = cleared).
    var onChange: ((KeyCombo?) -> Void)?

    var placeholder = "点击设置"
    private(set) var isRecording = false {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        toolTip = "点击后按下新的快捷键；Esc 取消，⌫ 清除"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        true
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == 53 { // esc cancels
            finish()
            return
        }
        if event.keyCode == 51 || event.keyCode == 117 { // delete clears
            combo = nil
            finish()
            onChange?(nil)
            return
        }

        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let recorded = KeyCombo(
            keyCode: UInt32(event.keyCode),
            modifiers: modifiers,
            display: KeyNames.symbols(for: modifiers)
                + KeyNames.name(for: UInt32(event.keyCode), characters: event.charactersIgnoringModifiers)
        )
        combo = recorded
        finish()
        onChange?(recorded)
    }

    private func finish() {
        isRecording = false
        window?.makeFirstResponder(nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        if isRecording {
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
        } else {
            NSColor.quaternaryLabelColor.withAlphaComponent(0.18).setFill()
        }
        path.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = isRecording ? 1.5 : 1
        path.stroke()

        let text: String
        let color: NSColor
        if isRecording {
            text = "按下快捷键…"
            color = .controlAccentColor
        } else if let combo {
            text = combo.display
            color = .labelColor
        } else {
            text = placeholder
            color = .tertiaryLabelColor
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: color
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(
            at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
            withAttributes: attributes
        )
    }
}
