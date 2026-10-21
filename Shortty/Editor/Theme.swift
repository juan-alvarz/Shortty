import SwiftUI

enum Theme {
    static let accent = Color(red: 1.0, green: 0.42, blue: 0.24)
    static let chrome = Color(red: 0.165, green: 0.165, blue: 0.18)
    static let chromeText = Color.white.opacity(0.85)
    static let chromeSubtext = Color.white.opacity(0.45)
    /// Fixed RGB (not system colors) so exports look the same in light and dark mode.
    static let palette: [Color] = [
        accent,
        Color(red: 0.94, green: 0.23, blue: 0.23), // red
        Color(red: 1.00, green: 0.80, blue: 0.10), // yellow
        Color(red: 0.20, green: 0.78, blue: 0.35), // green
        Color(red: 0.10, green: 0.75, blue: 0.85), // cyan
        Color(red: 0.16, green: 0.47, blue: 1.00), // blue
        Color(red: 0.60, green: 0.35, blue: 0.95), // purple
        Color(red: 1.00, green: 0.35, blue: 0.65), // pink
        .white,
        .black,
    ]
    static let strokeWidth: CGFloat = 4 // image pixels

    /// Subtle dark checkerboard, tiled behind the image.
    static let checkerboard: NSImage = {
        let cell: CGFloat = 12
        return NSImage(size: NSSize(width: cell * 2, height: cell * 2), flipped: false) { _ in
            NSColor(white: 0.17, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: cell * 2, height: cell * 2).fill()
            NSColor(white: 0.20, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: cell, height: cell).fill()
            NSRect(x: cell, y: cell, width: cell, height: cell).fill()
            return true
        }
    }()
}

/// Rounded label drawn with AppKit (overlays, canvas). `origin` receives the pill size and returns its corner.
func drawPill(_ text: String,
              font: NSFont = .systemFont(ofSize: 12, weight: .medium),
              fill: NSColor = NSColor(white: 0.08, alpha: 0.9),
              origin: (CGSize) -> CGPoint) {
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
    let textSize = (text as NSString).size(withAttributes: attributes)
    let size = CGSize(width: ceil(textSize.width) + 20, height: ceil(textSize.height) + 10)
    let rect = CGRect(origin: origin(size), size: size)
    fill.setFill()
    NSBezierPath(roundedRect: rect, xRadius: size.height / 2, yRadius: size.height / 2).fill()
    (text as NSString).draw(at: CGPoint(x: rect.minX + 10, y: rect.minY + (size.height - textSize.height) / 2), withAttributes: attributes)
}

extension Color {
    /// sRGB channels 0–255.
    init(rgb: [Double]) {
        self.init(.sRGB, red: rgb[0] / 255, green: rgb[1] / 255, blue: rgb[2] / 255)
    }

    var rgb: [Double] {
        let color = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return [color.redComponent, color.greenComponent, color.blueComponent].map { ($0 * 255).rounded().clamped(to: 0...255) }
    }

    /// "#RRGGBB". Also used to compare colors, since `Color ==` treats `.white` and white RGB as different.
    var hex: String { "#" + rgb.map { String(format: "%02X", Int($0)) }.joined() }

    /// Accepts "#RRGGBB", "RRGGBB" or "#RGB".
    init?(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespaces).uppercased()
        if digits.hasPrefix("#") { digits.removeFirst() }
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(rgb: [Double(value >> 16 & 0xFF), Double(value >> 8 & 0xFF), Double(value & 0xFF)])
    }
}
