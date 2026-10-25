import AppKit
import SwiftUI

/// Hand-drawn line icons (20×20 design grid, 1.5pt stroke) so the editor doesn't depend on SF Symbols.
enum IconKind {
    case copy, save, drag, pin, insertImage, backdrop, step, crop, cursor, pencil, arrow, text, rectangle, ellipse, magnifier, blur, spotlight,
         recognizeText, eyedropper, duplicate, bringToFront, sendToBack, trash, close, chevronUp
}

struct Icon: View {
    let kind: IconKind
    var size: CGFloat = 19

    var body: some View {
        Canvas { context, canvasSize in
            let unit = canvasSize.width / 20
            context.scaleBy(x: unit, y: unit)
            let style = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            switch kind {
            case .copy:
                let front = CGRect(x: 2.5, y: 6.5, width: 11, height: 11)
                var back = context
                back.clip(to: Path(front.insetBy(dx: -1.4, dy: -1.4)), options: .inverse)
                back.stroke(Path(roundedRect: CGRect(x: 6.5, y: 2.5, width: 11, height: 11), cornerRadius: 2.5), with: .foreground, style: style)
                context.stroke(Path(roundedRect: front, cornerRadius: 2.5), with: .foreground, style: style)
            case .save:
                var path = Path()
                path.move(to: CGPoint(x: 3, y: 12.5))
                path.addLine(to: CGPoint(x: 3, y: 15.5))
                path.addQuadCurve(to: CGPoint(x: 4.5, y: 17), control: CGPoint(x: 3, y: 17))
                path.addLine(to: CGPoint(x: 15.5, y: 17))
                path.addQuadCurve(to: CGPoint(x: 17, y: 15.5), control: CGPoint(x: 17, y: 17))
                path.addLine(to: CGPoint(x: 17, y: 12.5))
                path.addLines([CGPoint(x: 10, y: 3), CGPoint(x: 10, y: 13)])
                path.addLines([CGPoint(x: 6.5, y: 9.5), CGPoint(x: 10, y: 13), CGPoint(x: 13.5, y: 9.5)])
                context.stroke(path, with: .foreground, style: style)
            case .cursor:
                var path = Path()
                path.addLines([
                    CGPoint(x: 5.5, y: 3), CGPoint(x: 5.5, y: 15.5), CGPoint(x: 8.8, y: 12.6), CGPoint(x: 11, y: 17.2),
                    CGPoint(x: 13.2, y: 16.2), CGPoint(x: 11, y: 11.6), CGPoint(x: 15.5, y: 11.6),
                ])
                path.closeSubpath()
                context.stroke(path, with: .foreground, style: style)
            case .arrow:
                var path = Path()
                path.addLines([CGPoint(x: 4, y: 16), CGPoint(x: 15.5, y: 4.5)])
                path.addLines([CGPoint(x: 8.5, y: 4.5), CGPoint(x: 15.5, y: 4.5), CGPoint(x: 15.5, y: 11.5)])
                context.stroke(path, with: .foreground, style: style)
            case .text:
                var path = Path()
                path.addLines([CGPoint(x: 4.5, y: 6.5), CGPoint(x: 4.5, y: 4.5), CGPoint(x: 15.5, y: 4.5), CGPoint(x: 15.5, y: 6.5)])
                path.addLines([CGPoint(x: 10, y: 4.5), CGPoint(x: 10, y: 16)])
                path.addLines([CGPoint(x: 7.5, y: 16), CGPoint(x: 12.5, y: 16)])
                context.stroke(path, with: .foreground, style: style)
            case .drag:
                // A page with grip dots on both sides, like Shottr's drag handle.
                context.stroke(Path(roundedRect: CGRect(x: 6.5, y: 3.5, width: 7, height: 13), cornerRadius: 1.5), with: .foreground, style: style)
                for x in [3.0, 17.0] {
                    for y in [6.5, 10.0, 13.5] {
                        context.fill(Path(ellipseIn: CGRect(x: x - 0.9, y: y - 0.9, width: 1.8, height: 1.8)), with: .foreground)
                    }
                }
            case .pin:
                // A pushpin.
                var path = Path()
                path.addRoundedRect(in: CGRect(x: 6.5, y: 2.5, width: 7, height: 3), cornerSize: CGSize(width: 1, height: 1))
                path.addLines([CGPoint(x: 7.5, y: 5.5), CGPoint(x: 6.5, y: 11), CGPoint(x: 13.5, y: 11), CGPoint(x: 12.5, y: 5.5)])
                path.addLines([CGPoint(x: 4.5, y: 11), CGPoint(x: 15.5, y: 11)])
                path.addLines([CGPoint(x: 10, y: 11), CGPoint(x: 10, y: 17.5)])
                context.stroke(path, with: .foreground, style: style)
            case .step:
                // A badge with a 1.
                var path = Path(ellipseIn: CGRect(x: 2.75, y: 2.75, width: 14.5, height: 14.5))
                path.addLines([CGPoint(x: 8.25, y: 7.5), CGPoint(x: 10.25, y: 6), CGPoint(x: 10.25, y: 14)])
                context.stroke(path, with: .foreground, style: style)
            case .crop:
                var path = Path()
                path.addLines([CGPoint(x: 6, y: 2.5), CGPoint(x: 6, y: 14), CGPoint(x: 17.5, y: 14)])
                path.addLines([CGPoint(x: 2.5, y: 6), CGPoint(x: 14, y: 6), CGPoint(x: 14, y: 17.5)])
                context.stroke(path, with: .foreground, style: style)
            case .insertImage:
                // A picture with a plus. Two strokes: the plus overlaps the frame's top edge.
                context.stroke(Path(roundedRect: CGRect(x: 2.5, y: 5, width: 12.5, height: 11), cornerRadius: 2), with: .foreground, style: style)
                var scene = Path()
                scene.addLines([CGPoint(x: 4.5, y: 14), CGPoint(x: 8, y: 10.5), CGPoint(x: 10.5, y: 13), CGPoint(x: 12, y: 11.5), CGPoint(x: 13.5, y: 13)])
                scene.addLines([CGPoint(x: 15.5, y: 2.5), CGPoint(x: 15.5, y: 7.5)])
                scene.addLines([CGPoint(x: 13, y: 5), CGPoint(x: 18, y: 5)])
                context.stroke(scene, with: .foreground, style: style)
            case .backdrop:
                // A card on a background.
                context.stroke(Path(roundedRect: CGRect(x: 2.5, y: 3.5, width: 15, height: 13), cornerRadius: 3), with: .foreground, style: style)
                context.fill(Path(roundedRect: CGRect(x: 6, y: 7, width: 8, height: 6), cornerRadius: 1.5), with: .foreground)
            case .magnifier:
                var path = Path(ellipseIn: CGRect(x: 3, y: 3, width: 10.5, height: 10.5))
                path.addLines([CGPoint(x: 12, y: 12), CGPoint(x: 16.8, y: 16.8)])
                path.addLines([CGPoint(x: 8.25, y: 5.75), CGPoint(x: 8.25, y: 10.75)])
                path.addLines([CGPoint(x: 5.75, y: 8.25), CGPoint(x: 10.75, y: 8.25)])
                context.stroke(path, with: .foreground, style: style)
            case .blur:
                // A droplet.
                var path = Path()
                path.move(to: CGPoint(x: 10, y: 2.8))
                path.addCurve(to: CGPoint(x: 15, y: 12), control1: CGPoint(x: 12, y: 6), control2: CGPoint(x: 15, y: 8.5))
                path.addArc(center: CGPoint(x: 10, y: 12), radius: 5, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
                path.addCurve(to: CGPoint(x: 10, y: 2.8), control1: CGPoint(x: 5, y: 8.5), control2: CGPoint(x: 8, y: 6))
                context.stroke(path, with: .foreground, style: style)
            case .spotlight:
                context.stroke(Path(roundedRect: CGRect(x: 2.5, y: 4, width: 15, height: 12), cornerRadius: 2), with: .foreground, style: style)
                context.fill(Path(ellipseIn: CGRect(x: 6.5, y: 7, width: 7, height: 6)), with: .foreground)
            case .recognizeText:
                // Scan corners around two lines of text.
                var path = Path()
                for (x, y, dx, dy) in [(3.0, 3.0, 1.0, 1.0), (17.0, 3.0, -1.0, 1.0), (17.0, 17.0, -1.0, -1.0), (3.0, 17.0, 1.0, -1.0)] {
                    path.addLines([CGPoint(x: x, y: y + dy * 3.5), CGPoint(x: x, y: y), CGPoint(x: x + dx * 3.5, y: y)])
                }
                path.addLines([CGPoint(x: 6.5, y: 8.25), CGPoint(x: 13.5, y: 8.25)])
                path.addLines([CGPoint(x: 6.5, y: 11.75), CGPoint(x: 11.5, y: 11.75)])
                context.stroke(path, with: .foreground, style: style)
            case .eyedropper:
                var body = Path()
                body.addLines([CGPoint(x: 11.2, y: 6.6), CGPoint(x: 13.4, y: 8.8), CGPoint(x: 6.2, y: 16), CGPoint(x: 3.6, y: 16.4), CGPoint(x: 4, y: 13.8)])
                body.closeSubpath()
                var bulb = Path() // its own stroke: it overlaps the body's edge
                bulb.addLines([CGPoint(x: 10, y: 5.4), CGPoint(x: 14.6, y: 10)])
                bulb.move(to: CGPoint(x: 12.2, y: 7.8))
                bulb.addArc(center: CGPoint(x: 14.4, y: 5.6), radius: 2.6, startAngle: .degrees(135), endAngle: .degrees(-45), clockwise: false)
                context.stroke(body, with: .foreground, style: style)
                context.stroke(bulb, with: .foreground, style: style)
            case .rectangle:
                context.stroke(Path(roundedRect: CGRect(x: 3, y: 4.5, width: 14, height: 11), cornerRadius: 1.5), with: .foreground, style: style)
            case .ellipse:
                context.stroke(Path(ellipseIn: CGRect(x: 2.75, y: 4.25, width: 14.5, height: 11.5)), with: .foreground, style: style)
            case .pencil:
                var body = Path()
                body.addLines([
                    CGPoint(x: 3, y: 17), CGPoint(x: 6.4, y: 16.6), CGPoint(x: 17, y: 6), CGPoint(x: 14, y: 3), CGPoint(x: 3.4, y: 13.6),
                ])
                body.closeSubpath()
                let tip = Path { $0.addLines([CGPoint(x: 11.8, y: 5.2), CGPoint(x: 14.8, y: 8.2)]) }
                context.stroke(body, with: .foreground, style: style)
                context.stroke(tip, with: .foreground, style: style)
            case .duplicate:
                // Two squares, the copy with a plus.
                var path = Path(roundedRect: CGRect(x: 7, y: 7, width: 10.5, height: 10.5), cornerRadius: 2)
                path.addLines([CGPoint(x: 4.5, y: 13), CGPoint(x: 2.5, y: 13), CGPoint(x: 2.5, y: 2.5), CGPoint(x: 13, y: 2.5), CGPoint(x: 13, y: 4.5)])
                path.addLines([CGPoint(x: 12.25, y: 9.75), CGPoint(x: 12.25, y: 14.75)])
                path.addLines([CGPoint(x: 9.75, y: 12.25), CGPoint(x: 14.75, y: 12.25)])
                context.stroke(path, with: .foreground, style: style)
            case .bringToFront, .sendToBack:
                // Two overlapping squares; the filled one is on top (front) or underneath (back).
                let back = CGRect(x: 2.5, y: 2.5, width: 10, height: 10), front = CGRect(x: 7.5, y: 7.5, width: 10, height: 10)
                let (filled, outlined) = kind == .bringToFront ? (front, back) : (back, front)
                var under = context
                if kind == .bringToFront { under.clip(to: Path(front.insetBy(dx: -1.4, dy: -1.4)), options: .inverse) }
                under.stroke(Path(roundedRect: outlined, cornerRadius: 2), with: .foreground, style: style)
                var over = context
                if kind == .sendToBack { over.clip(to: Path(front.insetBy(dx: -1.4, dy: -1.4)), options: .inverse) }
                over.fill(Path(roundedRect: filled, cornerRadius: 2), with: .foreground)
            case .trash:
                var path = Path()
                path.addLines([CGPoint(x: 3.5, y: 5.5), CGPoint(x: 16.5, y: 5.5)])
                path.addLines([CGPoint(x: 7.5, y: 5.5), CGPoint(x: 7.5, y: 3), CGPoint(x: 12.5, y: 3), CGPoint(x: 12.5, y: 5.5)])
                path.addLines([CGPoint(x: 5, y: 5.5), CGPoint(x: 6, y: 17), CGPoint(x: 14, y: 17), CGPoint(x: 15, y: 5.5)])
                path.addLines([CGPoint(x: 8.5, y: 8.5), CGPoint(x: 8.5, y: 14)])
                path.addLines([CGPoint(x: 11.5, y: 8.5), CGPoint(x: 11.5, y: 14)])
                context.stroke(path, with: .foreground, style: style)
            case .close:
                var path = Path()
                path.addLines([CGPoint(x: 5, y: 5), CGPoint(x: 15, y: 15)])
                path.addLines([CGPoint(x: 15, y: 5), CGPoint(x: 5, y: 15)])
                context.stroke(path, with: .foreground, style: style)
            case .chevronUp:
                context.stroke(Path { $0.addLines([CGPoint(x: 4, y: 13), CGPoint(x: 10, y: 7), CGPoint(x: 16, y: 13)]) }, with: .foreground,
                               style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
    }
}

extension Icon {
    /// Menu bar template image: the app icon's cat (ears joined across the head, cheeks as the bottom corners),
    /// plus the lazy-shot seconds when counting down.
    static func menuBar(countdown: Int? = nil) -> NSImage {
        let text = countdown.map { "\($0)" as NSString }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.black,
        ]
        let textSize = text?.size(withAttributes: attributes) ?? .zero
        let width = 18 + (text == nil ? 0 : ceil(textSize.width) + 3)

        let image = NSImage(size: NSSize(width: width, height: 18), flipped: true) { _ in
            // On the 1024 grid of Design/AppIcon.svg, then scaled so the 548-wide mark fills 18 pt.
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 238, y: 500))
            path.line(to: NSPoint(x: 266, y: 250))
            path.line(to: NSPoint(x: 414, y: 368))
            path.curve(to: NSPoint(x: 610, y: 368), controlPoint: NSPoint(x: 512, y: 334))
            path.line(to: NSPoint(x: 758, y: 250))
            path.line(to: NSPoint(x: 786, y: 500))
            for x in [{ (v: CGFloat) in v }, { (v: CGFloat) in 1024 - v }] { // left cheek, then the mirrored right one
                path.move(to: NSPoint(x: x(238), y: 624))
                path.line(to: NSPoint(x: x(238), y: 672))
                path.curve(to: NSPoint(x: x(362), y: 790), controlPoint1: NSPoint(x: x(238), y: 742), controlPoint2: NSPoint(x: x(290), y: 790))
                path.line(to: NSPoint(x: x(420), y: 790))
            }
            let scale: CGFloat = 15.2 / 548
            path.transform(using: AffineTransform(m11: scale, m12: 0, m21: 0, m22: scale, tX: 1.4 - 238 * scale, tY: 1.5 - 250 * scale))
            path.lineWidth = 1.6
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            NSColor.black.setStroke()
            path.stroke()
            text?.draw(at: NSPoint(x: 21, y: (18 - textSize.height) / 2), withAttributes: attributes)
            return true
        }
        image.isTemplate = true
        return image
    }
}
