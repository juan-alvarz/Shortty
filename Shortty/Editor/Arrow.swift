import CoreGraphics

/// Shottr's four arrow looks: hollow outline, solid tapered, thin line, double-headed line.
enum ArrowStyle: String, CaseIterable {
    case outline, solid, line, double

    var title: String {
        switch self {
        case .outline: "Outline"
        case .solid: "Solid"
        case .line: "Line"
        case .double: "Double"
        }
    }
}

/// Quadratic curve from `start` to `end`. `bend` is how far the arrow's middle sits off the straight line (signed, px).
struct ArrowCurve {
    let start: CGPoint
    let end: CGPoint
    let control: CGPoint

    init(start: CGPoint, end: CGPoint, bend: CGFloat) {
        self.start = start
        self.end = end
        let normal = Self.normal(from: start, to: end)
        // The curve passes through its control point's halfway mark, so 2× bend puts the middle exactly `bend` off the line.
        control = CGPoint(x: (start.x + end.x) / 2 + normal.x * 2 * bend, y: (start.y + end.y) / 2 + normal.y * 2 * bend)
    }

    /// Unit vector perpendicular to a→b (zero when a == b).
    static func normal(from a: CGPoint, to b: CGPoint) -> CGPoint {
        let dx = b.x - a.x, dy = b.y - a.y, length = hypot(dx, dy)
        return length > 0 ? CGPoint(x: -dy / length, y: dx / length) : .zero
    }

    /// The bend that puts the middle handle under `point`.
    static func bend(through point: CGPoint, start: CGPoint, end: CGPoint) -> CGFloat {
        let normal = normal(from: start, to: end)
        return (point.x - (start.x + end.x) / 2) * normal.x + (point.y - (start.y + end.y) / 2) * normal.y
    }

    func point(at t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
                       y: u * u * start.y + 2 * u * t * control.y + t * t * end.y)
    }

    var middle: CGPoint { point(at: 0.5) }

    func samples(_ count: Int = 32) -> [CGPoint] {
        (0...count).map { point(at: CGFloat($0) / CGFloat(count)) }
    }
}

/// Ready-to-draw paths for one arrow, in the same coordinates as its points.
struct ArrowShape {
    private(set) var fill: CGPath?
    private(set) var stroke: CGPath?
    private(set) var strokeWidth: CGFloat = 0

    init(start: CGPoint, end: CGPoint, bend: CGFloat, style: ArrowStyle, width: CGFloat) {
        let points = ArrowCurve(start: start, end: end, bend: bend).samples()
        let length = pathLength(points)

        switch style {
        case .line, .double:
            var headLength = max(width * 3.2, 10)
            var headHalf = headLength * 0.5
            let limit = length * (style == .double ? 0.4 : 0.6) // short arrows get smaller heads
            if headLength > limit, headLength > 0 {
                headHalf *= limit / headLength
                headLength = limit
            }
            var (shaft, endBase) = trimEnd(points, by: headLength)
            let heads = CGMutablePath()
            addHead(to: heads, base: endBase, tip: end, halfWidth: headHalf)
            if style == .double {
                let (reversed, startBase) = trimEnd(shaft.reversed(), by: headLength)
                shaft = reversed.reversed()
                addHead(to: heads, base: startBase, tip: start, halfWidth: headHalf)
            }
            let line = CGMutablePath()
            line.addLines(between: shaft)
            stroke = line
            strokeWidth = width
            fill = heads

        case .solid, .outline:
            var headLength = max(width * 3, 12)
            var headHalf = max(width * 1.6, 7)
            if headLength > length * 0.6, headLength > 0 {
                headHalf *= length * 0.6 / headLength
                headLength = length * 0.6
            }
            // Tapered body: thin at the tail, full width where it meets the head.
            let tailHalf = width * 0.15, neckHalf = width * 0.5
            let (shaft, base) = trimEnd(points, by: headLength)
            let shaftLength = pathLength(shaft)
            var left: [CGPoint] = [], right: [CGPoint] = []
            var walked: CGFloat = 0
            for i in shaft.indices {
                if i > 0 { walked += distance(shaft[i - 1], shaft[i]) }
                let normal = ArrowCurve.normal(from: shaft[max(i - 1, 0)], to: shaft[min(i + 1, shaft.count - 1)])
                let half = tailHalf + (neckHalf - tailHalf) * (shaftLength > 0 ? walked / shaftLength : 1)
                left.append(offset(shaft[i], normal, half))
                right.append(offset(shaft[i], normal, -half))
            }
            let normal = ArrowCurve.normal(from: base, to: end)
            let outline = CGMutablePath()
            outline.addLines(between: left + [offset(base, normal, headHalf), end, offset(base, normal, -headHalf)] + right.reversed())
            outline.closeSubpath()
            if style == .solid {
                fill = outline
            } else {
                stroke = outline
                strokeWidth = max(width * 0.35, 2)
            }
        }
    }
}

private func addHead(to path: CGMutablePath, base: CGPoint, tip: CGPoint, halfWidth: CGFloat) {
    let normal = ArrowCurve.normal(from: base, to: tip)
    path.addLines(between: [offset(base, normal, halfWidth), tip, offset(base, normal, -halfWidth)])
    path.closeSubpath()
}

/// Cuts `length` off the end of a polyline. Returns the rest and the cut point (where the head starts).
private func trimEnd(_ points: [CGPoint], by length: CGFloat) -> (shaft: [CGPoint], base: CGPoint) {
    var remaining = length
    var i = points.count - 1
    while i > 0 {
        let segment = distance(points[i - 1], points[i])
        if segment >= remaining, segment > 0 {
            let t = remaining / segment
            let base = CGPoint(x: points[i].x + (points[i - 1].x - points[i].x) * t, y: points[i].y + (points[i - 1].y - points[i].y) * t)
            return (Array(points[..<i]) + [base], base)
        }
        remaining -= segment
        i -= 1
    }
    return ([points[0]], points[0])
}

private func pathLength(_ points: [CGPoint]) -> CGFloat {
    zip(points, points.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
}

private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(b.x - a.x, b.y - a.y) }

private func offset(_ point: CGPoint, _ normal: CGPoint, _ amount: CGFloat) -> CGPoint {
    CGPoint(x: point.x + normal.x * amount, y: point.y + normal.y * amount)
}
