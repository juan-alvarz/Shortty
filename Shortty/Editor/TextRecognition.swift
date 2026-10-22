import CoreGraphics
import Vision

/// On-device text detection (Vision) for Blur Text / Erase Text. Recognize Text uses Live Text (VisionKit) instead.
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
}

