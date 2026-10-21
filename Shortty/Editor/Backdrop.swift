import AppKit
import SwiftUI

/// Shottr's "Gradient Backdrop": the finished screenshot as a card on a gradient, with padding, rounded corners
/// and a soft shadow. Sizes are fractions of the screenshot's longer side, so they look the same at any size.
struct Backdrop: Equatable {
    var preset = 0
    var padding: CGFloat = 0.08
    var cornerRadius: CGFloat = 0.015
    var shadow: CGFloat = 0.6

    static let presets: [(name: String, colors: [Color])] = [
        ("Sunset", [Color(hex: "#FF8A3D")!, Color(hex: "#FF3D7F")!]),
        ("Ocean", [Color(hex: "#3A8DFF")!, Color(hex: "#8E5CFF")!]),
        ("Mint", [Color(hex: "#43E97B")!, Color(hex: "#38C9D7")!]),
        ("Peach", [Color(hex: "#FFD3A5")!, Color(hex: "#FD6585")!]),
        ("Sky", [Color(hex: "#A1C4FD")!, Color(hex: "#C2E9FB")!]),
        ("Lavender", [Color(hex: "#E0C3FC")!, Color(hex: "#8EC5FC")!]),
        ("Night", [Color(hex: "#2B2E3A")!, Color(hex: "#5A3E7A")!]),
        ("Paper", [Color(hex: "#F4F4F4")!, Color(hex: "#DADADA")!]),
    ]

    static let paddingRange: ClosedRange<CGFloat> = 0...0.25
    static let cornerRange: ClosedRange<CGFloat> = 0...0.05
    static let shadowRange: ClosedRange<CGFloat> = 0...1

    var colors: [Color] { Self.presets[preset].colors }

    func paddingSize(for content: CGRect) -> CGFloat { (max(content.width, content.height) * padding).rounded() }
    func radius(for content: CGRect) -> CGFloat { max(content.width, content.height) * cornerRadius }
}

extension CGContext {
    /// Gradient over `canvas`, a shadow under the `content` card, then `drawContent` clipped to its rounded corners.
    /// Works in any top-left-origin units (image pixels for export, the same for the editor).
    func drawBackdrop(_ backdrop: Backdrop, canvas: CGRect, content: CGRect, drawContent: () -> Void) {
        let colors = backdrop.colors.map { NSColor($0).cgColor } as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: nil) {
            saveGState()
            clip(to: canvas)
            drawLinearGradient(gradient, start: CGPoint(x: canvas.minX, y: canvas.minY), end: CGPoint(x: canvas.maxX, y: canvas.maxY), options: [])
            restoreGState()
        }
        let radius = backdrop.radius(for: content)
        let card = CGPath(roundedRect: content, cornerWidth: radius, cornerHeight: radius, transform: nil)
        if backdrop.shadow > 0 {
            // Shadow sizes are in device pixels, so convert from our units; positive y is up in device space.
            let toDevice = abs(userSpaceToDeviceSpaceTransform.a)
            let blur = max(content.width, content.height) * 0.04 * backdrop.shadow * toDevice
            saveGState()
            setShadow(offset: CGSize(width: 0, height: -blur * 0.35), blur: blur, color: CGColor(gray: 0, alpha: 0.5 * backdrop.shadow))
            setFillColor(CGColor(gray: 0, alpha: 1))
            addPath(card)
            fillPath()
            restoreGState()
        }
        saveGState()
        addPath(card)
        clip()
        drawContent()
        restoreGState()
    }
}

extension CGImage {
    /// This image (the flattened screenshot) placed on `backdrop`.
    func addingBackdrop(_ backdrop: Backdrop) -> CGImage {
        let content = bounds
        let pad = backdrop.paddingSize(for: content)
        let canvas = content.insetBy(dx: -pad, dy: -pad)
        guard let context = CGContext(data: nil, width: Int(canvas.width), height: Int(canvas.height), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return self }
        context.translateBy(x: 0, y: canvas.height)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: -canvas.minX, y: -canvas.minY)
        context.drawBackdrop(backdrop, canvas: canvas, content: content) { context.drawUpright(self, in: content) }
        return context.makeImage() ?? self
    }
}
