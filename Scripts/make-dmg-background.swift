// Draws the disk image window's background into Design/dmg/background.png and background@2x.png.
// Usage: swift Scripts/make-dmg-background.swift   (from the repo root)
// Layout shared with Scripts/make-dmg.sh: a 660 × 400 pt window, 128 pt icons centered at (165, 205) and (495, 205).
import AppKit

let size = CGSize(width: 660, height: 400)
let ink = NSColor(srgbRed: 0.07, green: 0.07, blue: 0.07, alpha: 1)
let accent = NSColor(srgbRed: 1, green: 0.42, blue: 0.24, alpha: 1) // #FF6B3D, the app's accent

/// Text centered on the window, its top at `top`.
func centered(_ text: NSAttributedString, top: CGFloat) {
    let box = text.boundingRect(with: CGSize(width: size.width, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin)
    text.draw(with: CGRect(x: (size.width - ceil(box.width)) / 2, y: top, width: ceil(box.width), height: ceil(box.height)),
              options: .usesLineFragmentOrigin)
}

func drawBackground() {
    NSColor.white.setFill()
    CGRect(origin: .zero, size: size).fill()

    centered(NSAttributedString(string: "Drag Shortty into Applications.",
                                attributes: [.font: NSFont.systemFont(ofSize: 26, weight: .light), .foregroundColor: ink, .kern: -0.6]), top: 40)

    // The app icon "selected" like a capture in Shortty: outline, corner handles and its size.
    let selection = CGRect(x: 96.5, y: 136.5, width: 137, height: 129)
    accent.setStroke()
    NSBezierPath(rect: selection).stroke()
    for corner in [CGPoint(x: selection.minX, y: selection.minY), CGPoint(x: selection.maxX, y: selection.minY),
                   CGPoint(x: selection.minX, y: selection.maxY), CGPoint(x: selection.maxX, y: selection.maxY)] {
        let handle = NSBezierPath(rect: CGRect(x: corner.x - 3.5, y: corner.y - 3.5, width: 7, height: 7))
        NSColor.white.setFill()
        handle.fill()
        handle.stroke()
    }
    let sizeLabel = NSAttributedString(string: "128 × 128", attributes: [.font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                                                                         .foregroundColor: NSColor.white])
    accent.setFill()
    CGRect(x: 97, y: 116, width: ceil(sizeLabel.size().width) + 10, height: 15).fill()
    sizeLabel.draw(at: CGPoint(x: 102, y: 117))

    let arrow = NSBezierPath()
    arrow.move(to: CGPoint(x: 264, y: 205)); arrow.line(to: CGPoint(x: 390, y: 205))
    arrow.move(to: CGPoint(x: 384, y: 200)); arrow.line(to: CGPoint(x: 392, y: 205)); arrow.line(to: CGPoint(x: 384, y: 210))
    arrow.lineWidth = 1.2
    NSColor(white: 0.74, alpha: 1).setStroke()
    arrow.stroke()

    // Finder draws the icon names black in light mode and white in dark mode: a mid-gray tag keeps both readable.
    // Centered on where Finder puts the 13 pt names (about y 280–296).
    NSColor(white: 0.48, alpha: 1).setFill()
    for x in [106.0, 436.0] { CGRect(x: x, y: 277, width: 118, height: 22).fill() }

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.minimumLineHeight = 18.4
    let gray: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11.5), .foregroundColor: NSColor(white: 0.54, alpha: 1), .paragraphStyle: paragraph]
    let bold: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11.5, weight: .semibold), .foregroundColor: ink, .paragraphStyle: paragraph]
    let hint = NSMutableAttributedString(string: "If macOS blocks the first launch: ", attributes: gray)
    hint.append(NSAttributedString(string: "System Settings → Privacy & Security → Open Anyway", attributes: bold))
    hint.append(NSAttributedString(string: ".\nShortty is free and not signed by Apple. You only do this once.", attributes: gray))
    centered(hint, top: 333)
}

for scale in [1, 2] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size // draw in points; the rep maps them to pixels
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    context.cgContext.translateBy(x: 0, y: size.height)
    context.cgContext.scaleBy(x: 1, y: -1) // top-left origin, like Finder's icon positions
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
    drawBackground()
    NSGraphicsContext.restoreGraphicsState()
    let name = scale == 2 ? "background@2x.png" : "background.png"
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "Design/dmg/\(name)"))
}
print("Wrote Design/dmg/background.png and background@2x.png")
