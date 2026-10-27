import CoreGraphics

/// Ruler tool: from the pixel under the pointer, how far the same color runs sideways and up and down, so the
/// distance between two edges in the picture reads off directly.
struct RulerPixels {
    /// Which runs the ruler shows. Holding 1 or 2 picks one.
    enum Axes { case both, horizontal, vertical }

    let image: CGImage
    private let width: Int, height: Int
    private let rgba: [UInt8] // rows top to bottom, same as image pixels

    init(_ image: CGImage) {
        self.image = image
        width = image.width
        height = image.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        rgba.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                    bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        self.rgba = rgba
    }

    /// The pixels in line with `point` (image px) that match its color, as a half-open range of x (horizontal) or y.
    /// Nil when the point is off the picture.
    func run(at point: CGPoint, horizontal: Bool, tolerance: Int = 12) -> Range<Int>? {
        let x = Int(point.x.rounded(.down)), y = Int(point.y.rounded(.down))
        guard (0..<width).contains(x), (0..<height).contains(y) else { return nil }
        let start = (y * width + x) * 4
        let matches = { (x: Int, y: Int) in
            let offset = (y * width + x) * 4
            return (0..<3).allSatisfy { abs(Int(rgba[offset + $0]) - Int(rgba[start + $0])) <= tolerance }
        }
        var low = horizontal ? x : y, high = low + 1
        let limit = horizontal ? width : height
        while low > 0, horizontal ? matches(low - 1, y) : matches(x, low - 1) { low -= 1 }
        while high < limit, horizontal ? matches(high, y) : matches(x, high) { high += 1 }
        return low..<high
    }
}
