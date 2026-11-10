import AppKit

/// Headless check of PNG/JPEG encoding and "fit under N KB" search.
@MainActor
enum ExportSelfTest {
    static func run() async -> Int32 {
        guard let image = SnapshotDemo.makeDesktopImage(size: CGSize(width: 1280, height: 720), scale: 2) else {
            print("RESULT: FAIL (no test image)")
            return 1
        }
        var ok = true

        func report(_ label: String, _ result: ExportResult?, targetKB: Int? = nil) {
            guard let result else {
                print("\(label): FAILED")
                ok = false
                return
            }
            let fits = targetKB.map { result.bytes <= $0 * 1024 } ?? true
            if !fits { ok = false }
            print(String(
                format: "%@: %@  %d×%d  q=%.2f s=%.2f%@",
                label, result.kbText, result.pixelWidth, result.pixelHeight,
                result.quality, result.scale, fits ? "" : "  OVER TARGET"
            ))
        }

        report("PNG full", ImageExporter.encode(image, options: ExportOptions(format: .png, quality: 1, scale: 1, maxKB: nil)))
        report("JPEG q80", ImageExporter.encode(image, options: ExportOptions(format: .jpeg, quality: 0.8, scale: 1, maxKB: nil)))

        for target in [600, 200, 80] {
            let pngOptions = ExportOptions(format: .png, quality: 1, scale: 1, maxKB: target)
            report("PNG <=\(target)KB", ImageExporter.fit(image, options: pngOptions, maxKB: target), targetKB: target)

            let jpegOptions = ExportOptions(format: .jpeg, quality: 0.8, scale: 1, maxKB: target)
            report("JPEG <=\(target)KB", ImageExporter.fit(image, options: jpegOptions, maxKB: target), targetKB: target)
        }

        if let jpeg = ImageExporter.fit(
            image,
            options: ExportOptions(format: .jpeg, quality: 0.8, scale: 1, maxKB: 200),
            maxKB: 200
        ) {
            try? jpeg.data.write(to: URL(fileURLWithPath: "/tmp/snippin-export-200k.jpg"))
        }

        print(ok ? "RESULT: PASS" : "RESULT: FAIL")
        return ok ? 0 : 2
    }
}
