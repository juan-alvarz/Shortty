import AppKit
import SwiftUI

/// Something drawn on the screenshot, in image pixel coordinates (origin top-left).
struct Annotation: Identifiable, Equatable {
    enum Shape: Equatable {
        case stroke([CGPoint])
        case rectangle(CGRect)
        case ellipse(CGRect)
        /// `bend`: how far the middle sits off the straight start→end line (0 = straight).
        case arrow(start: CGPoint, end: CGPoint, bend: CGFloat, style: ArrowStyle)
        /// `origin`: top-left of the box. `pointer`: where a callout points. Font size is the annotation's `width`.
        case text(origin: CGPoint, string: String, style: TextStyle, pointer: CGPoint)
        /// Blur/erase an area, or only the text in it (`textBoxes`, found with Vision). Strength is `width`.
        case redact(rect: CGRect, style: RedactStyle, textBoxes: [CGRect])
        /// Dims everything else. Dim percent is `width`.
        case spotlight(rect: CGRect, shape: AreaShape)
        /// `source` shown enlarged inside `target`; zoom = target size / source size.
        case magnifier(source: CGRect, target: CGRect, shape: AreaShape)
        /// A pasted, dropped or newly captured picture, drawn into `rect`.
        case image(rect: CGRect, image: CGImage)
        /// A numbered badge. Its number is its position among the steps (so deleting one renumbers the rest);
        /// the diameter is `width`.
        case step(center: CGPoint)
    }

    let id = UUID()
    var shape: Shape
    var color: Color
    var width: CGFloat = Theme.strokeWidth

    var isStroke: Bool {
        if case .stroke = shape { true } else { false }
    }

    var isArrow: Bool {
        if case .arrow = shape { true } else { false }
    }

    var isText: Bool {
        if case .text = shape { true } else { false }
    }

    var isMagnifier: Bool {
        if case .magnifier = shape { true } else { false }
    }

    var isImage: Bool {
        if case .image = shape { true } else { false }
    }

    var isStep: Bool {
        if case .step = shape { true } else { false }
    }

    /// 1, 2, 3… for the steps in `annotations`, in the order they were added.
    static func stepNumbers(in annotations: [Annotation]) -> [Annotation.ID: Int] {
        var numbers: [Annotation.ID: Int] = [:]
        for annotation in annotations where annotation.isStep { numbers[annotation.id] = numbers.count + 1 }
        return numbers
    }

    /// Effects drawn below everything else (hiding and the spotlight dim), rather than in list order.
    var isBackdropEffect: Bool {
        switch shape {
        case .redact, .spotlight: true
        default: false
        }
    }

    var textBox: TextBox? {
        guard case .text(let origin, let string, let style, let pointer) = shape else { return nil }
        return TextBox(origin: origin, string: string, style: style, pointer: pointer, fontSize: width, color: color)
    }

    /// The tool that draws this kind of annotation.
    var tool: EditorModel.Tool {
        switch shape {
        case .stroke: .pencil
        case .arrow: .arrow
        case .rectangle: .rectangle
        case .ellipse: .ellipse
        case .text: .text
        case .redact: .blur
        case .spotlight: .spotlight
        case .magnifier: .magnifier
        case .image: .select // no tool draws it; it's inserted
        case .step: .step
        }
    }

    /// Arrows are edited by their points, text by its pointer, the magnifier by its two lenses; everything else by a box with 8 handles.
    var usesBoxHandles: Bool { !isArrow && !isText && !isMagnifier && !isStep }

    /// The box that selection handles sit on.
    var bounds: CGRect {
        switch shape {
        case .stroke(let points):
            let xs = points.map(\.x), ys = points.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return .zero }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        case .rectangle(let rect), .ellipse(let rect):
            return rect.standardized
        case .arrow(let start, let end, let bend, _):
            let points = ArrowCurve(start: start, end: end, bend: bend).samples(16)
            let xs = points.map(\.x), ys = points.map(\.y)
            return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        case .text(_, _, let style, let pointer):
            let box = textBox!.box
            return style == .callout ? box.union(CGRect(origin: pointer, size: .zero)) : box
        case .redact(let rect, _, _), .spotlight(let rect, _):
            return rect.standardized
        case .magnifier(let source, let target, _):
            return source.standardized.union(target.standardized)
        case .image(let rect, _):
            return rect.standardized
        case .step(let center):
            return CGRect(x: center.x - width / 2, y: center.y - width / 2, width: width, height: width)
        }
    }

    /// A shape too small to see (a click without a drag), or text with nothing typed.
    var isDegenerate: Bool {
        switch shape {
        case .stroke, .step: false
        case .arrow(let start, let end, _, _): hypot(end.x - start.x, end.y - start.y) < 4
        case .rectangle, .ellipse: bounds.width < 3 || bounds.height < 3
        case .text(_, let string, _, _): string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .redact(let rect, _, _), .spotlight(let rect, _), .magnifier(let rect, _, _), .image(let rect, _):
            abs(rect.width) < 3 || abs(rect.height) < 3
        }
    }

    /// True when `point` is on the line itself (shapes are outlines, so their inside doesn't count).
    func contains(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        let reach = tolerance + width / 2
        switch shape {
        case .stroke(let points):
            return zip(points, points.dropFirst()).contains { distance(point, toSegment: $0, $1) <= reach }
        case .rectangle(let rect):
            let rect = rect.standardized
            return rect.insetBy(dx: -reach, dy: -reach).contains(point) && !rect.insetBy(dx: reach, dy: reach).contains(point)
        case .ellipse(let rect):
            let rect = rect.standardized
            let a = rect.width / 2, b = rect.height / 2
            guard a > 0, b > 0 else { return rect.insetBy(dx: -reach, dy: -reach).contains(point) }
            let dx = (point.x - rect.midX) / a, dy = (point.y - rect.midY) / b
            return abs((dx * dx + dy * dy).squareRoot() - 1) * min(a, b) <= reach
        case .arrow(let start, let end, let bend, _):
            let points = ArrowCurve(start: start, end: end, bend: bend).samples()
            let arrowReach = tolerance + max(width, 6) // heads are wider than the line
            return zip(points, points.dropFirst()).contains { distance(point, toSegment: $0, $1) <= arrowReach }
        case .text(_, _, let style, let pointer):
            let box = textBox!.box
            if box.insetBy(dx: -tolerance, dy: -tolerance).contains(point) { return true }
            return style == .callout && distance(point, toSegment: CGPoint(x: box.midX, y: box.midY), pointer) <= tolerance + width * 0.3
        case .redact(let rect, _, _), .spotlight(let rect, _):
            return rect.standardized.insetBy(dx: -tolerance, dy: -tolerance).contains(point) // areas: anywhere inside
        case .magnifier(let source, let target, _):
            return [source, target].contains { $0.standardized.insetBy(dx: -tolerance, dy: -tolerance).contains(point) }
        case .image(let rect, _):
            return rect.standardized.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case .step(let center):
            return hypot(point.x - center.x, point.y - center.y) <= width / 2 + tolerance
        }
    }

    func moved(by offset: CGPoint) -> Annotation {
        mapped { CGPoint(x: $0.x + offset.x, y: $0.y + offset.y) }
    }

    /// Maps the `old` box onto `new`. `new` may have a negative size, which mirrors the annotation.
    func resized(from old: CGRect, to new: CGRect) -> Annotation {
        mapped { point in
            CGPoint(
                x: old.width == 0 ? point.x + new.origin.x - old.minX : new.origin.x + (point.x - old.minX) / old.width * new.size.width,
                y: old.height == 0 ? point.y + new.origin.y - old.minY : new.origin.y + (point.y - old.minY) / old.height * new.size.height)
        }
    }

    /// The box dragged from `start` to `end`; `square` forces equal sides (Shift).
    static func dragRect(from start: CGPoint, to end: CGPoint, square: Bool) -> CGRect {
        var dx = end.x - start.x, dy = end.y - start.y
        if square {
            let side = max(abs(dx), abs(dy))
            dx = CGFloat(signOf: dx, magnitudeOf: side)
            dy = CGFloat(signOf: dy, magnitudeOf: side)
        }
        return CGRect(x: start.x, y: start.y, width: dx, height: dy).standardized
    }

    private func mapped(_ transform: (CGPoint) -> CGPoint) -> Annotation {
        var copy = self
        func box(_ rect: CGRect) -> CGRect {
            let a = transform(rect.origin), b = transform(CGPoint(x: rect.maxX, y: rect.maxY))
            return CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y).standardized
        }
        switch shape {
        case .stroke(let points): copy.shape = .stroke(points.map(transform))
        case .rectangle(let rect): copy.shape = .rectangle(box(rect))
        case .ellipse(let rect): copy.shape = .ellipse(box(rect))
        case .arrow(let start, let end, let bend, let style):
            copy.shape = .arrow(start: transform(start), end: transform(end), bend: bend, style: style)
        case .text(let origin, let string, let style, let pointer):
            copy.shape = .text(origin: transform(origin), string: string, style: style, pointer: transform(pointer))
        case .redact(let rect, let style, let textBoxes):
            copy.shape = .redact(rect: box(rect), style: style, textBoxes: textBoxes.map(box)) // boxes follow until re-detected
        case .spotlight(let rect, let shape):
            copy.shape = .spotlight(rect: box(rect), shape: shape)
        case .magnifier(let source, let target, let shape):
            copy.shape = .magnifier(source: box(source), target: box(target), shape: shape)
        case .image(let rect, let image):
            copy.shape = .image(rect: box(rect), image: image)
        case .step(let center):
            copy.shape = .step(center: transform(center))
        }
        return copy
    }
}

private func distance(_ point: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
    let dx = b.x - a.x, dy = b.y - a.y
    let lengthSquared = dx * dx + dy * dy
    let t = lengthSquared == 0 ? 0 : min(max(((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared, 0), 1)
    return hypot(point.x - (a.x + t * dx), point.y - (a.y + t * dy))
}

extension CGContext {
    /// Draws annotations over `image`; the caller sets up a top-left-origin image pixel space.
    /// Order: blur/erase, then the spotlight dim, then everything else in list order (so arrows and text stay bright).
    /// `hidingTextOf`: the text being typed, whose letters the inline editor draws instead.
    /// `canvas`: the whole drawn area (the image plus anything past its edges), for the spotlight dim.
    func drawAnnotations(_ annotations: [Annotation], on image: CGImage, canvas: CGRect? = nil, hidingTextOf hiddenText: Annotation.ID? = nil) {
        for annotation in annotations {
            guard case .redact(let rect, let style, let textBoxes) = annotation.shape else { continue }
            saveGState()
            clip(to: rect.standardized)
            for area in style.textOnly ? textBoxes : [rect.standardized] {
                if style.usesStrength { pixelate(area, of: image, block: annotation.width) } else { erase(area, of: image) }
            }
            restoreGState()
        }
        drawSpotlights(annotations.filter { if case .spotlight = $0.shape { true } else { false } }, area: canvas ?? image.bounds)

        setLineCap(.round)
        setLineJoin(.round)
        let stepNumbers = Annotation.stepNumbers(in: annotations)
        for annotation in annotations where !annotation.isBackdropEffect {
            let color = NSColor(annotation.color).cgColor
            setStrokeColor(color)
            setFillColor(color)
            setLineWidth(annotation.width)
            switch annotation.shape {
            case .stroke(let points):
                addLines(between: points)
                strokePath()
            case .rectangle(let rect):
                addRect(rect.standardized)
                strokePath()
            case .ellipse(let rect):
                addEllipse(in: rect.standardized)
                strokePath()
            case .arrow(let start, let end, let bend, let style):
                let arrow = ArrowShape(start: start, end: end, bend: bend, style: style, width: annotation.width)
                if let fill = arrow.fill {
                    addPath(fill)
                    fillPath()
                }
                if let stroke = arrow.stroke {
                    setLineWidth(arrow.strokeWidth)
                    addPath(stroke)
                    strokePath()
                }
            case .text(_, _, let style, _):
                let layout = annotation.textBox!
                if style != .plain {
                    // Box and pointer filled separately: as one path, opposite windings could punch a hole where they overlap.
                    addPath(CGPath(roundedRect: layout.box, cornerWidth: layout.cornerRadius, cornerHeight: layout.cornerRadius, transform: nil))
                    fillPath()
                    if let pointer = layout.pointerPath {
                        addPath(pointer)
                        fillPath()
                    }
                }
                if annotation.id != hiddenText { layout.drawText(in: self) }
            case .magnifier(let source, let target, let shape):
                drawMagnifier(source: source, target: target, shape: shape, of: image, color: color, width: annotation.width)
            case .image(let rect, let picture):
                saveGState()
                interpolationQuality = .high
                drawUpright(picture, in: rect.standardized)
                restoreGState()
            case .step(let center):
                drawStep(stepNumbers[annotation.id] ?? 0, at: center, diameter: annotation.width, color: annotation.color)
            case .redact, .spotlight:
                break // drawn above, before everything else
            }
        }
    }
}

extension CGContext {
    /// A filled circle with its number centered in black or white, whichever reads better on the color.
    func drawStep(_ number: Int, at center: CGPoint, diameter: CGFloat, color: Color) {
        fillEllipse(in: CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter))
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: diameter * (number > 9 ? 0.46 : 0.56), weight: .bold),
            .foregroundColor: TextBox.textColor(style: .label, color: color),
        ]
        let label = NSAttributedString(string: "\(number)", attributes: attributes)
        let size = label.size()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: self, flipped: true)
        label.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))
        NSGraphicsContext.restoreGraphicsState()
    }
}

extension Annotation {
    /// What this annotation covers once drawn (line width, arrow heads), for growing the canvas.
    /// Blur and spotlight only act on the image, so they never grow it.
    var drawnBounds: CGRect {
        switch shape {
        case .redact, .spotlight: .null
        case .arrow: bounds.insetBy(dx: -(max(width * 1.8, 8) + 2), dy: -(max(width * 1.8, 8) + 2))
        case .text: bounds.insetBy(dx: -3, dy: -3)
        case .image: bounds
        case .step: bounds.insetBy(dx: -2, dy: -2)
        case .stroke, .rectangle, .ellipse, .magnifier: bounds.insetBy(dx: -(width / 2 + 2), dy: -(width / 2 + 2))
        }
    }
}

extension CGImage {
    /// The image plus anything drawn past its edges, in image pixels (origin may be negative).
    func canvasRect(for annotations: [Annotation]) -> CGRect {
        annotations.reduce(bounds) { $0.union($1.drawnBounds) }.integral
    }

    /// Flattens annotations onto a copy of the image. Anything drawn past the edges grows the result,
    /// and the new area is filled with the image's edge color.
    /// `crop`: export only that area (image px) instead.
    func rendering(_ annotations: [Annotation], crop: CGRect? = nil) -> CGImage {
        guard !annotations.isEmpty || crop != nil else { return self }
        let canvas = crop?.integral ?? canvasRect(for: annotations)
        guard let context = CGContext(
            data: nil, width: Int(canvas.width), height: Int(canvas.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return self }

        context.translateBy(x: 0, y: canvas.height)
        context.scaleBy(x: 1, y: -1) // top-left origin, like the canvas
        context.translateBy(x: -canvas.minX, y: -canvas.minY) // image pixel coordinates
        if canvas != bounds {
            context.setFillColor(edgeColor)
            context.fill(canvas)
        }
        context.drawUpright(self, in: bounds)
        context.drawAnnotations(annotations, on: self, canvas: canvas)
        return context.makeImage() ?? self
    }
}
