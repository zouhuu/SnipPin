import AppKit

/// Renders the UI offscreen into PNGs so the layout can be reviewed without
/// screen-recording permission: `SnipPin --render-demo [outputDir]`.
@MainActor
enum SnapshotDemo {
    static func run() async -> Int32 {
        let args = CommandLine.arguments
        let dir: URL
        if let index = args.firstIndex(of: "--render-demo"), index + 1 < args.count, !args[index + 1].hasPrefix("-") {
            dir = URL(fileURLWithPath: args[index + 1])
        } else {
            dir = URL(fileURLWithPath: "/tmp/snippin-demo")
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let desktopSize = CGSize(width: 640, height: 400)
        let scale: CGFloat = 2
        guard let desktop = makeDesktopImage(size: desktopSize, scale: scale) else {
            print("RESULT: FAIL (could not build demo image)")
            return 1
        }

        renderSelection(desktop: desktop, size: desktopSize, scale: scale, to: dir.appendingPathComponent("selection.png"))
        renderHover(desktop: desktop, size: desktopSize, scale: scale, to: dir.appendingPathComponent("selection-hover.png"))
        renderEditor(desktop: desktop, size: desktopSize, scale: scale, to: dir.appendingPathComponent("editor.png"))
        renderPin(desktop: desktop, size: desktopSize, scale: scale, to: dir.appendingPathComponent("pin.png"))
        renderMosaic(desktop: desktop, size: desktopSize, scale: scale, to: dir.appendingPathComponent("mosaic.png"))
        renderSizePanel(to: dir.appendingPathComponent("size-panel.png"))
        renderShortcuts(to: dir.appendingPathComponent("shortcuts.png"))

        print("RESULT: PASS")
        print("wrote \(dir.path)/selection.png")
        print("wrote \(dir.path)/selection-hover.png")
        print("wrote \(dir.path)/editor.png")
        print("wrote \(dir.path)/pin.png")
        print("wrote \(dir.path)/mosaic.png")
        print("wrote \(dir.path)/size-panel.png")
        print("wrote \(dir.path)/shortcuts.png")
        return 0
    }

    // MARK: - Previews

    private static func renderSelection(desktop: CGImage, size: CGSize, scale: CGFloat, to url: URL) {
        guard let screen = NSScreen.main else { return }
        let shot = ScreenShot(screen: screen, displayID: 0, image: desktop, explicitScale: scale)
        let view = SelectionView(shot: shot, controller: SelectionController.shared)
        view.frame = CGRect(origin: .zero, size: size)
        view.configureForPreview(
            cursor: CGPoint(x: 402, y: 214),
            selection: CGRect(x: 118, y: 92, width: 302, height: 196)
        )
        render(view, to: url)
    }

    private static func renderHover(desktop: CGImage, size: CGSize, scale: CGFloat, to url: URL) {
        guard let screen = NSScreen.main else { return }
        let shot = ScreenShot(screen: screen, displayID: 0, image: desktop, explicitScale: scale)
        let view = SelectionView(shot: shot, controller: SelectionController.shared)
        view.frame = CGRect(origin: .zero, size: size)
        view.configureForPreview(cursor: CGPoint(x: 218, y: 300), selection: .zero)
        render(view, to: url)
    }

    private static func renderEditor(desktop: CGImage, size: CGSize, scale: CGFloat, to url: URL) {
        let cropRect = CGRect(x: 118, y: 92, width: 302, height: 196)
        let pixelRect = CGRect(
            x: cropRect.minX * scale,
            y: cropRect.minY * scale,
            width: cropRect.width * scale,
            height: cropRect.height * scale
        )
        guard let crop = desktop.cropping(to: pixelRect) else { return }

        let canvas = CanvasView(cgImage: crop, pointSize: cropRect.size)
        let red = NSColor(calibratedRed: 0.94, green: 0.27, blue: 0.27, alpha: 1)
        let yellow = NSColor(calibratedRed: 0.98, green: 0.75, blue: 0.18, alpha: 1)
        let blue = NSColor(calibratedRed: 0.23, green: 0.51, blue: 0.96, alpha: 1)
        canvas.addForPreview([
            Annotation(tool: .rect, points: [CGPoint(x: 20, y: 24), CGPoint(x: 268, y: 120)], color: red, lineWidth: 3),
            Annotation(tool: .arrow, points: [CGPoint(x: 40, y: 170), CGPoint(x: 150, y: 130)], color: blue, lineWidth: 3),
            Annotation(tool: .highlight, points: [
                CGPoint(x: 180, y: 160), CGPoint(x: 220, y: 158), CGPoint(x: 262, y: 162)
            ], color: yellow, lineWidth: 3),
            Annotation(tool: .mosaic, points: [
                CGPoint(x: 150, y: 182), CGPoint(x: 200, y: 182), CGPoint(x: 252, y: 182)
            ], color: .white, lineWidth: 3),
            Annotation(tool: .text, points: [CGPoint(x: 22, y: 138)], color: red, lineWidth: 3, text: "SnipPin 标注演示", fontSize: 18)
        ])

        let editor = EditorController(image: crop, captureRect: CGRect(origin: .zero, size: cropRect.size), scale: scale)
        let toolbar = ToolbarView(editor: editor)
        toolbar.selectedTool = .arrow
        toolbar.setSize(text: "1.3 MB", warning: false)
        toolbar.frame = CGRect(origin: .zero, size: CGSize(width: ToolbarView.width, height: ToolbarView.height))

        let gap: CGFloat = 16
        let containerSize = CGSize(
            width: max(cropRect.width, ToolbarView.width) + gap * 2,
            height: cropRect.height + ToolbarView.height + gap * 3
        )
        let container = NSView(frame: CGRect(origin: .zero, size: containerSize))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(calibratedWhite: 0.22, alpha: 1).cgColor

        canvas.frame = CGRect(x: gap, y: gap, width: cropRect.width, height: cropRect.height)
        container.addSubview(canvas)
        toolbar.frame = CGRect(x: gap, y: cropRect.height + gap * 2, width: ToolbarView.width, height: ToolbarView.height)
        container.addSubview(toolbar)
        render(container, to: url)
    }

    private static func renderSizePanel(to url: URL) {
        var options = ExportOptions()
        options.format = .jpeg
        options.quality = 0.72
        options.scale = 1
        options.maxKB = 200
        let panel = ExportSizePanel(options: options, originalKB: 1286, width: 2560, height: 1440)
        _ = panel.view
        panel.sync(options)
        panel.updateOutput("输出 196 KB · 2560 × 1440", warning: false)
        render(panel.view, to: url)
    }

    private static func renderShortcuts(to url: URL) {
        let controller = ShortcutSettingsWindow(onApply: { [] }, onClose: {})
        guard let content = controller.contentViewForTesting else { return }
        content.frame = CGRect(origin: .zero, size: CGSize(width: 440, height: 596))
        let container = NSView(frame: content.bounds)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        container.addSubview(content)
        render(container, to: url)
    }

    private static func renderMosaic(desktop: CGImage, size: CGSize, scale: CGFloat, to url: URL) {
        let cropRect = CGRect(x: 118, y: 92, width: 302, height: 196)
        let pixelRect = CGRect(
            x: cropRect.minX * scale,
            y: cropRect.minY * scale,
            width: cropRect.width * scale,
            height: cropRect.height * scale
        )
        guard let crop = desktop.cropping(to: pixelRect) else { return }
        let canvas = CanvasView(cgImage: crop, pointSize: cropRect.size)
        canvas.addForPreview([
            Annotation(tool: .mosaic, points: [
                CGPoint(x: 60, y: 160), CGPoint(x: 120, y: 150), CGPoint(x: 200, y: 168), CGPoint(x: 250, y: 150)
            ], color: .white, lineWidth: 3)
        ])
        render(canvas, to: url)
    }

    private static func renderPin(desktop: CGImage, size: CGSize, scale: CGFloat, to url: URL) {
        let cropRect = CGRect(x: 118, y: 92, width: 302, height: 196)
        let pixelRect = CGRect(
            x: cropRect.minX * scale,
            y: cropRect.minY * scale,
            width: cropRect.width * scale,
            height: cropRect.height * scale
        )
        guard let crop = desktop.cropping(to: pixelRect) else { return }
        let view = PinImageView(image: crop, frame: CGRect(origin: .zero, size: cropRect.size))
        let container = NSView(frame: CGRect(x: 0, y: 0, width: cropRect.width + 40, height: cropRect.height + 40))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(calibratedWhite: 0.25, alpha: 1).cgColor
        view.frame = CGRect(x: 20, y: 20, width: cropRect.width, height: cropRect.height)
        container.addSubview(view)
        render(container, to: url)
    }

    // MARK: - Helpers

    private static func render(_ view: NSView, to url: URL) {
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            print("could not render \(url.lastPathComponent)")
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: url)
        }
    }

    static func makeDesktopImage(size: CGSize, scale: CGFloat) -> CGImage? {
        let width = Int(size.width * scale)
        let height = Int(size.height * scale)
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.scaleBy(x: scale, y: scale)

        let colors = [
            NSColor(calibratedRed: 0.13, green: 0.20, blue: 0.36, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.42, green: 0.22, blue: 0.46, alpha: 1).cgColor
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: size.height),
                end: CGPoint(x: size.width, y: 0),
                options: []
            )
        }

        // Fake window.
        let windowRect = CGRect(x: 44, y: 40, width: 520, height: 300)
        ctx.setFillColor(NSColor(calibratedWhite: 0.97, alpha: 1).cgColor)
        ctx.addPath(CGPath(roundedRect: windowRect, cornerWidth: 10, cornerHeight: 10, transform: nil))
        ctx.fillPath()

        ctx.setFillColor(NSColor(calibratedWhite: 0.90, alpha: 1).cgColor)
        ctx.addPath(CGPath(roundedRect: CGRect(x: 44, y: 310, width: 520, height: 30), cornerWidth: 10, cornerHeight: 10, transform: nil))
        ctx.fillPath()
        for index in 0..<3 {
            ctx.setFillColor(NSColor(calibratedRed: [0.96, 0.72, 0.25][index], green: [0.35, 0.75, 0.42][index], blue: [0.32, 0.28, 0.72][index], alpha: 1).cgColor)
            ctx.fillEllipse(in: CGRect(x: 58 + CGFloat(index) * 18, y: 320, width: 10, height: 10))
        }

        // Sidebar + content lines.
        ctx.setFillColor(NSColor(calibratedRed: 0.90, green: 0.92, blue: 0.96, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 44, y: 40, width: 120, height: 270))

        ctx.setFillColor(NSColor(calibratedWhite: 0.80, alpha: 1).cgColor)
        for index in 0..<7 {
            ctx.fill(CGRect(x: 64, y: 280 - CGFloat(index) * 22, width: 76, height: 8))
        }

        NSGraphicsContext.saveGraphicsState()
        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        do {
            NSGraphicsContext.current = ns
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 20, weight: .bold),
                .foregroundColor: NSColor(calibratedWhite: 0.15, alpha: 1)
            ]
            ("桌面预览 · SnipPin" as NSString).draw(at: CGPoint(x: 186, y: 254), withAttributes: titleAttrs)
            let bodyAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor(calibratedWhite: 0.45, alpha: 1)
            ]
            ("拖动框选 · 放大镜取色 · 标注 · 贴图" as NSString).draw(at: CGPoint(x: 186, y: 228), withAttributes: bodyAttrs)
            NSGraphicsContext.restoreGraphicsState()
        }

        // Some colourful blocks to make mosaic visible.
        let blocks: [NSColor] = [
            NSColor(calibratedRed: 0.23, green: 0.51, blue: 0.96, alpha: 1),
            NSColor(calibratedRed: 0.98, green: 0.75, blue: 0.18, alpha: 1),
            NSColor(calibratedRed: 0.22, green: 0.78, blue: 0.45, alpha: 1),
            NSColor(calibratedRed: 0.94, green: 0.27, blue: 0.27, alpha: 1)
        ]
        for (index, color) in blocks.enumerated() {
            ctx.setFillColor(color.cgColor)
            ctx.fill(CGRect(x: 186 + CGFloat(index) * 74, y: 74 + CGFloat(index % 2) * 18, width: 60, height: 46))
        }

        return ctx.makeImage()
    }
}

/// End-to-end check on the real desktop: shows the overlay/editor/pin windows
/// and captures the composited result with ScreenCaptureKit.
/// Usage: `SnipPin --live-test [outputDir]`
@MainActor
enum LiveTest {
    static func run() async -> Int32 {
        DebugLog.write("LiveTest start, permission=\(CaptureService.hasScreenCapturePermission)")
        guard CaptureService.hasScreenCapturePermission else {
            DebugLog.write("LiveTest aborted: no permission")
            print("RESULT: FAIL (screen recording permission missing)")
            return 2
        }
        let args = CommandLine.arguments
        let dir: URL
        if let index = args.firstIndex(of: "--live-test"), index + 1 < args.count, !args[index + 1].hasPrefix("-") {
            dir = URL(fileURLWithPath: args[index + 1])
        } else {
            dir = URL(fileURLWithPath: "/tmp/snippin-live")
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        do {
            let shot = try await CaptureService.shared.captureMainScreen()
            DebugLog.write("captured \(shot.image.width)x\(shot.image.height)")
            let screenFrame = shot.screen.frame

            // 1) Selection overlay over the real desktop.
            NSApp.activate(ignoringOtherApps: true)
            SelectionController.shared.begin(shots: [shot]) { _ in }
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            await snap(to: dir.appendingPathComponent("live-selection.png"))
            SelectionController.shared.cancel()
            try? await Task.sleep(nanoseconds: 400_000_000)

            // 2) Editor window + toolbar.
            let localRect = CGRect(x: 280, y: 220, width: 520, height: 320)
            let pixelRect = shot.pixelRect(forPointRect: localRect)
            guard let crop = shot.image.cropping(to: pixelRect) else { return 4 }
            let captureRect = CGRect(
                x: screenFrame.minX + localRect.minX,
                y: screenFrame.maxY - localRect.maxY,
                width: localRect.width,
                height: localRect.height
            )
            let editor = EditorController(image: crop, captureRect: captureRect, scale: shot.scale)
            editor.present()
            editor.loadDemoAnnotations()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await snap(to: dir.appendingPathComponent("live-editor.png"))

            editor.moveEditorForTesting(by: CGSize(width: 360, height: -180))
            try? await Task.sleep(nanoseconds: 700_000_000)
            await snap(to: dir.appendingPathComponent("live-moved.png"))

            editor.showSizePanelForTesting()
            try? await Task.sleep(nanoseconds: 900_000_000)
            await snap(to: dir.appendingPathComponent("live-size-panel.png"))

            // 3) Pin window.
            PinController.shared.pin(image: crop, at: CGPoint(x: screenFrame.midX - 160, y: screenFrame.midY), scale: shot.scale)
            editor.close()
            try? await Task.sleep(nanoseconds: 800_000_000)
            await snap(to: dir.appendingPathComponent("live-pin.png"))

            // 4) Pasteboard + PNG encode smoke test.
            ImageOutput.copyToPasteboard(crop)
            let pasteboardHasPNG = NSPasteboard.general.data(forType: .png) != nil
            let pngSize = ImageOutput.pngData(crop)?.count ?? 0
            DebugLog.write("pasteboard png=\(pasteboardHasPNG) bytes=\(pngSize)")
            print("pasteboard png: \(pasteboardHasPNG), encoded bytes: \(pngSize)")

            let ocr = await OCRService.recognize(in: crop)
            DebugLog.write("ocr chars=\(ocr.text.count) first=\(ocr.lines.first ?? "-")")
            print("ocr chars: \(ocr.text.count)")

            (NSApp.delegate as? AppDelegate)?.openShortcutSettingsForTesting()
            try? await Task.sleep(nanoseconds: 900_000_000)
            await snap(to: dir.appendingPathComponent("live-shortcuts.png"))
            (NSApp.delegate as? AppDelegate)?.closeShortcutSettingsForTesting()

            PinController.shared.closeAll()
            DebugLog.write("LiveTest PASS")
            print("RESULT: PASS")
            print("wrote \(dir.path)/live-selection.png")
            print("wrote \(dir.path)/live-editor.png")
            print("wrote \(dir.path)/live-pin.png")
            return 0
        } catch {
            DebugLog.write("LiveTest FAIL \(error.localizedDescription)")
            print("RESULT: FAIL (\(error.localizedDescription))")
            return 5
        }
    }

    private static func snap(to url: URL) async {
        do {
            let shot = try await CaptureService.shared.captureMainScreen()
            DebugLog.write("captured \(shot.image.width)x\(shot.image.height)")
            if let data = ImageOutput.pngData(shot.image) {
                try? data.write(to: url)
                print("snap \(url.lastPathComponent): \(shot.image.width)x\(shot.image.height)")
            }
        } catch {
            print("snap failed: \(error.localizedDescription)")
        }
    }
}
