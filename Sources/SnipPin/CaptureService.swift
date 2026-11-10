import AppKit
import ScreenCaptureKit

/// One frozen screenshot of a single display, taken at native pixel resolution.
struct ScreenShot {
    let screen: NSScreen
    let displayID: CGDirectDisplayID
    let image: CGImage
    /// Overrides the derived backing scale (used by the offscreen preview renderer).
    var explicitScale: CGFloat? = nil

    /// Pixels per point for this display.
    var scale: CGFloat {
        if let explicitScale { return explicitScale }
        guard screen.frame.width > 0 else { return 2 }
        return CGFloat(image.width) / screen.frame.width
    }

    func pixelRect(forPointRect rect: CGRect) -> CGRect {
        let s = scale
        return CGRect(x: rect.minX * s, y: rect.minY * s, width: rect.width * s, height: rect.height * s)
            .integral
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
}

enum CaptureError: LocalizedError {
    case permissionMissing
    case noDisplays
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .permissionMissing:
            return "SnipPin 没有「屏幕录制」权限"
        case .noDisplays:
            return "找不到可截图的显示器"
        case .failed(let message):
            return message
        }
    }
}

@MainActor
final class CaptureService {
    static let shared = CaptureService()

    /// True if the process already holds the screen-recording TCC grant.
    nonisolated static var hasScreenCapturePermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Ask macOS to show the screen-recording permission prompt (only prompts once per signature).
    @discardableResult
    nonisolated static func requestScreenCapturePermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// Capture every attached display at native resolution.
    func captureAllScreens() async throws -> [ScreenShot] {
        guard Self.hasScreenCapturePermission else { throw CaptureError.permissionMissing }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            let ns = error as NSError
            if ns.domain == SCStreamErrorDomain || ns.code == -3801 {
                throw CaptureError.permissionMissing
            }
            throw CaptureError.failed("读取屏幕内容失败：\(error.localizedDescription)")
        }

        var shots: [ScreenShot] = []
        for screen in NSScreen.screens {
            guard
                let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { continue }
            let displayID = CGDirectDisplayID(number.uint32Value)
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else { continue }

            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            let config = SCStreamConfiguration()
            // SCDisplay reports the logical size on scaled (Retina) displays; capture at the
            // native backing resolution so 1pt selections stay 2x sharp when saved.
            let backing = screen.backingScaleFactor
            let nativeWidth = Int((screen.frame.width * backing).rounded())
            let nativeHeight = Int((screen.frame.height * backing).rounded())
            config.width = max(Int(display.width), nativeWidth)
            config.height = max(Int(display.height), nativeHeight)
            config.showsCursor = false
            config.captureResolution = .best
            config.scalesToFit = false
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.ignoreShadowsDisplay = true

            do {
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                shots.append(ScreenShot(screen: screen, displayID: displayID, image: image))
            } catch {
                NSLog("SnipPin: capture failed for display \(displayID): \(error)")
            }
        }

        guard !shots.isEmpty else { throw CaptureError.noDisplays }
        return shots
    }

    /// Capture a single display (used by the demo/selftest paths).
    func captureMainScreen() async throws -> ScreenShot {
        let shots = try await captureAllScreens()
        let mouse = NSEvent.mouseLocation
        if let hit = shots.first(where: { $0.screen.frame.contains(mouse) }) { return hit }
        guard let first = shots.first else { throw CaptureError.noDisplays }
        return first
    }
}

/// Fast RGBA pixel access for the colour loupe.
final class PixelSampler {
    let width: Int
    let height: Int
    private let buffer: [UInt8]

    init?(image: CGImage) {
        let w = image.width
        let h = image.height
        guard w > 0, h > 0 else { return nil }
        width = w
        height = h
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ok = data.withUnsafeMutableBytes { raw -> Bool in
            guard
                let ctx = CGContext(
                    data: raw.baseAddress,
                    width: w,
                    height: h,
                    bitsPerComponent: 8,
                    bytesPerRow: w * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        buffer = data
    }

    func color(atPixelX px: Int, y py: Int) -> NSColor? {
        guard px >= 0, py >= 0, px < width, py < height else { return nil }
        let i = (py * width + px) * 4
        let r = CGFloat(buffer[i]) / 255
        let g = CGFloat(buffer[i + 1]) / 255
        let b = CGFloat(buffer[i + 2]) / 255
        let a = CGFloat(buffer[i + 3]) / 255
        if a > 0.01 {
            return NSColor(srgbRed: r / a, green: g / a, blue: b / a, alpha: 1)
        }
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}

extension NSColor {
    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
