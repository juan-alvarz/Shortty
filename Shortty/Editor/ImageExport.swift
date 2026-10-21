import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ImageExport {
    static func copy(_ image: CGImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([NSImage(cgImage: image, size: .zero)])
    }

    /// Writes `<folder>/shortty-<yyyyMMdd-HHmmss>-image.png` (creating the folder if it's gone), returns the URL.
    @discardableResult
    static func save(_ image: CGImage, to folder: URL) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(fileName())
        try writePNG(image, to: url)
        return url
    }

    /// A PNG in a temporary folder for drag and drop, so nothing lands in Downloads. Replaces the previous one.
    static func temporaryFile(_ image: CGImage) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Shortty Drag", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(fileName())
        try writePNG(image, to: url)
        return url
    }

    private static func fileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "shortty-\(formatter.string(from: .now))-image.png"
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}
