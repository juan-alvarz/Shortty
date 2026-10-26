import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ImageExport {
    static let copiedNotice = "Copied to clipboard"

    /// "Saved to ~/Downloads/shortty-….png"
    static func savedNotice(_ url: URL) -> String { "Saved to " + (url.path as NSString).abbreviatingWithTildeInPath }

    static func copy(_ image: CGImage, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.writeObjects([NSImage(cgImage: image, size: .zero)])
    }

    /// Writes `<folder>/shortty-<yyyyMMdd-HHmmss>-image.png` (creating the folder if it's gone), returns the URL.
    @discardableResult
    static func save(_ image: CGImage, to folder: URL) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = folder.appendingPathComponent("shortty-\(formatter.string(from: .now))-image.png")
        try writePNG(image, to: url)
        return url
    }

    /// A PNG in a temporary folder for drag and drop, so nothing lands in Downloads. Replaces the previous one.
    static func temporaryFile(_ image: CGImage) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Shortty Drag", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        return try save(image, to: folder)
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}
