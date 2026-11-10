import AppKit

enum Tool: String, CaseIterable {
    case move, rect, ellipse, arrow, pen, highlight, mosaic, text

    var symbol: String {
        switch self {
        case .move: return "hand.draw"
        case .rect: return "rectangle"
        case .ellipse: return "circle"
        case .arrow: return "arrow.up.right"
        case .pen: return "pencil.tip"
        case .highlight: return "highlighter"
        case .mosaic: return "checkerboard.rectangle"
        case .text: return "t.square"
        }
    }

    var title: String {
        switch self {
        case .move: return "移动"
        case .rect: return "矩形"
        case .ellipse: return "椭圆"
        case .arrow: return "箭头"
        case .pen: return "画笔"
        case .highlight: return "高亮"
        case .mosaic: return "马赛克"
        case .text: return "文字"
        }
    }

    var shortcut: String {
        switch self {
        case .move: return "V"
        case .rect: return "R"
        case .ellipse: return "O"
        case .arrow: return "A"
        case .pen: return "P"
        case .highlight: return "H"
        case .mosaic: return "M"
        case .text: return "T"
        }
    }
}

struct Annotation {
    var tool: Tool
    var points: [CGPoint]
    var color: NSColor
    var lineWidth: CGFloat
    var text: String = ""
    var fontSize: CGFloat = 18

    var boundingRect: CGRect {
        guard let first = points.first else { return .zero }
        var rect = CGRect(origin: first, size: .zero)
        for point in points.dropFirst() {
            rect = rect.union(CGRect(origin: point, size: .zero))
        }
        return rect.insetBy(dx: -lineWidth * 2, dy: -lineWidth * 2)
    }
}

@MainActor
protocol CanvasDelegate: AnyObject {
    func canvasDidRequestText(at point: CGPoint)
    func canvasDidDoubleClick()
    func canvasDidFinishMoving()
    var canvasIsEditingText: Bool { get }
}

@MainActor
final class CanvasView: NSView {
    let cgImage: CGImage
    let pointSize: CGSize
    private let nsImage: NSImage
    private lazy var pixelatedImage: NSImage? = makePixelated()

    weak var delegate: CanvasDelegate?
    var tool: Tool = .rect {
        didSet {
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }
    var color: NSColor = NSColor(calibratedRed: 0.94, green: 0.27, blue: 0.27, alpha: 1)
    var lineWidth: CGFloat = 3

    var onChange: (() -> Void)?
    private(set) var annotations: [Annotation] = []
    private var current: Annotation?
    private var dragStart: CGPoint = .zero
    private(set) var isDrawing = false

    private var isDraggingWindow = false
    private var windowDragStartMouse: CGPoint = .zero
    private var windowDragStartOrigin: CGPoint = .zero
    private var spaceHeld = false

    init(cgImage: CGImage, pointSize: CGSize) {
        self.cgImage = cgImage
        self.pointSize = pointSize
        self.nsImage = NSImage(cgImage: cgImage, size: pointSize)
        super.init(frame: CGRect(origin: .zero, size: pointSize))
        wantsLayer = true
        layer?.borderWidth = 1.5
        layer?.borderColor = NSColor.white.withAlphaComponent(0.45).cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: (tool == .move || spaceHeld) ? .openHand : .crosshair)
    }

    func setSpaceHeld(_ held: Bool) {
        guard spaceHeld != held else { return }
        spaceHeld = held
        window?.invalidateCursorRects(for: self)
        ((tool == .move || held) ? NSCursor.openHand : NSCursor.crosshair).set()
    }

    func undo() {
        guard !annotations.isEmpty else { return }
        annotations.removeLast()
        needsDisplay = true
        onChange?()
    }

    /// Used by the offscreen preview renderer only.
    func addForPreview(_ items: [Annotation]) {
        annotations.append(contentsOf: items)
        needsDisplay = true
    }

    func addText(_ text: String, at point: CGPoint) {
        guard !text.isEmpty else { return }
        annotations.append(Annotation(tool: .text, points: [point], color: color, lineWidth: lineWidth, text: text, fontSize: 18))
        needsDisplay = true
        onChange?()
    }

    /// Flattened capture at native backing resolution (used for copy/save/pin/OCR).
    func exportImage() -> CGImage? {
        guard bounds.width >= 1, bounds.height >= 1 else { return nil }
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        cacheDisplay(in: bounds, to: rep)
        return rep.cgImage
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        if delegate?.canvasIsEditingText == true {
            window?.makeFirstResponder(nil)
            return
        }
        if (tool == .move || spaceHeld), let window {
            windowDragStartMouse = NSEvent.mouseLocation
            windowDragStartOrigin = window.frame.origin
            isDraggingWindow = true
            NSCursor.closedHand.set()
            return
        }
        if event.clickCount == 2 {
            delegate?.canvasDidDoubleClick()
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        dragStart = point
        isDrawing = true

        if tool == .text {
            isDrawing = false
            delegate?.canvasDidRequestText(at: point)
            return
        }

        current = Annotation(tool: tool, points: [point], color: color, lineWidth: lineWidth)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        if isDraggingWindow, let window {
            let current = NSEvent.mouseLocation
            let proposed = CGPoint(
                x: windowDragStartOrigin.x + (current.x - windowDragStartMouse.x),
                y: windowDragStartOrigin.y + (current.y - windowDragStartMouse.y)
            )
            window.setFrameOrigin(clampedWindowOrigin(proposed, size: window.frame.size))
            return
        }
        guard isDrawing, var annotation = current else { return }
        let point = convert(event.locationInWindow, from: nil)
        switch tool {
        case .move:
            return
        case .rect, .ellipse, .arrow:
            annotation.points = [dragStart, point]
        case .pen, .highlight, .mosaic:
            if let last = annotation.points.last, hypot(point.x - last.x, point.y - last.y) < 1.2 {
                return
            }
            annotation.points.append(point)
        case .text:
            break
        }
        current = annotation
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if isDraggingWindow {
            isDraggingWindow = false
            ((tool == .move || spaceHeld) ? NSCursor.openHand : NSCursor.crosshair).set()
            delegate?.canvasDidFinishMoving()
            return
        }
        guard isDrawing, let annotation = current else {
            isDrawing = false
            return
        }
        isDrawing = false
        current = nil
        if isValid(annotation) {
            annotations.append(annotation)
            onChange?()
        }
        needsDisplay = true
    }

    private func isValid(_ annotation: Annotation) -> Bool {
        switch annotation.tool {
        case .move:
            return false
        case .rect, .ellipse, .arrow:
            guard annotation.points.count >= 2 else { return false }
            let a = annotation.points[0], b = annotation.points[1]
            return abs(a.x - b.x) > 2 || abs(a.y - b.y) > 2
        case .pen, .highlight, .mosaic:
            return annotation.points.count >= 2
        case .text:
            return !annotation.text.isEmpty
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        nsImage.draw(in: bounds)
        for annotation in annotations {
            draw(annotation, in: ctx)
        }
        if let current {
            draw(current, in: ctx)
        }
    }

    private func draw(_ annotation: Annotation, in ctx: CGContext) {
        switch annotation.tool {
        case .move:
            break
        case .rect, .ellipse:
            guard annotation.points.count >= 2 else { return }
            let rect = shapeRect(annotation.points[0], annotation.points[1])
            let path = annotation.tool == .rect ? NSBezierPath(rect: rect) : NSBezierPath(ovalIn: rect)
            path.lineWidth = annotation.lineWidth
            annotation.color.setStroke()
            path.stroke()

        case .arrow:
            guard annotation.points.count >= 2 else { return }
            drawArrow(from: annotation.points[0], to: annotation.points[1], color: annotation.color, width: annotation.lineWidth)

        case .pen, .highlight:
            guard annotation.points.count >= 2 else { return }
            let path = smoothPath(annotation.points)
            path.lineWidth = annotation.tool == .highlight ? annotation.lineWidth * 5 : annotation.lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            let drawColor = annotation.tool == .highlight
                ? annotation.color.withAlphaComponent(0.32)
                : annotation.color
            drawColor.setStroke()
            path.stroke()

        case .mosaic:
            guard annotation.points.count >= 2, let pixelated = pixelatedImage else { return }
            ctx.saveGState()
            ctx.addPath(smoothedCGPath(annotation.points))
            ctx.setLineWidth(28)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.replacePathWithStrokedPath()
            ctx.clip()
            pixelated.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
            ctx.restoreGState()

        case .text:
            guard !annotation.text.isEmpty, let origin = annotation.points.first else { return }
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
            shadow.shadowBlurRadius = 3
            shadow.shadowOffset = NSSize(width: 0, height: 1)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: annotation.fontSize, weight: .semibold),
                .foregroundColor: annotation.color,
                .shadow: shadow
            ]
            (annotation.text as NSString).draw(at: origin, withAttributes: attrs)
        }
    }

    private func smoothedCGPath(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 2 else {
            if points.count == 2 { path.addLine(to: points[1]) }
            return path
        }
        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let mid = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
            path.addQuadCurve(to: mid, control: previous)
            if index == points.count - 1 { path.addLine(to: current) }
        }
        return path
    }

    /// Keeps the window centre inside the union of all screens so it cannot be lost.
    private func clampedWindowOrigin(_ origin: CGPoint, size: CGSize) -> CGPoint {
        let screens = NSScreen.screens
        guard let first = screens.first else { return origin }
        var union = first.frame
        for screen in screens.dropFirst() { union = union.union(screen.frame) }
        let margin: CGFloat = 40
        let center = CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
        let clamped = CGPoint(
            x: min(max(center.x, union.minX + margin), union.maxX - margin),
            y: min(max(center.y, union.minY + margin), union.maxY - margin)
        )
        return CGPoint(x: clamped.x - size.width / 2, y: clamped.y - size.height / 2)
    }

    private func shapeRect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    private func smoothPath(_ points: [CGPoint]) -> NSBezierPath {
        let path = NSBezierPath()
        guard let first = points.first else { return path }
        path.move(to: first)
        if points.count == 2 {
            path.line(to: points[1])
            return path
        }
        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let mid = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
            path.curve(to: mid, controlPoint1: previous, controlPoint2: mid)
            if index == points.count - 1 {
                path.line(to: current)
            }
        }
        return path
    }

    private func drawArrow(from start: CGPoint, to end: CGPoint, color: NSColor, width: CGFloat) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength = max(11, width * 4.2)
        let headAngle: CGFloat = 0.42
        let left = CGPoint(
            x: end.x - headLength * cos(angle - headAngle),
            y: end.y - headLength * sin(angle - headAngle)
        )
        let right = CGPoint(
            x: end.x - headLength * cos(angle + headAngle),
            y: end.y - headLength * sin(angle + headAngle)
        )

        let shaft = NSBezierPath()
        shaft.move(to: start)
        shaft.line(to: CGPoint(x: end.x - cos(angle) * headLength * 0.55, y: end.y - sin(angle) * headLength * 0.55))
        shaft.lineWidth = width
        shaft.lineCapStyle = .round
        color.setStroke()
        shaft.stroke()

        let head = NSBezierPath()
        head.move(to: end)
        head.line(to: left)
        head.line(to: right)
        head.close()
        color.setFill()
        head.fill()
    }

    private func makePixelated() -> NSImage? {
        // Pixellate in image pixels (~12 px blocks) so text stays visible but unreadable.
        let blockPixels = 12
        let smallWidth = max(1, cgImage.width / blockPixels)
        let smallHeight = max(1, cgImage.height / blockPixels)
        guard
            let small = CGContext(
                data: nil,
                width: smallWidth,
                height: smallHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ),
            let full = CGContext(
                data: nil,
                width: max(1, Int(pointSize.width)),
                height: max(1, Int(pointSize.height)),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }

        small.interpolationQuality = .medium
        small.draw(cgImage, in: CGRect(x: 0, y: 0, width: smallWidth, height: smallHeight))
        guard let reduced = small.makeImage() else { return nil }

        full.interpolationQuality = .none
        full.draw(reduced, in: CGRect(origin: .zero, size: pointSize))
        guard let enlarged = full.makeImage() else { return nil }
        return NSImage(cgImage: enlarged, size: pointSize)
    }
}