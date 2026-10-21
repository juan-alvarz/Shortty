// Renders Design/AppIcon.svg into every size the macOS app icon needs.
// Usage: swift Scripts/make-icon.swift [svg] [appiconset dir]
import AppKit

let args = CommandLine.arguments
let svg = URL(fileURLWithPath: args.count > 1 ? args[1] : "Design/AppIcon.svg")
let output = URL(fileURLWithPath: args.count > 2 ? args[2] : "Shortty/Resources/Assets.xcassets/AppIcon.appiconset")

guard let source = NSImage(contentsOf: svg) else {
    FileHandle.standardError.write("Can't read \(svg.path) as an image\n".data(using: .utf8)!)
    exit(1)
}

var entries: [String] = []
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
        entries.append(#"{ "filename" : "\#(name)", "idiom" : "mac", "scale" : "\#(scale)x", "size" : "\#(points)x\#(points)" }"#)
    }
}

let contents = "{\n  \"images\" : [\n    " + entries.joined(separator: ",\n    ") + "\n  ],\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
try contents.write(to: output.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("Wrote \(entries.count) icon sizes to \(output.path)")
