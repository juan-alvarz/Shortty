// Renders Design/AppIcon.svg into every size the macOS app icon needs (Contents.json already lists them).
// Usage: swift Scripts/make-icon.swift   (from the repo root)
import AppKit

let svg = URL(fileURLWithPath: "Design/AppIcon.svg")
let output = URL(fileURLWithPath: "Shortty/Resources/Assets.xcassets/AppIcon.appiconset")

guard let source = NSImage(contentsOf: svg) else {
    FileHandle.standardError.write("Can't read \(svg.path) as an image\n".data(using: .utf8)!)
    exit(1)
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
    }
}
print("Wrote 10 icon sizes to \(output.path)")
