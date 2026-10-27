import AppKit
import simd
import Vision

/// On-device Vision: line boxes for Blur Text / Erase Text, Capture Text's text-or-QR reading, and Text Card's colored text.
/// (Recognize Text in the editor uses Live Text instead.)
nonisolated enum TextRecognition {
    /// Boxes around each line of text inside `rect` (image px, top-left origin), padded a little. Fast mode.
    static func lineBoxes(in image: CGImage, rect: CGRect) -> [CGRect] {
        let area = rect.standardized.integral.intersection(image.bounds)
        guard area.width >= 4, area.height >= 4, let crop = image.cropping(to: area) else { return [] }
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

// MARK: - Text Card

/// An area's text as it looks in the picture: lines with their indentation, each word in its color, and the
/// background behind it. Built off the main thread, then only read.
nonisolated struct StyledText: @unchecked Sendable {
    let text: NSAttributedString
    let background: NSColor
}

nonisolated extension TextRecognition {
    /// Text Card: the text inside `rect` (image px, top-left origin), line by line. Indentation and gaps come from where
    /// the words sit (in character widths, so code keeps its shape), and each word takes the color of its own pixels,
    /// so syntax highlighting survives. Accurate mode without language correction, since code isn't prose.
    static func styledText(in image: CGImage, rect: CGRect) -> StyledText? {
        let area = rect.standardized.integral.intersection(image.bounds)
        guard area.width >= 8, area.height >= 8, let crop = image.cropping(to: area), let pixels = Pixels(crop) else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: crop).perform([request])
        let size = CGSize(width: crop.width, height: crop.height)
        func pixelRect(_ box: CGRect) -> CGRect { // normalized, bottom-left → crop px, top-left
            CGRect(x: box.minX * size.width, y: (1 - box.maxY) * size.height, width: box.width * size.width, height: box.height * size.height)
        }

        struct Word { let range: Range<String.Index>; let color: NSColor? }
        struct Piece { let string: String; let box: CGRect; let words: [Word] }
        let background = pixels.dominantColor()
        var palette: [NSColor] = [] // nearly equal colors become one, so a keyword is the same color everywhere
        func snapped(_ color: NSColor?) -> NSColor? {
            guard let color else { return nil }
            if let near = palette.first(where: { $0.distance(to: color) < 0.12 }) { return near }
            palette.append(color)
            return color
        }
        let pieces: [Piece] = (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first, !candidate.string.isEmpty else { return nil }
            let string = candidate.string
            var words: [Word] = []
            var start: String.Index?
            for index in string.indices + [string.endIndex] {
                let isSpace = index == string.endIndex || string[index].isWhitespace
                if !isSpace, start == nil { start = index }
                if isSpace, let from = start {
                    let box = (try? candidate.boundingBox(for: from..<index))?.boundingBox ?? observation.boundingBox
                    words.append(Word(range: from..<index, color: snapped(pixels.inkColor(in: pixelRect(box), background: background))))
                    start = nil
                }
            }
            return Piece(string: string, box: pixelRect(observation.boundingBox), words: words)
        }
        guard !pieces.isEmpty else { return nil }

        // Rows: pieces whose middles fall within a row's height share it.
        var rows: [[Piece]] = []
        for piece in pieces.sorted(by: { $0.box.minY < $1.box.minY }) {
            if let last = rows.last?.last, abs(piece.box.midY - last.box.midY) < min(piece.box.height, last.box.height) / 2 {
                rows[rows.count - 1].append(piece)
            } else {
                rows.append([piece])
            }
        }
        rows = rows.map { $0.sorted { $0.box.minX < $1.box.minX } }
        let charWidth = median(pieces.map { $0.box.width / CGFloat(max($0.string.count, 1)) })
        // The distance from one line to the next (the median, so one line split in two can't shrink it); a gap of two is one blank line.
        let tops = rows.map { $0.map(\.box.minY).min() ?? 0 }
        let pitch = median(zip(tops.dropFirst(), tops).map { $0 - $1 })
        let left = pieces.map(\.box.minX).min() ?? 0

        let text = NSMutableAttributedString()
        for (index, row) in rows.enumerated() {
            if index > 0 {
                text.append(NSAttributedString(string: String(repeating: "\n", count: max(1, Int(((tops[index] - tops[index - 1]) / pitch).rounded())))))
            }
            var x = left
            for (index, piece) in row.enumerated() {
                let gap = Int(((piece.box.minX - x) / charWidth).rounded())
                text.append(NSAttributedString(string: String(repeating: " ", count: index == 0 ? max(gap, 0) : max(gap, 1))))
                let line = NSMutableAttributedString(string: piece.string)
                for word in piece.words {
                    guard let color = word.color else { continue }
                    line.addAttribute(.foregroundColor, value: color, range: NSRange(word.range, in: piece.string))
                }
                text.append(line)
                x = piece.box.maxX
            }
        }
        return StyledText(text: text, background: background)
    }

    private static func median(_ values: [CGFloat]) -> CGFloat {
        let sorted = values.sorted()
        return sorted.isEmpty ? 1 : max(sorted[(sorted.count - 1) / 2], 1) // the lower one of an even count
    }
}

/// An image's sRGB pixels, for reading colors.
private nonisolated struct Pixels {
    let width: Int, height: Int
    private let data: [UInt8]

    init?(_ image: CGImage) {
        let (width, height) = (image.width, image.height)
        self.width = width
        self.height = height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.data = data
    }

    /// RGB 0…1 at (x, y), top-left origin.
    func rgb(_ x: Int, _ y: Int) -> SIMD3<Double> {
        let i = (y * width + x) * 4
        return SIMD3(Double(data[i]), Double(data[i + 1]), Double(data[i + 2])) / 255
    }

    /// The most common color (to 1/16 per channel), averaged within its bucket.
    func dominantColor(in rect: CGRect? = nil, where include: (SIMD3<Double>) -> Bool = { _ in true }) -> NSColor {
        let area = (rect ?? CGRect(x: 0, y: 0, width: width, height: height)).integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        var buckets: [Int: (sum: SIMD3<Double>, count: Int)] = [:]
        let step = area.width * area.height > 400_000 ? 2 : 1
        if !area.isNull {
            for y in stride(from: Int(area.minY), to: Int(area.maxY), by: step) {
                for x in stride(from: Int(area.minX), to: Int(area.maxX), by: step) {
                    let color = rgb(x, y)
                    guard include(color) else { continue }
                    let key = Int(color.x * 15.99) << 8 | Int(color.y * 15.99) << 4 | Int(color.z * 15.99)
                    buckets[key, default: (.zero, 0)].sum += color
                    buckets[key, default: (.zero, 0)].count += 1
                }
            }
        }
        guard let best = buckets.values.max(by: { $0.count < $1.count }) else { return .black }
        let mean = best.sum / Double(best.count)
        return NSColor(srgbRed: mean.x, green: mean.y, blue: mean.z, alpha: 1)
    }

    /// A word's color: the most common of its pixels that stand out most from the background (letters' cores, not
    /// their anti-aliased edges). Nil when nothing stands out.
    func inkColor(in rect: CGRect, background: NSColor) -> NSColor? {
        let area = rect.integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !area.isNull, area.width >= 1, area.height >= 1 else { return nil }
        let back = background.rgbVector
        var farthest = 0.0
        for y in Int(area.minY)..<Int(area.maxY) {
            for x in Int(area.minX)..<Int(area.maxX) { farthest = max(farthest, simd_distance(rgb(x, y), back)) }
        }
        guard farthest > 0.15 else { return nil }
        return dominantColor(in: area) { simd_distance($0, back) > farthest * 0.6 }
    }
}

nonisolated extension NSColor {
    var rgbVector: SIMD3<Double> {
        let color = usingColorSpace(.sRGB) ?? .black
        return SIMD3(color.redComponent, color.greenComponent, color.blueComponent)
    }

    func distance(to other: NSColor) -> Double { simd_distance(rgbVector, other.rgbVector) }
}

nonisolated enum Readable: Equatable, Sendable {
    case code(String), text(String)
}
