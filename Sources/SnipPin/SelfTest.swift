import AppKit
import Vision

/// Headless pipeline check: `SnipPin.app/Contents/MacOS/SnipPin --selftest`
/// Captures the main display, writes a PNG and (if possible) runs OCR on it.
enum SelfTest {
    static func run() async -> Int32 {
        print("SnipPin selftest")
        print("screen-capture permission: \(CaptureService.hasScreenCapturePermission ? "granted" : "missing")")

        guard CaptureService.hasScreenCapturePermission else {
            print("RESULT: FAIL (no screen recording permission — run the app once and allow it in System Settings)")
            return 2
        }

        do {
            let shot = try await CaptureService.shared.captureMainScreen()
            print("captured display \(shot.displayID): \(shot.image.width)x\(shot.image.height) px, scale \(shot.scale)x")

            guard let data = NSBitmapImageRep(cgImage: shot.image).representation(using: .png, properties: [:]) else {
                print("RESULT: FAIL (png encode)")
                return 3
            }
            let path = "/tmp/snippin-selftest.png"
            try data.write(to: URL(fileURLWithPath: path))
            print("wrote \(path) (\(data.count / 1024) KB)")

            let ocr = await OCRService.recognize(in: shot.image)
            print("ocr: \(ocr.text.isEmpty ? "(no text found)" : "\(ocr.text.count) chars, \(ocr.lines.count) lines")")
            if let first = ocr.lines.first { print("ocr first line: \(first)") }

            print("RESULT: PASS")
            return 0
        } catch {
            print("RESULT: FAIL (\(error.localizedDescription))")
            return 4
        }
    }
}
