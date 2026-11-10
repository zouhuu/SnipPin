import AppKit

enum ImageOutput {
    static func pngData(_ image: CGImage) -> Data? {
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .png, properties: [:])
    }

    static func tiffData(_ image: CGImage) -> Data? {
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .tiff, properties: [:])
    }

    static func copyToPasteboard(_ image: CGImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let data = pngData(image) {
            pasteboard.setData(data, forType: .png)
        }
        if let tiff = tiffData(image) {
            pasteboard.setData(tiff, forType: .tiff)
        }
    }

    @discardableResult
    static func writePNG(_ image: CGImage, to url: URL) -> Bool {
        guard let data = pngData(image) else { return false }
        do {
            try data.write(to: url)
            return true
        } catch {
            NSLog("SnipPin: write failed \(error.localizedDescription)")
            return false
        }
    }

    static func defaultFilename(ext: String = "png") -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "SnipPin \(formatter.string(from: Date())).\(ext)"
    }

    static func defaultDirectory() -> URL {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        return desktop ?? FileManager.default.homeDirectoryForCurrentUser
    }

    /// Temporary PNG on disk, used for drag-and-drop sharing of pins.
    static func temporaryPNGFile(_ image: CGImage) -> URL? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SnipPin", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("SnipPin-\(UUID().uuidString).png")
        guard let data = pngData(image) else { return nil }
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}

/// Transient HUD confirmation ("已复制到剪贴板").
@MainActor
enum Toast {
    private static var current: NSPanel?

    static func show(_ text: String, near rect: CGRect? = nil) {
        current?.orderOut(nil)
        current = nil

        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let padding = CGSize(width: 16, height: 10)
        let size = CGSize(width: textSize.width + padding.width * 2, height: textSize.height + padding.height * 2)

        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar + 2
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let view = NSView(frame: CGRect(origin: .zero, size: size))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 0.92).cgColor
        view.layer?.cornerRadius = 9
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = .white
        label.frame = CGRect(x: padding.width, y: padding.height, width: textSize.width, height: textSize.height)
        view.addSubview(label)
        panel.contentView = view

        let screen = NSScreen.screens.first(where: { $0.frame.intersects(rect ?? .zero) }) ?? NSScreen.main
        if let screen {
            let frame = screen.visibleFrame
            var origin = CGPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height - 90)
            if let rect {
                origin = CGPoint(x: rect.midX - size.width / 2, y: rect.maxY - size.height - 12)
                origin.y = max(frame.minY + 12, min(origin.y, frame.maxY - size.height - 12))
                origin.x = max(frame.minX + 12, min(origin.x, frame.maxX - size.width - 12))
            }
            panel.setFrameOrigin(origin)
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        current = panel

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        } completionHandler: {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                guard current === panel else { return }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.25
                    panel.animator().alphaValue = 0
                } completionHandler: {
                    panel.orderOut(nil)
                    if current === panel { current = nil }
                }
            }
        }
    }
}
