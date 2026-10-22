import CoreGraphics
import Vision

/// On-device Vision: line boxes for Blur Text / Erase Text, and Capture Text's text-or-QR reading.
/// (Recognize Text in the editor uses Live Text instead.)
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

    /// Capture Text: a QR code / barcode's contents if there is one, else the text (lines top to bottom). Accurate mode.
    static func readable(in image: CGImage) -> Readable? {
        let codes = VNDetectBarcodesRequest()
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .accurate
        text.usesLanguageCorrection = true
        text.automaticallyDetectsLanguage = true
        try? VNImageRequestHandler(cgImage: image).perform([codes, text])
        let payloads = (codes.results ?? []).compactMap(\.payloadStringValue)
        if !payloads.isEmpty { return .code(payloads.joined(separator: "\n")) }
        let lines = (text.results ?? [])
            .sorted { abs($0.boundingBox.maxY - $1.boundingBox.maxY) > 0.01 ? $0.boundingBox.maxY > $1.boundingBox.maxY : $0.boundingBox.minX < $1.boundingBox.minX }
            .compactMap { $0.topCandidates(1).first?.string }
        return lines.isEmpty ? nil : .text(lines.joined(separator: "\n"))
    }
}

nonisolated enum Readable: Equatable, Sendable {
    case code(String), text(String)
}

/// Lets a CGImage (immutable) cross into a background task.
nonisolated struct SendableImage: @unchecked Sendable {
    let image: CGImage
}
