import AppKit

struct SelectionResult {
    let image: CGImage
    /// Selection in screen (global, bottom-left origin) points.
    let screenRect: CGRect
    let screen: NSScreen
    let scale: CGFloat
}

/// Full-screen frozen-desktop overlay that lets the user drag out a capture region.
@MainActor
final class SelectionController {
    static let shared = SelectionController()

    private var windows: [SelectionWindow] = []
    private var views: [SelectionView] = []
    private var keyMonitor: Any?
    private var completion: ((SelectionResult?) -> Void)?
    private var isActive = false

    var active: Bool { isActive }

    func begin(shots: [ScreenShot], completion: @escaping (SelectionResult?) -> Void) {
        guard !isActive else { return }
        isActive = true
        self.completion = completion

        NSApp.activate(ignoringOtherApps: true)

        let mouse = NSEvent.mouseLocation
        for shot in shots {
            let window = SelectionWindow(
                contentRect: shot.screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.setFrame(shot.screen.frame, display: false)
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.acceptsMouseMovedEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.ignoresMouseEvents = false

            let view = SelectionView(shot: shot, controller: self)
            view.frame = CGRect(origin: .zero, size: shot.screen.frame.size)
            window.contentView = view
            windows.append(window)
            views.append(view)
        }

        for (index, window) in windows.enumerated() {
            window.orderFrontRegardless()
            if shots[index].screen.frame.contains(mouse) {
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(views[index])
                views[index].cursorPoint = views[index].convertWindowPoint(mouse)
            }
        }
        windows.first?.makeKey()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isActive else { return event }
            if event.keyCode == 53 { // esc
                self.cancel()
                return nil
            }
            if event.charactersIgnoringModifiers?.lowercased() == "c" {
                self.copyColorUnderCursor()
                return nil
            }
            return event
        }
    }

    func finish(_ view: SelectionView) {
        guard isActive else { return }
        let rect = view.selectionRect.intersection(view.bounds).integral
        guard rect.width >= 2, rect.height >= 2 else {
            cancel()
            return
        }
        let shot = view.shot
        let pixelRect = shot.pixelRect(forPointRect: rect)
        guard let cropped = shot.image.cropping(to: pixelRect) else {
            cancel()
            return
        }
        let screenRect = CGRect(
            x: shot.screen.frame.minX + rect.minX,
            y: shot.screen.frame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
        let result = SelectionResult(image: cropped, screenRect: screenRect, screen: shot.screen, scale: shot.scale)
        end(with: result)
    }

    func cancel() { end(with: nil) }

    private func end(with result: SelectionResult?) {
        guard isActive else { return }
        isActive = false
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        views.removeAll()
        let callback = completion
        completion = nil
        callback?(result)
    }

    private func copyColorUnderCursor() {
        guard let view = views.first(where: { $0.window?.isKeyWindow == true }) ?? views.first else { return }
        view.copyColorAtCursor()
    }
}

final class SelectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class SelectionView: NSView {
    let shot: ScreenShot
    private weak var controller: SelectionController?

    private(set) var selectionRect: CGRect = .zero
    var cursorPoint: CGPoint = .zero
    private var isDragging = false
    private var dragStart: CGPoint = .zero
    private var showsCursor = true
    private lazy var sampler = PixelSampler(image: shot.image)

    private let dimAlpha: CGFloat = 0.55

    init(shot: ScreenShot, controller: SelectionController) {
        self.shot = shot
        self.controller = controller
        super.init(frame: CGRect(origin: .zero, size: shot.screen.frame.size))
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    func convertWindowPoint(_ point: CGPoint) -> CGPoint {
        convert(point, from: nil)
    }

    // MARK: - Mouse

    override func mouseMoved(with event: NSEvent) {
        cursorPoint = convert(event.locationInWindow, from: nil)
        showsCursor = true
        needsDisplay = true
    }

    override func mouseEntered(with event: NSEvent) {
        cursorPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        dragStart = clamp(convert(event.locationInWindow, from: nil))
        selectionRect = .zero
        isDragging = true
        showsCursor = false
        cursorPoint = dragStart
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let current = clamp(convert(event.locationInWindow, from: nil))
        cursorPoint = current
        selectionRect = CGRect(
            x: min(dragStart.x, current.x),
            y: min(dragStart.y, current.y),
            width: abs(current.x - dragStart.x),
            height: abs(current.y - dragStart.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        let rect = selectionRect.integral
        if rect.width >= 2, rect.height >= 2 {
            controller?.finish(self)
        } else {
            selectionRect = .zero
            showsCursor = true
            needsDisplay = true
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        controller?.cancel()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: controller?.cancel()
        case 36, 76: // return / enter
            if selectionRect.width >= 2 { controller?.finish(self) }
        default: super.keyDown(with: event)
        }
    }

    func copyColorAtCursor() {
        let px = Int(cursorPoint.x * shot.scale)
        let py = Int(cursorPoint.y * shot.scale)
        guard let color = sampler?.color(atPixelX: px, y: py) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(color.hexString, forType: .string)
        NSSound(named: "Tink")?.play()
    }

    /// Used by the offscreen preview renderer only.
    func configureForPreview(cursor: CGPoint, selection: CGRect) {
        cursorPoint = cursor
        selectionRect = selection
        showsCursor = selection.isEmpty
        needsDisplay = true
    }

    private func clamp(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), bounds.width), y: min(max(point.y, 0), bounds.height))
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let image = shot.image

        // Frozen screenshot.
        NSImage(cgImage: image, size: bounds.size).draw(in: bounds)

        // Dim everything, then re-reveal the selection.
        NSColor.black.withAlphaComponent(dimAlpha).setFill()
        NSBezierPath(rect: bounds).fill()

        if selectionRect.width > 0 {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: selectionRect).addClip()
            NSImage(cgImage: image, size: bounds.size).draw(in: bounds)
            NSGraphicsContext.restoreGraphicsState()
        }

        if !showsCursor, selectionRect.width > 0 {
            drawSelectionChrome(selectionRect)
        } else {
            drawCrosshair(at: cursorPoint)
        }

        if showsCursor {
            drawLoupe(near: cursorPoint, ctx: ctx)
            drawHint()
        }

        if isDragging, selectionRect.width > 0 {
            drawSizeChip(for: selectionRect, near: cursorPoint)
        }
    }

    private func drawCrosshair(at point: CGPoint) {
        NSColor.white.withAlphaComponent(0.45).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        path.setLineDash([4, 4], count: 2, phase: 0)
        path.move(to: CGPoint(x: 0, y: point.y + 0.5))
        path.line(to: CGPoint(x: bounds.width, y: point.y + 0.5))
        path.move(to: CGPoint(x: point.x + 0.5, y: 0))
        path.line(to: CGPoint(x: point.x + 0.5, y: bounds.height))
        path.stroke()
    }

    private func drawSelectionChrome(_ rect: CGRect) {
        let border = rect.insetBy(dx: 0.5, dy: 0.5)
        NSColor.white.withAlphaComponent(0.9).setStroke()
        let outer = NSBezierPath(rect: border)
        outer.lineWidth = 2
        outer.stroke()

        NSColor(calibratedRed: 0.23, green: 0.51, blue: 0.96, alpha: 1).setStroke()
        let inner = NSBezierPath(rect: border)
        inner.lineWidth = 1
        inner.stroke()

        // Corner marks.
        let arm: CGFloat = min(14, min(rect.width, rect.height) / 4)
        let corners: [(CGPoint, CGPoint, CGPoint)] = [
            (CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.minX + arm, y: rect.minY), CGPoint(x: rect.minX, y: rect.minY + arm)),
            (CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX - arm, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY + arm)),
            (CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.minX + arm, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY - arm)),
            (CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.maxX - arm, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY - arm))
        ]
        let accent = NSColor(calibratedRed: 0.23, green: 0.51, blue: 0.96, alpha: 1)
        for (corner, h, v) in corners {
            let path = NSBezierPath()
            path.lineWidth = 3
            path.lineCapStyle = .square
            path.move(to: h)
            path.line(to: corner)
            path.line(to: v)
            accent.setStroke()
            path.stroke()
        }
    }

    private func drawSizeChip(for rect: CGRect, near point: CGPoint) {
        let w = Int((rect.width * shot.scale).rounded())
        let h = Int((rect.height * shot.scale).rounded())
        let text = "\(w) × \(h)"
        var origin = CGPoint(x: rect.maxX - 96, y: rect.maxY + 8)
        if origin.y + 26 > bounds.height { origin.y = rect.maxY - 32 }
        if origin.x < 8 { origin.x = 8 }
        drawChip(text, at: origin, alignRight: false)
    }

    private func drawHint() {
        guard selectionRect.width == 0 else { return }
        let text = "拖动鼠标选择区域    Esc 取消    C 复制色值"
        drawChip(text, at: CGPoint(x: bounds.midX, y: 58), centered: true, small: true)
    }

    private func drawLoupe(near point: CGPoint, ctx: CGContext) {
        guard let sampler else { return }
        let loupe: CGFloat = 116
        let pixels: CGFloat = 12
        var origin = CGPoint(x: point.x + 22, y: point.y + 22)
        if origin.x + loupe > bounds.width - 8 { origin.x = point.x - loupe - 22 }
        if origin.y + loupe + 42 > bounds.height - 8 { origin.y = point.y - loupe - 42 }
        origin.x = max(8, origin.x)
        origin.y = max(8, origin.y)

        let frame = CGRect(x: origin.x, y: origin.y, width: loupe, height: loupe)

        // Background + border.
        let bg = NSBezierPath(roundedRect: frame.insetBy(dx: -3, dy: -3), xRadius: 8, yRadius: 8)
        NSColor(calibratedWhite: 0.08, alpha: 0.92).setFill()
        bg.fill()
        NSColor.white.withAlphaComponent(0.35).setStroke()
        bg.lineWidth = 1
        bg.stroke()

        // Zoomed pixels.
        let px = point.x * shot.scale
        let py = point.y * shot.scale
        let half = pixels / 2
        let src = CGRect(x: (px - half).rounded(.down), y: (py - half).rounded(.down), width: pixels, height: pixels)
            .intersection(CGRect(x: 0, y: 0, width: shot.image.width, height: shot.image.height))
        if let cropped = shot.image.cropping(to: src) {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: frame).addClip()
            ctx.interpolationQuality = .none
            NSImage(cgImage: cropped, size: src.size).draw(in: frame)
            NSGraphicsContext.restoreGraphicsState()
        }

        // Centre marker: white outer box + blue inner box so it reads on any pixel.
        let step = loupe / pixels
        let centerPixel = CGRect(
            x: frame.minX + step * (pixels / 2).rounded(.down),
            y: frame.minY + step * (pixels / 2).rounded(.down),
            width: step,
            height: step
        )
        NSColor.white.withAlphaComponent(0.95).setStroke()
        let outerMarker = NSBezierPath(rect: centerPixel.insetBy(dx: -0.5, dy: -0.5))
        outerMarker.lineWidth = 2
        outerMarker.stroke()
        NSColor(calibratedRed: 0.23, green: 0.51, blue: 0.96, alpha: 1).setStroke()
        let innerMarker = NSBezierPath(rect: centerPixel)
        innerMarker.lineWidth = 1
        innerMarker.stroke()

        // Colour + coordinate readout under the loupe.
        let color = sampler.color(atPixelX: Int(px), y: Int(py)) ?? .black
        let hex = color.hexString
        let coord = "\(Int(px)), \(Int(py))"
        let chipFrame = CGRect(x: frame.minX, y: frame.maxY + 6, width: loupe, height: 46)
        let chip = NSBezierPath(roundedRect: chipFrame, xRadius: 7, yRadius: 7)
        NSColor(calibratedWhite: 0.08, alpha: 0.92).setFill()
        chip.fill()

        let swatch = CGRect(x: chipFrame.minX + 8, y: chipFrame.minY + 8, width: 14, height: 14)
        color.setFill()
        NSBezierPath(roundedRect: swatch, xRadius: 3, yRadius: 3).fill()
        NSColor.white.withAlphaComponent(0.3).setStroke()
        let swatchBorder = NSBezierPath(roundedRect: swatch, xRadius: 3, yRadius: 3)
        swatchBorder.lineWidth = 1
        swatchBorder.stroke()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        (hex as NSString).draw(at: CGPoint(x: swatch.maxX + 7, y: chipFrame.minY + 8), withAttributes: attrs)

        let coordAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9.5, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.62)
        ]
        (coord as NSString).draw(
            at: CGPoint(x: chipFrame.minX + 9, y: chipFrame.minY + 27),
            withAttributes: coordAttrs
        )
    }

    private func drawChip(_ text: String, at point: CGPoint, centered: Bool = false, alignRight: Bool = false, small: Bool = false) {
        let font = NSFont.systemFont(ofSize: small ? 11 : 12, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let size = (text as NSString).size(withAttributes: attrs)
        let padding = CGSize(width: 10, height: 6)
        var frame = CGRect(x: point.x, y: point.y, width: size.width + padding.width * 2, height: size.height + padding.height * 2)
        if centered { frame.origin.x = point.x - frame.width / 2 }
        if alignRight { frame.origin.x = point.x - frame.width }
        // Keep inside the screen.
        if frame.maxX > bounds.width - 6 { frame.origin.x = bounds.width - frame.width - 6 }
        frame.origin.x = max(6, frame.origin.x)
        frame.origin.y = max(6, min(frame.origin.y, bounds.height - frame.height - 6))

        let bg = NSBezierPath(roundedRect: frame, xRadius: 7, yRadius: 7)
        NSColor(calibratedWhite: 0.1, alpha: 0.86).setFill()
        bg.fill()
        NSColor.white.withAlphaComponent(0.15).setStroke()
        bg.lineWidth = 1
        bg.stroke()
        (text as NSString).draw(
            at: CGPoint(x: frame.minX + padding.width, y: frame.minY + padding.height),
            withAttributes: attrs
        )
    }
}
