import CoreGraphics

/// Joins frames of a fixed screen area captured while the page scrolls down into one tall image.
///
/// Each frame's rows get a hash. Rows that sit still between frames at the top and bottom are a sticky
/// header/footer (kept once). Inside the moving band, the shift that lines up the most non-blank rows with
/// the previous frame is how far the page scrolled; only those newly revealed rows are appended.
struct ScrollStitcher {
    enum Outcome: Equatable {
        case started, appended(rows: Int), unchanged
        /// No overlap with the last frame (scrolled too far between captures); the frame is skipped.
        case lost
    }

    private struct Frame {
        let image: CGImage
        let rows: [UInt64]
        /// One-color rows match anywhere, so they don't count as evidence.
        let blank: [Bool]
    }

    private var pieces: [(image: CGImage, rows: Range<Int>)] = []
    private var last: Frame?
    private var footer = 0

    /// Height of the stitched result so far, in pixels.
    var height: Int {
        guard let last else { return 0 }
        return pieces.dropFirst().reduce(last.rows.count) { $0 + $1.rows.count }
    }

    mutating func add(_ image: CGImage) -> Outcome {
        guard let frame = Self.frame(image) else { return .lost }
        guard let previous = last else {
            last = frame
            pieces = [(image, 0..<frame.rows.count)]
            return .started
        }
        let h = frame.rows.count
        guard h == previous.rows.count, image.width == previous.image.width else { return .lost }

        var top = 0
        while top < h, frame.rows[top] == previous.rows[top] { top += 1 }
        if top == h { return .unchanged }
        var bottom = 0
        while bottom < h - top, frame.rows[h - 1 - bottom] == previous.rows[h - 1 - bottom] { bottom += 1 }
        let band = top..<(h - bottom)
        guard band.count > 1 else { return .lost }

        // Smallest shift with the most matching non-blank rows (ties go to smaller shifts: we capture often).
        var best = (shift: 0, score: 0, candidates: 0)
        for shift in 1..<band.count {
            var score = 0, candidates = 0
            for row in band.lowerBound..<(band.upperBound - shift) where !frame.blank[row] {
                candidates += 1
                if frame.rows[row] == previous.rows[row + shift] { score += 1 }
            }
            if score > best.score { best = (shift, score, candidates) }
        }
        guard best.score >= 3, best.score * 2 >= best.candidates else { return .lost }

        let newRows = (band.upperBound - best.shift)..<band.upperBound
        pieces.append((image, newRows))
        footer = bottom
        last = frame
        return .appended(rows: newRows.count)
    }

    /// The tall image: first frame (without its footer), each frame's new rows, then the footer once.
    func image() -> CGImage? {
        var slices = pieces
        guard let last, !slices.isEmpty else { return nil }
        let h = last.rows.count, width = last.image.width
        slices[0].rows = 0..<(h - footer)
        if footer > 0 { slices.append((last.image, (h - footer)..<h)) }
        let total = slices.reduce(0) { $0 + $1.rows.count }
        guard let context = CGContext(data: nil, width: width, height: total, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        var y = 0 // from the top
        for slice in slices {
            if let part = slice.image.cropping(to: CGRect(x: 0, y: slice.rows.lowerBound, width: width, height: slice.rows.count)) {
                context.draw(part, in: CGRect(x: 0, y: total - y - slice.rows.count, width: width, height: slice.rows.count))
            }
            y += slice.rows.count
        }
        return context.makeImage()
    }

    /// Row hashes (FNV-1a), ignoring the right edge where scrollbars come and go.
    private static func frame(_ image: CGImage) -> Frame? {
        let width = image.width, height = image.height
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt32.self, capacity: width * height)
        let used = max(width - min(24, width / 10), 1)
        var rows = [UInt64](repeating: 0, count: height), blank = [Bool](repeating: true, count: height)
        for y in 0..<height {
            let row = pixels + y * width
            let first = row[0]
            var hash: UInt64 = 0xcbf2_9ce4_8422_2325
            var same = true
            for x in 0..<used {
                let pixel = row[x]
                hash = (hash ^ UInt64(pixel)) &* 0x100_0000_01b3
                if pixel != first { same = false }
            }
            rows[y] = hash
            blank[y] = same
        }
        return Frame(image: image, rows: rows, blank: blank)
    }
}
