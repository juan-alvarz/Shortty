import AppKit
import SwiftUI

/// Text looks: a callout (filled box with a pointer), a label (filled box), or plain letters.
enum TextStyle: String, CaseIterable, Codable {
    case callout = "Callout", label = "Label", plain = "Text"

    var title: String { rawValue }
}

/// Layout of a text annotation in image pixels. Drawing, hit testing and the inline editor all use this,
/// so text sits in exactly the same place while typing and after.
struct TextBox {
    /// Filled background (callout/label); for plain text, just the glyph bounds.
    let box: CGRect
    let textRect: CGRect
    let cornerRadius: CGFloat
    /// The callout's triangle toward its pointer; nil for other styles or when the pointer is inside the box.
    let pointerPath: CGPath?
    let string: String
    let attributes: [NSAttributedString.Key: Any]

    static let drawingOptions: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]

    init(origin: CGPoint, string: String, style: TextStyle, pointer: CGPoint, fontSize: CGFloat, color: Color) {
        self.string = string
        attributes = Self.attributes(fontSize: fontSize, style: style, color: color)
        let measured = Self.measure(string, attributes: attributes, fontSize: fontSize)
        let padding = Self.padding(style: style, fontSize: fontSize)
        box = CGRect(x: origin.x, y: origin.y, width: measured.width + padding.width * 2, height: measured.height + padding.height * 2)
        textRect = CGRect(x: origin.x + padding.width, y: origin.y + padding.height, width: measured.width, height: measured.height)
        cornerRadius = (fontSize * 0.22).rounded()
        pointerPath = style == .callout ? Self.pointerPath(box: box, tip: pointer, fontSize: fontSize, cornerRadius: cornerRadius) : nil
    }

    /// Where a callout points until it's aimed: just below-left of the box, like a speech bubble.
    static func defaultPointer(below box: CGRect, fontSize: CGFloat) -> CGPoint {
        CGPoint(x: box.minX + fontSize * 0.6, y: box.maxY + fontSize * 0.8)
    }

    /// Space between the text and the box edge; the canvas uses it to put the caret where the user clicked.
    static func padding(style: TextStyle, fontSize: CGFloat) -> CGSize {
        style == .plain ? .zero : CGSize(width: (fontSize * 0.45).rounded(), height: (fontSize * 0.28).rounded())
    }

    static func attributes(fontSize: CGFloat, style: TextStyle, color: Color) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: fontSize, weight: .semibold), .foregroundColor: textColor(style: style, color: color)]
    }

    /// Plain text uses the color itself; on a filled box, black or white, whichever reads better.
    static func textColor(style: TextStyle, color: Color) -> NSColor {
        guard style != .plain else { return NSColor(color) }
        let rgb = color.rgb
        let luminance = (0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]) / 255
        return luminance > 0.62 ? .black : .white
    }

    /// Size of the text, unwrapped (lines break only at returns). Empty text and a trailing return still get a line.
    static func measure(_ string: String, attributes: [NSAttributedString.Key: Any], fontSize: CGFloat) -> CGSize {
        let sample = string.isEmpty || string.hasSuffix("\n") ? string + " " : string
        let rect = NSAttributedString(string: sample, attributes: attributes)
            .boundingRect(with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude), options: drawingOptions)
        return CGSize(width: max(ceil(rect.width), (fontSize * 0.5).rounded()), height: ceil(rect.height))
    }

    /// Draws the glyphs into a top-left-origin context.
    func drawText(in context: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        NSAttributedString(string: string, attributes: attributes).draw(with: textRect, options: Self.drawingOptions, context: nil)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Tapered wedge from the box edge facing the tip, with inward-curving sides and a small rounded point (like Shottr's).
    private static func pointerPath(box: CGRect, tip: CGPoint, fontSize: CGFloat, cornerRadius: CGFloat) -> CGPath? {
        let nx = (tip.x - box.midX) / max(box.width / 2, 1)
        let ny = (tip.y - box.midY) / max(box.height / 2, 1)
        guard abs(nx) > 1 || abs(ny) > 1 else { return nil }

        func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat { low > high ? (low + high) / 2 : min(max(value, low), high) }
        // Base: at least 1.2× the font size, growing a little with length, never past the edge's straight part.
        let vertical = abs(ny) >= abs(nx)
        let length = hypot(tip.x - box.midX, tip.y - box.midY) - (vertical ? box.height : box.width) / 2
        let wanted = min(max(fontSize * 0.6, length * 0.09), fontSize * 1.2)
        // Each side meets the box with a fillet: it leaves the edge `fillet` further out, tangent to it, so the joint is smooth.
        let room = max(((vertical ? box.width : box.height) - 2 * cornerRadius) / 2, 1)
        let half = min(wanted, room), outer = min(half * 1.6, room)
        let center: CGPoint, edge: CGPoint // middle of the base (1px into the box so there's no seam), and the edge direction
        if vertical {
            center = CGPoint(x: clamp(tip.x, box.minX + cornerRadius + outer, box.maxX - cornerRadius - outer), y: ny > 0 ? box.maxY - 1 : box.minY + 1)
            edge = CGPoint(x: 1, y: 0)
        } else {
            center = CGPoint(x: nx > 0 ? box.maxX - 1 : box.minX + 1, y: clamp(tip.y, box.minY + cornerRadius + outer, box.maxY - cornerRadius - outer))
            edge = CGPoint(x: 0, y: 1)
        }
        let along = { (d: CGFloat) in CGPoint(x: center.x + edge.x * d, y: center.y + edge.y * d) }
        let (baseA, baseB) = (along(-half), along(half))

        // Each side bows toward the base→tip line, so the wedge flares out of the box and narrows,
        // then ends in a small round cap (a needle point looks harsh) whose far edge sits on the tip.
        let base = center
        let span = hypot(tip.x - base.x, tip.y - base.y)
        guard span > 0 else { return nil }
        let u = CGPoint(x: (tip.x - base.x) / span, y: (tip.y - base.y) / span), n = CGPoint(x: -u.y, y: u.x)
        let radius = min(max(fontSize * 0.07, 1.5), span / 4)
        let cap = CGPoint(x: tip.x - u.x * radius, y: tip.y - u.y * radius)
        let bow = { (side: CGPoint) in CGPoint(x: base.x + (tip.x - base.x) * 0.3 + (side.x - base.x) * 0.25,
                                               y: base.y + (tip.y - base.y) * 0.3 + (side.y - base.y) * 0.25) }
        // Walk fillet(+n side) → round cap → fillet(−n side); the base points pull each curve along the edge first.
        let nFirst = edge.x * n.x + edge.y * n.y < 0 // baseA (−edge) is on the +n side
        let (sideN, sideMinusN) = nFirst ? (baseA, baseB) : (baseB, baseA)
        let (outerN, outerMinusN) = nFirst ? (along(-outer), along(outer)) : (along(outer), along(-outer))
        let path = CGMutablePath()
        path.move(to: outerN)
        path.addCurve(to: CGPoint(x: cap.x + n.x * radius, y: cap.y + n.y * radius), control1: sideN, control2: bow(sideN))
        path.addRelativeArc(center: cap, radius: radius, startAngle: atan2(n.y, n.x), delta: -.pi) // from +n through the tip (u)
        path.addCurve(to: outerMinusN, control1: bow(sideMinusN), control2: sideMinusN)
        path.closeSubpath()
        return path
    }
}
