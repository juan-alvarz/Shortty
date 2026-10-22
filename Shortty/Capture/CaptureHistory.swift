import AppKit
import ImageIO
import Observation

/// Recent captures as PNG files in Caches, newest first, at most `limit`. The newest is what
/// "Reopen Last Capture" opens after a relaunch; the editor's history strip shows them all.
@Observable
final class CaptureHistory {
    static let shared = CaptureHistory(folder: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Shortty", isDirectory: true)
        .appendingPathComponent("History", isDirectory: true))
    static let limit = 20

    let folder: URL
    /// Newest first. File names are timestamps, so sorting by name sorts by time.
    private(set) var items: [URL]

    /// Internal for the self-check, which uses a temporary folder.
    init(folder: URL) {
        self.folder = folder
        // Built from the folder (not the listing's own URLs, which may spell the path differently, e.g. /private/var) so they compare equal.
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        items = names.filter { $0.hasSuffix(".png") }.sorted(by: >).map { folder.appendingPathComponent($0) }
    }

    var latest: URL? { items.first }

    /// Moves a fresh capture file in (no re-encoding).
    func keep(_ file: URL) {
        let url = nextURL()
        guard (try? FileManager.default.moveItem(at: file, to: url)) != nil else { return }
        add(url)
    }

    /// Writes a capture that didn't come from a file (scrolling capture).
    func store(_ image: CGImage) {
        let url = nextURL()
        guard (try? ImageExport.writePNG(image, to: url)) != nil else { return }
        add(url)
    }

    func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        items.removeAll { $0 == url }
    }

    func removeAll() {
        items.forEach { try? FileManager.default.removeItem(at: $0) }
        items = []
    }

    /// When the file was captured (from its name), for the strip's labels.
    static func date(of url: URL) -> Date? { nameFormatter.date(from: String(url.deletingPathExtension().lastPathComponent.prefix(19))) }

    /// A small preview, decoded off the main thread by the caller.
    nonisolated static func thumbnail(of url: URL, maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                                        kCGImageSourceCreateThumbnailWithTransform: true]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private func add(_ url: URL) {
        items.insert(url, at: 0)
        while items.count > Self.limit { remove(items[items.count - 1]) }
    }

    private static let nameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter
    }()

    /// `<timestamp>.png`, always after the newest one so names sort in capture order (even two in the same millisecond).
    private func nextURL() -> URL {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let newest = items.first.flatMap(Self.date(of:)) ?? .distantPast
        let date = max(Date.now, newest.addingTimeInterval(0.0015)) // the name keeps whole milliseconds
        return folder.appendingPathComponent("\(Self.nameFormatter.string(from: date)).png")
    }
}
