import AppKit

/// Text Card tool: the text in an area of the screenshot redrawn as a clean window-like card, in a monospaced font,
/// each word in the color it had in the picture (so code keeps its syntax highlighting). Pure: preparing and drawing.
enum TextCard {
    static let fontSizes: ClosedRange<Double> = 10...28
    /// Text without a color of its own: it follows the card's text color. Recoloring a range removes it there.
    static let followsTextColor = NSAttributedString.Key("shortty.followsTextColor")

    static let padding = CGSize(width: 24, height: 20)
    static let barHeight: CGFloat = 36
    static let cornerRadius: CGFloat = 12
    static let lineHeight: CGFloat = 1.25

    struct Style {
        var background: NSColor
        var windowBar: Bool
        var title: String
    }

    struct Prepared {
        let text: NSMutableAttributedString
        let background: NSColor
        let textColor: NSColor
    }

    /// Ready for the card: trailing spaces and blank lines at the ends removed, monospaced at `fontSize`. Words keep
    /// their recognized colors; the rest gets a text color that reads well on the background.
    static func prepare(_ styled: StyledText, fontSize: CGFloat) -> Prepared {
        let text = NSMutableAttributedString(attributedString: styled.text)
        trimLines(text)
        text.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if value == nil { text.addAttribute(followsTextColor, value: true, range: range) }
        }
        let textColor = contrastingText(on: styled.background)
        setFontSize(fontSize, in: text)
        setTextColor(textColor, in: text)
        return Prepared(text: text, background: styled.background, textColor: textColor)
    }

    static func contrastingText(on background: NSColor) -> NSColor {
        background.luminance > 0.5 ? NSColor(srgbRed: 0.12, green: 0.14, blue: 0.16, alpha: 1) : NSColor(srgbRed: 0.9, green: 0.9, blue: 0.91, alpha: 1)
    }

    /// Monospaced at `size`, keeping bold and italic; also the card's line height.
    static func setFontSize(_ size: CGFloat, in text: NSMutableAttributedString) {
        let full = NSRange(location: 0, length: text.length)
        text.enumerateAttribute(.font, in: full) { value, range, _ in
            text.addAttribute(.font, value: font(size: size, like: value as? NSFont), range: range)
        }
        text.addAttribute(.paragraphStyle, value: paragraphStyle, range: full)
    }

    static func font(size: CGFloat, like original: NSFont? = nil) -> NSFont {
        let traits = original?.fontDescriptor.symbolicTraits ?? []
        let base = NSFont.monospacedSystemFont(ofSize: size, weight: traits.contains(.bold) ? .bold : .regular)
        guard traits.contains(.italic) else { return base }
        return NSFont(descriptor: base.fontDescriptor.withSymbolicTraits(.italic), size: size) ?? base
    }

    static var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = lineHeight
        return style
    }

    /// The text that has no color of its own.
    static func setTextColor(_ color: NSColor, in text: NSMutableAttributedString) {
        text.enumerateAttribute(followsTextColor, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if value != nil { text.addAttribute(.foregroundColor, value: color, range: range) }
        }
    }

    /// A color picked for part of the text: it keeps it when the card's text color changes.
    static func setColor(_ color: NSColor, range: NSRange, in text: NSMutableAttributedString) {
        text.addAttribute(.foregroundColor, value: color, range: range)
        text.removeAttribute(followsTextColor, range: range)
    }

    /// What new typing looks like.
    static func typingAttributes(fontSize: CGFloat, textColor: NSColor) -> [NSAttributedString.Key: Any] {
        [.font: font(size: fontSize), .foregroundColor: textColor, .paragraphStyle: paragraphStyle, followsTextColor: true]
    }

    // MARK: Drawing

    /// The text's size in points, lines never wrapped.
    static func textSize(_ text: NSAttributedString) -> CGSize {
        let bounds = text.boundingRect(with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude),
                                       options: [.usesLineFragmentOrigin, .usesFontLeading])
        return CGSize(width: ceil(bounds.width), height: ceil(bounds.height))
    }

    /// The card's size in points.
    static func size(of text: NSAttributedString, style: Style) -> CGSize {
        let content = textSize(text)
        return CGSize(width: max(content.width + padding.width * 2, 240),
                      height: content.height + padding.height * 2 + (style.windowBar ? barHeight - 8 : 0))
    }

    /// The finished card at `scale` pixels per point, with transparent rounded corners.
    static func render(_ text: NSAttributedString, style: Style, scale: CGFloat = 2) -> CGImage? {
        let size = size(of: text, style: style)
        guard let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.translateBy(x: 0, y: size.height * scale)
        context.scaleBy(x: scale, y: -scale) // top-left origin, in points
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        defer { NSGraphicsContext.restoreGraphicsState() }

        let card = CGRect(origin: .zero, size: size)
        style.background.setFill()
        NSBezierPath(roundedRect: card, xRadius: cornerRadius, yRadius: cornerRadius).fill()
        NSColor(white: style.background.luminance > 0.5 ? 0 : 1, alpha: 0.08).setStroke()
        let edge = NSBezierPath(roundedRect: card.insetBy(dx: 0.5, dy: 0.5), xRadius: cornerRadius - 0.5, yRadius: cornerRadius - 0.5)
        edge.lineWidth = 1
        edge.stroke()

        var top = padding.height
        if style.windowBar {
            drawWindowBar(width: size.width, title: style.title, on: style.background)
            top = barHeight + padding.height - 8
        }
        text.draw(with: CGRect(x: padding.width, y: top, width: size.width - padding.width * 2, height: size.height - top),
                  options: [.usesLineFragmentOrigin, .usesFontLeading])
        return context.makeImage()
    }

    static let windowButtonColors = [NSColor(srgbRed: 1, green: 0.373, blue: 0.341, alpha: 1),
                                     NSColor(srgbRed: 0.996, green: 0.737, blue: 0.180, alpha: 1),
                                     NSColor(srgbRed: 0.157, green: 0.784, blue: 0.251, alpha: 1)]

    /// Traffic lights and the title, in a flipped context.
    private static func drawWindowBar(width: CGFloat, title: String, on background: NSColor) {
        for (index, color) in windowButtonColors.enumerated() {
            color.setFill()
            NSBezierPath(ovalIn: CGRect(x: 18 + CGFloat(index) * 20, y: barHeight / 2 - 6, width: 12, height: 12)).fill()
        }
        guard !title.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor(white: background.luminance > 0.5 ? 0 : 1, alpha: 0.55),
        ]
        let titleSize = (title as NSString).size(withAttributes: attributes)
        let maxWidth = width - 2 * 90 // clear of the lights
        (title as NSString).draw(with: CGRect(x: max(90, (width - min(titleSize.width, maxWidth)) / 2), y: (barHeight - titleSize.height) / 2,
                                              width: maxWidth, height: titleSize.height),
                                 options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes)
    }

    /// Trailing spaces off every line, blank lines off both ends.
    private static func trimLines(_ text: NSMutableAttributedString) {
        func lines() -> [NSRange] {
            var ranges: [NSRange] = []
            let string = text.string as NSString
            string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: [.byLines, .substringNotRequired]) { _, range, _, _ in
                ranges.append(range)
            }
            return ranges
        }
        func isBlank(_ range: NSRange) -> Bool { (text.string as NSString).substring(with: range).allSatisfy(\.isWhitespace) }

        for range in lines().reversed() {
            let line = (text.string as NSString).substring(with: range)
            let trailing = line.reversed().prefix(while: { $0 == " " }).count
            if trailing > 0 { text.deleteCharacters(in: NSRange(location: NSMaxRange(range) - trailing, length: trailing)) }
        }
        while let last = lines().last, isBlank(last) {
            let from = max(last.location - 1, 0)
            text.deleteCharacters(in: NSRange(location: from, length: text.length - from))
        }
        if let lastLine = lines().last, NSMaxRange(lastLine) < text.length { // a final newline
            text.deleteCharacters(in: NSRange(location: NSMaxRange(lastLine), length: text.length - NSMaxRange(lastLine)))
        }
        while let first = lines().first, isBlank(first), lines().count > 1 {
            text.deleteCharacters(in: NSRange(location: 0, length: lines()[1].location))
        }
    }
}

extension NSColor {
    /// Relative luminance (0 black … 1 white) of the sRGB color.
    var luminance: Double {
        let color = usingColorSpace(.sRGB) ?? .black
        return 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
    }
}
