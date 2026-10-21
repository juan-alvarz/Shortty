import AppKit

/// Rectangle or ellipse: the spotlight's hole and the magnifier's lens.
enum AreaShape: String, CaseIterable {
    case rectangle, ellipse

    var title: String { self == .rectangle ? "Rectangle" : "Ellipse" }
    var icon: IconKind { self == .rectangle ? .rectangle : .ellipse }

    func path(in rect: CGRect, cornerRadius: CGFloat) -> CGPath {
        switch self {
        case .rectangle:
            let radius = min(cornerRadius, rect.width / 2, rect.height / 2)
            return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        case .ellipse:
            return CGPath(ellipseIn: rect, transform: nil)
        }
    }

    /// Where a line from the shape's center toward `point` leaves the shape.
    func edgePoint(of rect: CGRect, toward point: CGPoint) -> CGPoint {
        let dx = point.x - rect.midX, dy = point.y - rect.midY
        let a = rect.width / 2, b = rect.height / 2
        guard dx != 0 || dy != 0, a > 0, b > 0 else { return CGPoint(x: rect.midX, y: rect.midY) }
        let t: CGFloat = switch self {
        case .ellipse: 1 / ((dx * dx) / (a * a) + (dy * dy) / (b * b)).squareRoot()
        case .rectangle: min(dx == 0 ? .infinity : a / abs(dx), dy == 0 ? .infinity : b / abs(dy))
        }
        return CGPoint(x: rect.midX + dx * t, y: rect.midY + dy * t)
    }
}

/// Shottr's four ways to hide things.
enum RedactStyle: String, CaseIterable {
    case blur, blurText, erase, eraseText

    var title: String {
        switch self {
        case .blur: "Blur"
        case .blurText: "Blur Text"
        case .erase: "Erase"
        case .eraseText: "Erase Text"
        }
    }

    /// Only the text inside the area (found with Vision), not the whole area.
    var textOnly: Bool { self == .blurText || self == .eraseText }
    /// Blur has a strength (block size); erase doesn't.
    var usesStrength: Bool { self == .blur || self == .blurText }
}

enum Magnifier {
    static let defaultZoom: CGFloat = 2

    /// Where the magnified copy goes: beside the source (right, left, below, above), inside the image when it fits.
    static func target(for source: CGRect, zoom: CGFloat, within bounds: CGRect) -> CGRect {
        let size = CGSize(width: source.width * zoom, height: source.height * zoom)
        let gap = max(16, min(source.width, source.height) * 0.4)
        let candidates = [
            CGRect(x: source.maxX + gap, y: source.midY - size.height / 2, width: size.width, height: size.height),
            CGRect(x: source.minX - gap - size.width, y: source.midY - size.height / 2, width: size.width, height: size.height),
            CGRect(x: source.midX - size.width / 2, y: source.maxY + gap, width: size.width, height: size.height),
            CGRect(x: source.midX - size.width / 2, y: source.minY - gap - size.height, width: size.width, height: size.height),
        ]
        func visibleArea(_ rect: CGRect) -> CGFloat {
            let visible = rect.intersection(bounds)
            return visible.isNull ? 0 : visible.width * visible.height
        }
        var best = candidates.first { bounds.contains($0) } ?? candidates.max { visibleArea($0) < visibleArea($1) }!
        best.origin.x = min(max(best.minX, bounds.minX), max(bounds.maxX - best.width, bounds.minX))
        best.origin.y = min(max(best.minY, bounds.minY), max(bounds.maxY - best.height, bounds.minY))
        return best
    }
}

extension CGImage {
    nonisolated var bounds: CGRect { CGRect(x: 0, y: 0, width: width, height: height) } // used by background OCR too

    /// The screenshot's typical edge color: the fill where the canvas grows past the image.
    var edgeColor: CGColor { medianColor(around: bounds.insetBy(dx: 3, dy: 3)) }

    /// Median color of a thin ring just outside `rect` (clamped to the image).
    func medianColor(around rect: CGRect) -> CGColor {
        let ring: CGFloat = 3
        let strips = [
            CGRect(x: rect.minX - ring, y: rect.minY - ring, width: rect.width + 2 * ring, height: ring),
            CGRect(x: rect.minX - ring, y: rect.maxY, width: rect.width + 2 * ring, height: ring),
            CGRect(x: rect.minX - ring, y: rect.minY, width: ring, height: rect.height),
            CGRect(x: rect.maxX, y: rect.minY, width: ring, height: rect.height),
        ]
        var reds: [UInt8] = [], greens: [UInt8] = [], blues: [UInt8] = []
        for strip in strips {
            let area = strip.integral.intersection(bounds)
            guard !area.isNull, area.width >= 1, area.height >= 1, let crop = cropping(to: area) else { continue }
            let w = min(Int(area.width), 64), h = min(Int(area.height), 64)
            var pixels = [UInt8](repeating: 0, count: w * h * 4)
            let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { return false }
                context.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            guard drawn else { continue }
            for i in stride(from: 0, to: pixels.count, by: 4) {
                reds.append(pixels[i]); greens.append(pixels[i + 1]); blues.append(pixels[i + 2])
            }
        }
        guard !reds.isEmpty else { return CGColor(gray: 0.5, alpha: 1) }
        func median(_ values: [UInt8]) -> CGFloat { CGFloat(values.sorted()[values.count / 2]) / 255 }
        return CGColor(srgbRed: median(reds), green: median(greens), blue: median(blues), alpha: 1)
    }
}

extension CGContext {
    /// Draws an image into `rect` the right way up, in a top-left-origin context.
    func drawUpright(_ image: CGImage, in rect: CGRect) {
        saveGState()
        translateBy(x: 0, y: rect.minY + rect.maxY)
        scaleBy(x: 1, y: -1)
        draw(image, in: rect)
        restoreGState()
    }

    /// Mosaic of `block`-pixel squares over `rect`.
    func pixelate(_ rect: CGRect, of image: CGImage, block: CGFloat) {
        let area = rect.integral.intersection(image.bounds)
        guard !area.isNull, area.width >= 1, area.height >= 1, let crop = image.cropping(to: area) else { return }
        let columns = max(Int((area.width / block).rounded()), 1), rows = max(Int((area.height / block).rounded()), 1)
        guard let small = CGContext(data: nil, width: columns, height: rows, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }
        small.interpolationQuality = .high // averages each block
        small.draw(crop, in: CGRect(x: 0, y: 0, width: columns, height: rows))
        guard let blocks = small.makeImage() else { return }
        saveGState()
        interpolationQuality = .none // hard block edges
        drawUpright(blocks, in: area)
        restoreGState()
    }

    /// Paints `rect` with the color around it (median of a thin ring just outside), so it looks erased.
    func erase(_ rect: CGRect, of image: CGImage) {
        setFillColor(image.medianColor(around: rect))
        fill(rect)
    }

    /// One shared dim layer with a hole per spotlight (so overlapping spotlights don't dim each other),
    /// then each hole outlined in its color.
    func drawSpotlights(_ spots: [Annotation], area: CGRect) {
        let holes: [(rect: CGRect, shape: AreaShape, color: CGColor)] = spots.compactMap {
            if case .spotlight(let rect, let shape) = $0.shape { (rect.standardized, shape, NSColor($0.color).cgColor) } else { nil }
        }
        guard !holes.isEmpty, let strength = spots.map(\.width).max() else { return }
        saveGState()
        beginTransparencyLayer(auxiliaryInfo: nil)
        setFillColor(CGColor(gray: 0, alpha: strength / 100))
        fill(area)
        setBlendMode(.clear)
        for hole in holes {
            addPath(hole.shape.path(in: hole.rect, cornerRadius: 6))
            fillPath()
        }
        endTransparencyLayer()
        restoreGState()

        setLineWidth(Self.spotlightBorder)
        for hole in holes {
            setStrokeColor(hole.color)
            addPath(hole.shape.path(in: hole.rect, cornerRadius: 6))
            strokePath()
        }
    }

    static let spotlightBorder: CGFloat = 4

    /// The source outline, the enlarged copy inside the target, and a line joining them.
    func drawMagnifier(source: CGRect, target: CGRect, shape: AreaShape, of image: CGImage, color: CGColor, width: CGFloat) {
        let source = source.standardized, target = target.standardized
        guard source.width >= 1, source.height >= 1 else { return }
        let radius = min(target.width, target.height) * 0.12
        let visible = source.integral.intersection(image.bounds)
        if !visible.isNull, visible.width >= 1, visible.height >= 1, let crop = image.cropping(to: visible) {
            let sx = target.width / source.width, sy = target.height / source.height
            let destination = CGRect(x: target.minX + (visible.minX - source.minX) * sx, y: target.minY + (visible.minY - source.minY) * sy,
                                     width: visible.width * sx, height: visible.height * sy)
            saveGState()
            addPath(shape.path(in: target, cornerRadius: radius))
            clip()
            setFillColor(CGColor(gray: 0.1, alpha: 1)) // where the lens reaches past the image
            fill(target)
            interpolationQuality = .high
            drawUpright(crop, in: destination)
            restoreGState()
        }
        setStrokeColor(color)
        setLineWidth(width)
        setLineCap(.round)
        if !source.insetBy(dx: -width, dy: -width).intersects(target) {
            move(to: shape.edgePoint(of: source, toward: CGPoint(x: target.midX, y: target.midY)))
            addLine(to: shape.edgePoint(of: target, toward: CGPoint(x: source.midX, y: source.midY)))
        }
        addPath(shape.path(in: source, cornerRadius: min(source.width, source.height) * 0.12))
        addPath(shape.path(in: target, cornerRadius: radius))
        strokePath()
    }
}
