import AppKit
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable {
    case png, jpeg

    var displayName: String { self == .png ? "PNG" : "JPEG" }
    var utType: UTType { self == .png ? .png : .jpeg }
    var fileExtension: String { self == .png ? "png" : "jpg" }
    var pasteboardType: NSPasteboard.PasteboardType {
        self == .png ? .png : NSPasteboard.PasteboardType(UTType.jpeg.identifier)
    }
}

struct ExportOptions: Equatable {
    var format: ExportFormat = .png
    /// JPEG quality, 0.05...1.
    var quality: Double = 0.8
    /// Output scale, 0.2...1.
    var scale: Double = 1.0
    /// Optional size ceiling in KB (nil = keep full size).
    var maxKB: Int?

    static func load() -> ExportOptions {
        let defaults = UserDefaults.standard
        var options = ExportOptions()
        // Only the preferred format is sticky: an auto-fit from a previous capture
        // must never shrink the next screenshot (quality/scale always start fresh).
        if let raw = defaults.string(forKey: "SnipPin.exportFormat"), let format = ExportFormat(rawValue: raw) {
            options.format = format
        }
        defaults.removeObject(forKey: "SnipPin.exportQuality")
        defaults.removeObject(forKey: "SnipPin.exportScale")
        return options
    }

    func save() {
        UserDefaults.standard.set(format.rawValue, forKey: "SnipPin.exportFormat")
    }
}

struct ExportResult {
    let data: Data
    let format: ExportFormat
    let quality: Double
    let scale: Double
    let pixelWidth: Int
    let pixelHeight: Int

    var bytes: Int { data.count }
    var kbText: String { ImageExporter.kbText(bytes) }
}

enum ImageExporter {
    static func kbText(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024
        if kb >= 1024 {
            return String(format: "%.1f MB", kb / 1024)
        }
        return "\(max(1, Int(kb.rounded()))) KB"
    }

    static func encode(_ image: CGImage, options: ExportOptions) -> ExportResult? {
        encode(image, format: options.format, quality: options.quality, scale: options.scale)
    }

    static func encode(_ image: CGImage, format: ExportFormat, quality: Double, scale: Double) -> ExportResult? {
        let clampedScale = min(1, max(0.2, scale))
        let target = clampedScale < 0.999 ? resized(image, scale: clampedScale) : image
        let rep = NSBitmapImageRep(cgImage: target)

        switch format {
        case .png:
            guard let data = rep.representation(using: .png, properties: [:]) else { return nil }
            return ExportResult(
                data: data, format: .png, quality: 1, scale: clampedScale,
                pixelWidth: target.width, pixelHeight: target.height
            )
        case .jpeg:
            let clampedQuality = min(1, max(0.05, quality))
            guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: clampedQuality]) else {
                return nil
            }
            return ExportResult(
                data: data, format: .jpeg, quality: clampedQuality, scale: clampedScale,
                pixelWidth: target.width, pixelHeight: target.height
            )
        }
    }

    static func resized(_ image: CGImage, scale: Double) -> CGImage {
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        guard
            let ctx = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage() ?? image
    }

    /// Encode with `options`; if a `maxKB` ceiling is configured and the result is
    /// too large, search for the best quality/scale that fits.
    static func resolve(_ image: CGImage, options: ExportOptions) -> ExportResult? {
        guard let maxKB = options.maxKB, maxKB > 0 else {
            return encode(image, options: options)
        }
        if let current = encode(image, options: options), current.bytes <= maxKB * 1024 {
            return current
        }
        return fit(image, options: options, maxKB: maxKB)
    }

    /// Search quality (JPEG) or scale (PNG) to land under the KB ceiling.
    static func fit(_ image: CGImage, options: ExportOptions, maxKB: Int) -> ExportResult? {
        let limit = maxKB * 1024
        if let current = encode(image, options: options), current.bytes <= limit {
            return current
        }

        switch options.format {
        case .jpeg:
            var low = 0.05
            var high = 1.0
            var best: ExportResult?
            for _ in 0..<7 {
                let mid = (low + high) / 2
                guard let result = encode(image, format: .jpeg, quality: mid, scale: options.scale) else { break }
                if result.bytes <= limit {
                    best = result
                    low = mid
                } else {
                    high = mid
                }
            }
            if let best { return best }
            return fitByScale(image, format: .jpeg, quality: 0.5, scaleLimit: options.scale, limit: limit)

        case .png:
            return fitByScale(image, format: .png, quality: 1, scaleLimit: options.scale, limit: limit)
        }
    }

    private static func fitByScale(
        _ image: CGImage,
        format: ExportFormat,
        quality: Double,
        scaleLimit: Double,
        limit: Int
    ) -> ExportResult? {
        var low = 0.2
        var high = min(1, scaleLimit)
        var best: ExportResult?
        for _ in 0..<6 {
            let mid = (low + high) / 2
            guard let result = encode(image, format: format, quality: quality, scale: mid) else { break }
            if result.bytes <= limit {
                best = result
                low = mid
            } else {
                high = mid
            }
        }
        if let best { return best }
        return encode(image, format: format, quality: quality, scale: 0.2)
    }
}
