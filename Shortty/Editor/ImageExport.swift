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

    /// Writes `<folder>/shortty-<yyyyMMdd-HHmmss>-image.png`, returns the URL.
    @discardableResult
    static func save(_ image: CGImage, to folder: URL) throws -> URL {
        let url = try newFile("image.png", in: folder)
        try writePNG(image, to: url)
        return url
    }

    /// `<folder>/shortty-<yyyyMMdd-HHmmss>-<name>`, creating the folder if it's gone.
    static func newFile(_ name: String, in folder: URL) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return folder.appendingPathComponent("shortty-\(formatter.string(from: .now))-\(name)")
    }

    /// A PNG in a temporary folder for drag and drop, so nothing lands in Downloads. Replaces the previous one.
    static let temporaryFolder = FileManager.default.temporaryDirectory.appendingPathComponent("Shortty Drag", isDirectory: true)

    static func temporaryFile(_ image: CGImage) throws -> URL {
        try? FileManager.default.removeItem(at: temporaryFolder)
        return try save(image, to: temporaryFolder)
    }

    // MARK: GIF recordings (a capture whose file is a .gif)

    /// Writes the GIF at `file` to `url` with the edits drawn on every frame; a plain copy when there's nothing to draw.
    /// shortcut: every frame is drawn on the main thread, a few seconds for a long clip. Move it off, with a notice, if that hurts.
    static func writeGIF(_ file: URL, edits: SavedEdits = SavedEdits(), backdrop: Backdrop? = nil, to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        if edits.annotations.isEmpty, edits.crop == nil, backdrop == nil { return try FileManager.default.copyItem(at: file, to: url) }
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { throw CocoaError(.fileReadCorruptFile) }
        try GIF.write((0..<CGImageSourceGetCount(source)).compactMap {
            CGImageSourceCreateImageAtIndex(source, $0, nil)?.rendering(edits.annotations, crop: edits.crop, backdrop: backdrop)
        }, to: url)
    }

    /// Writes `<folder>/shortty-<yyyyMMdd-HHmmss>-recording.gif`, returns the URL.
    @discardableResult
    static func saveGIF(_ file: URL, edits: SavedEdits = SavedEdits(), backdrop: Backdrop? = nil, to folder: URL) throws -> URL {
        let url = try newFile("recording.gif", in: folder)
        try writeGIF(file, edits: edits, backdrop: backdrop, to: url)
        return url
    }

    /// Copy for a GIF: a file on the clipboard, the way Finder copies one, so pasting keeps the animation.
    /// It waits in its own temporary folder until the next GIF is copied.
    static func copyGIF(_ file: URL, edits: SavedEdits = SavedEdits(), backdrop: Backdrop? = nil, to pasteboard: NSPasteboard = .general) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Shortty Copy", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        let url = try saveGIF(file, edits: edits, backdrop: backdrop, to: folder)
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
    }

    /// A GIF in the temporary folder for drag and drop. Replaces the previous one.
    static func temporaryGIF(_ file: URL, edits: SavedEdits = SavedEdits(), backdrop: Backdrop? = nil) throws -> URL {
        try? FileManager.default.removeItem(at: temporaryFolder)
        return try saveGIF(file, edits: edits, backdrop: backdrop, to: temporaryFolder)
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}
