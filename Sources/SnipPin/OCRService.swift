import AppKit
import Vision

struct OCRResult {
    var text: String = ""
    var lines: [String] = []
}

enum OCRService {
    /// Recognise text in an image, preserving rough reading order.
    static func recognize(in image: CGImage, languages: [String] = ["zh-Hans", "zh-Hant", "en-US"]) async -> OCRResult {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    NSLog("SnipPin OCR error: \(error.localizedDescription)")
                    continuation.resume(returning: OCRResult())
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let sorted = observations.sorted { a, b in
                    let ay = a.boundingBox.midY, by = b.boundingBox.midY
                    if abs(ay - by) > 0.01 { return ay > by }
                    return a.boundingBox.minX < b.boundingBox.minX
                }
                var lines: [String] = []
                for observation in sorted {
                    guard let candidate = observation.topCandidates(1).first else { continue }
                    lines.append(candidate.string)
                }
                continuation.resume(returning: OCRResult(text: lines.joined(separator: "\n"), lines: lines))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = languages

            let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
            do {
                try handler.perform([request])
            } catch {
                NSLog("SnipPin OCR perform error: \(error.localizedDescription)")
                continuation.resume(returning: OCRResult())
            }
        }
    }
}
