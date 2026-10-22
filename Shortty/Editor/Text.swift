import AppKit
import SwiftUI

/// Text looks: a callout (filled box with a pointer), a label (filled box), or plain letters.
enum TextStyle: String, CaseIterable {
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
        let padding = style == .plain ? .zero : CGSize(width: (fontSize * 0.55).rounded(), height: (fontSize * 0.3).rounded())
        box = CGRect(x: origin.x, y: origin.y, width: measured.width + padding.width * 2, height: measured.height + padding.height * 2)
        textRect = CGRect(x: origin.x + padding.width, y: origin.y + padding.height, width: measured.width, height: measured.height)
        cornerRadius = (fontSize * 0.3).rounded()
        pointerPath = style == .callout ? Self.pointerPath(box: box, tip: pointer, fontSize: fontSize, cornerRadius: cornerRadius) : nil
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

    /// Tapered band from the box edge facing the tip to the tip, ending in a rounded point (like Shottr's),
    /// so the pointer stays visible all the way instead of fading into a needle.
    private static func pointerPath(box: CGRect, tip: CGPoint, fontSize: CGFloat, cornerRadius: CGFloat) -> CGPath? {
        let nx = (tip.x - box.midX) / max(box.width / 2, 1)
        let ny = (tip.y - box.midY) / max(box.height / 2, 1)
        guard abs(nx) > 1 || abs(ny) > 1 else { return nil }

        func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat { low > high ? (low + high) / 2 : min(max(value, low), high) }
        // Base: at least 1.2× the font size, growing a little with length, never past the edge's straight part.
        let vertical = abs(ny) >= abs(nx)
        let length = hypot(tip.x - box.midX, tip.y - box.midY) - (vertical ? box.height : box.width) / 2
        let wanted = min(max(fontSize * 0.6, length * 0.09), fontSize * 1.2)
        let baseA: CGPoint, baseB: CGPoint
        if vertical {
            let half = min(wanted, max((box.width - 2 * cornerRadius) / 2, 1))
            let x = clamp(tip.x, box.minX + cornerRadius + half, box.maxX - cornerRadius - half)
            let y = ny > 0 ? box.maxY - 1 : box.minY + 1 // 1px into the box so there's no seam
            (baseA, baseB) = (CGPoint(x: x - half, y: y), CGPoint(x: x + half, y: y))
        } else {
            let half = min(wanted, max((box.height - 2 * cornerRadius) / 2, 1))
            let y = clamp(tip.y, box.minY + cornerRadius + half, box.maxY - cornerRadius - half)
            let x = nx > 0 ? box.maxX - 1 : box.minX + 1
            (baseA, baseB) = (CGPoint(x: x, y: y - half), CGPoint(x: x, y: y + half))
        }

        // Rounded end: a half circle whose far edge sits exactly on the tip.
        let base = CGPoint(x: (baseA.x + baseB.x) / 2, y: (baseA.y + baseB.y) / 2)
        let span = hypot(tip.x - base.x, tip.y - base.y)
        guard span > 0 else { return nil }
        let u = CGPoint(x: (tip.x - base.x) / span, y: (tip.y - base.y) / span) // toward the tip
        let n = CGPoint(x: -u.y, y: u.x)
        let radius = min(max(fontSize * 0.1, 1.5), span / 4)
        let center = CGPoint(x: tip.x - u.x * radius, y: tip.y - u.y * radius)
        // Walk base(+n side) → rounded end → base(−n side).
        let (sideN, sideMinusN) = (baseA.x - base.x) * n.x + (baseA.y - base.y) * n.y >= 0 ? (baseA, baseB) : (baseB, baseA)
        let path = CGMutablePath()
        path.move(to: sideN)
        path.addRelativeArc(center: center, radius: radius, startAngle: atan2(n.y, n.x), delta: -.pi) // from +n through the tip (u)
        path.addLine(to: sideMinusN)
        path.closeSubpath()
        return path
    }
}
