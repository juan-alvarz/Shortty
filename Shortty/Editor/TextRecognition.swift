import CoreGraphics
import Vision

/// On-device text recognition (Vision). Nonisolated so OCR can run off the main thread.
nonisolated enum TextRecognition {
    /// Boxes around each line of text inside `rect` (image px, top-left origin), padded a little. Fast mode.
    static func lineBoxes(in image: CGImage, rect: CGRect) -> [CGRect] {
        let area = rect.standardized.integral.intersection(image.bounds)
        guard !area.isNull, area.width >= 4, area.height >= 4, let crop = image.cropping(to: area) else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: crop).perform([request])
        return (request.results ?? []).map { observation in
            let box = observation.boundingBox // normalized, bottom-left origin
            let line = CGRect(x: area.minX + box.minX * area.width, y: area.minY + (1 - box.maxY) * area.height,
                              width: box.width * area.width, height: box.height * area.height)
            let pad = max(2, line.height * 0.2)
            return line.insetBy(dx: -pad, dy: -pad)
        }
    }

    /// The text in `image`, one string per line, top to bottom. Accurate mode.
    static func lines(in image: CGImage) -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? [])
            .sorted { abs($0.boundingBox.maxY - $1.boundingBox.maxY) > 0.01 ? $0.boundingBox.maxY > $1.boundingBox.maxY : $0.boundingBox.minX < $1.boundingBox.minX }
            .compactMap { $0.topCandidates(1).first?.string }
    }
}

/// Lets a CGImage (immutable) cross into a background task.
nonisolated struct SendableImage: @unchecked Sendable {
    let image: CGImage
}
