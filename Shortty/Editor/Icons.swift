import AppKit
import SwiftUI

/// Hand-drawn line icons (20×20 design grid, 1.5pt stroke) so the editor doesn't depend on SF Symbols.
enum IconKind { case copy, save, drag, pin, insertImage, backdrop, step, crop, cursor, pencil, arrow, text, rectangle, ellipse, magnifier, blur, spotlight, recognizeText, eyedropper }

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
                var tray = Path()
                tray.move(to: CGPoint(x: 3, y: 12.5))
                tray.addLine(to: CGPoint(x: 3, y: 15.5))
                tray.addQuadCurve(to: CGPoint(x: 4.5, y: 17), control: CGPoint(x: 3, y: 17))
                tray.addLine(to: CGPoint(x: 15.5, y: 17))
                tray.addQuadCurve(to: CGPoint(x: 17, y: 15.5), control: CGPoint(x: 17, y: 17))
                tray.addLine(to: CGPoint(x: 17, y: 12.5))
                var arrow = Path()
                arrow.move(to: CGPoint(x: 10, y: 3))
                arrow.addLine(to: CGPoint(x: 10, y: 13))
                arrow.move(to: CGPoint(x: 6.5, y: 9.5))
                arrow.addLine(to: CGPoint(x: 10, y: 13))
                arrow.addLine(to: CGPoint(x: 13.5, y: 9.5))
                context.stroke(tray, with: .foreground, style: style)
                context.stroke(arrow, with: .foreground, style: style)
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
                path.move(to: CGPoint(x: 4, y: 16))
                path.addLine(to: CGPoint(x: 15.5, y: 4.5))
                path.move(to: CGPoint(x: 8.5, y: 4.5))
                path.addLine(to: CGPoint(x: 15.5, y: 4.5))
                path.addLine(to: CGPoint(x: 15.5, y: 11.5))
                context.stroke(path, with: .foreground, style: style)
            case .text:
                var path = Path()
                path.move(to: CGPoint(x: 4.5, y: 6.5))
                path.addLine(to: CGPoint(x: 4.5, y: 4.5))
                path.addLine(to: CGPoint(x: 15.5, y: 4.5))
                path.addLine(to: CGPoint(x: 15.5, y: 6.5))
                path.move(to: CGPoint(x: 10, y: 4.5))
                path.addLine(to: CGPoint(x: 10, y: 16))
                path.move(to: CGPoint(x: 7.5, y: 16))
                path.addLine(to: CGPoint(x: 12.5, y: 16))
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
                path.move(to: CGPoint(x: 7.5, y: 5.5))
                path.addLine(to: CGPoint(x: 6.5, y: 11))
                path.addLine(to: CGPoint(x: 13.5, y: 11))
                path.addLine(to: CGPoint(x: 12.5, y: 5.5))
                path.move(to: CGPoint(x: 4.5, y: 11))
                path.addLine(to: CGPoint(x: 15.5, y: 11))
                path.move(to: CGPoint(x: 10, y: 11))
                path.addLine(to: CGPoint(x: 10, y: 17.5))
                context.stroke(path, with: .foreground, style: style)
            case .step:
                // A badge with a 1.
                context.stroke(Path(ellipseIn: CGRect(x: 2.75, y: 2.75, width: 14.5, height: 14.5)), with: .foreground, style: style)
                var one = Path()
                one.move(to: CGPoint(x: 8.25, y: 7.5))
                one.addLine(to: CGPoint(x: 10.25, y: 6))
                one.addLine(to: CGPoint(x: 10.25, y: 14))
                context.stroke(one, with: .foreground, style: style)
            case .crop:
                var path = Path()
                path.move(to: CGPoint(x: 6, y: 2.5))
                path.addLine(to: CGPoint(x: 6, y: 14))
                path.addLine(to: CGPoint(x: 17.5, y: 14))
                path.move(to: CGPoint(x: 2.5, y: 6))
                path.addLine(to: CGPoint(x: 14, y: 6))
                path.addLine(to: CGPoint(x: 14, y: 17.5))
                context.stroke(path, with: .foreground, style: style)
            case .insertImage:
                // A picture with a plus.
                context.stroke(Path(roundedRect: CGRect(x: 2.5, y: 5, width: 12.5, height: 11), cornerRadius: 2), with: .foreground, style: style)
                var scene = Path()
                scene.move(to: CGPoint(x: 4.5, y: 14))
                scene.addLine(to: CGPoint(x: 8, y: 10.5))
                scene.addLine(to: CGPoint(x: 10.5, y: 13))
                scene.addLine(to: CGPoint(x: 12, y: 11.5))
                scene.addLine(to: CGPoint(x: 13.5, y: 13))
                scene.move(to: CGPoint(x: 15.5, y: 2.5))
                scene.addLine(to: CGPoint(x: 15.5, y: 7.5))
                scene.move(to: CGPoint(x: 13, y: 5))
                scene.addLine(to: CGPoint(x: 18, y: 5))
                context.stroke(scene, with: .foreground, style: style)
            case .backdrop:
                // A card on a background.
                context.stroke(Path(roundedRect: CGRect(x: 2.5, y: 3.5, width: 15, height: 13), cornerRadius: 3), with: .foreground, style: style)
                context.fill(Path(roundedRect: CGRect(x: 6, y: 7, width: 8, height: 6), cornerRadius: 1.5), with: .foreground)
            case .magnifier:
                var path = Path(ellipseIn: CGRect(x: 3, y: 3, width: 10.5, height: 10.5))
                path.move(to: CGPoint(x: 12, y: 12))
                path.addLine(to: CGPoint(x: 16.8, y: 16.8))
                path.move(to: CGPoint(x: 8.25, y: 5.75))
                path.addLine(to: CGPoint(x: 8.25, y: 10.75))
                path.move(to: CGPoint(x: 5.75, y: 8.25))
                path.addLine(to: CGPoint(x: 10.75, y: 8.25))
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
                    path.move(to: CGPoint(x: x, y: y + dy * 3.5))
                    path.addLine(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x + dx * 3.5, y: y))
                }
                path.move(to: CGPoint(x: 6.5, y: 8.25))
                path.addLine(to: CGPoint(x: 13.5, y: 8.25))
                path.move(to: CGPoint(x: 6.5, y: 11.75))
                path.addLine(to: CGPoint(x: 11.5, y: 11.75))
                context.stroke(path, with: .foreground, style: style)
            case .eyedropper:
                var body = Path()
                body.addLines([CGPoint(x: 11.2, y: 6.6), CGPoint(x: 13.4, y: 8.8), CGPoint(x: 6.2, y: 16), CGPoint(x: 3.6, y: 16.4), CGPoint(x: 4, y: 13.8)])
                body.closeSubpath()
                var bulb = Path()
                bulb.move(to: CGPoint(x: 10, y: 5.4))
                bulb.addLine(to: CGPoint(x: 14.6, y: 10))
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
                var tip = Path()
                tip.move(to: CGPoint(x: 11.8, y: 5.2))
                tip.addLine(to: CGPoint(x: 14.8, y: 8.2))
                context.stroke(body, with: .foreground, style: style)
                context.stroke(tip, with: .foreground, style: style)
            }
        }
        .frame(width: size, height: size)
    }
}

extension Icon {
    /// Menu bar template image: viewfinder corners around a dot, plus the lazy-shot seconds when counting down.
    static func menuBar(countdown: Int? = nil) -> NSImage {
        let text = countdown.map { "\($0)" as NSString }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.black,
        ]
        let textSize = text?.size(withAttributes: attributes) ?? .zero
        let width = 18 + (text == nil ? 0 : ceil(textSize.width) + 3)

        let image = NSImage(size: NSSize(width: width, height: 18), flipped: true) { _ in
            let path = NSBezierPath()
            path.lineWidth = 1.6
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            let edge: CGFloat = 2.5, far: CGFloat = 15.5, arm: CGFloat = 4
            for (x, y, dx, dy) in [(edge, edge, 1.0, 1.0), (far, edge, -1.0, 1.0), (far, far, -1.0, -1.0), (edge, far, 1.0, -1.0)] {
                path.move(to: NSPoint(x: x, y: y + dy * arm))
                path.line(to: NSPoint(x: x, y: y))
                path.line(to: NSPoint(x: x + dx * arm, y: y))
            }
            path.appendOval(in: NSRect(x: 6.5, y: 6.5, width: 5, height: 5))
            NSColor.black.setStroke()
            path.stroke()
            text?.draw(at: NSPoint(x: 21, y: (18 - textSize.height) / 2), withAttributes: attributes)
            return true
        }
        image.isTemplate = true
        return image
    }
}
