import AppKit
import ImageIO
import os

enum ScreenCapture {
    static let log = Logger(subsystem: "com.socialgoodsoftware.Shortty", category: "capture")

    /// System interactive capture (crosshair; Space toggles window mode; Esc cancels → nil).
    /// `keepAsLast: false` for pictures inserted into the editor, so "Reopen Last Capture" still means the main one.
    static func captureRegion(keepAsLast: Bool = true) async -> CGImage? { await capture(["-i"], keepAsLast: keepAsLast) }

    /// The whole display under the mouse pointer.
    static func captureScreen() async -> CGImage? {
        let mouse = NSEvent.mouseLocation
        let display = (NSScreen.screens.firstIndex { NSMouseInRect(mouse, $0.frame, false) } ?? 0) + 1
        return await capture(["-D", "\(display)"])
    }

    /// One quiet frame of a fixed area for scrolling capture: no sound, not kept as the last capture.
    /// TIFF because it's the fastest format for `screencapture` to write and us to read (~120 ms a frame).
    static func frame(of rect: CGRect) async -> CGImage? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("shortty-frame-\(UUID().uuidString).tiff")
        defer { try? FileManager.default.removeItem(at: url) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-R", rectArgument(rect), "-t", "tiff", url.path]
        await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in continuation.resume() }
            do { try process.run() } catch { continuation.resume() }
        }
        return CGImage.load(from: url)
    }

    static func hasPermission() -> Bool { ensurePermission() }

    /// Click a window to capture it (no shadow).
    static func captureWindow() async -> CGImage? { await capture(["-i", "-W", "-o"]) }

    /// The frontmost app's front window, no clicking (no shadow).
    static func captureActiveWindow() async -> CGImage? {
        guard let app = NSWorkspace.shared.frontmostApplication, let id = frontWindowID(of: app.processIdentifier) else {
            NSSound.beep()
            return nil
        }
        return await capture(["-l", "\(id)", "-o"])
    }

    /// The app's frontmost normal window (on screen, layer 0, not a sliver). The list comes front to back.
    static func frontWindowID(of pid: pid_t) -> CGWindowID? {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let window = windows.first { info in
            guard info[kCGWindowOwnerPID as String] as? pid_t == pid, info[kCGWindowLayer as String] as? Int == 0,
                  let bounds = info[kCGWindowBounds as String] as! CFDictionary?, let rect = CGRect(dictionaryRepresentation: bounds)
            else { return false }
            return rect.width > 40 && rect.height > 40
        }
        return window?[kCGWindowNumber as String] as? CGWindowID
    }

    /// A fixed rectangle in global AppKit coordinates (bottom-left origin).
    static func captureRect(_ rect: CGRect) async -> CGImage? {
        await capture(["-R", rectArgument(rect)])
    }

    /// `screencapture -R` takes x,y,w,h in points with the origin at the top-left of the primary display.
    static func rectArgument(_ rect: CGRect, primaryHeight: CGFloat = NSScreen.screens.first?.frame.height ?? 0) -> String {
        let rect = rect.integral
        return "\(Int(rect.minX)),\(Int(primaryHeight - rect.maxY)),\(Int(rect.width)),\(Int(rect.height))"
    }

    private static func capture(_ options: [String], keepAsLast: Bool = true) async -> CGImage? {
        guard ensurePermission() else {
            log.notice("capture skipped: Screen Recording not granted")
            return nil
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("shortty-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = (AppSettings.shared.captureSound ? [] : ["-x"]) + options + ["-t", "png", url.path]
        let stderr = Pipe()
        process.standardError = stderr

        await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in continuation.resume() }
            do { try process.run() } catch { continuation.resume() }
        }
        let errorText = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let image = CGImage.load(from: url)
        let summary = image.map { "\($0.width)x\($0.height) blank=\($0.isBlank)" } ?? "no file"
        log.notice("screencapture \(options, privacy: .public) exit=\(process.terminationStatus) image=\(summary, privacy: .public) stderr=\(errorText, privacy: .public)")

        guard let image else { return nil } // cancelled
        guard !image.isBlank else {
            showBlankCaptureAlert()
            return nil
        }
        if keepAsLast { LastCapture.keep(url) }
        return image
    }

    /// Without Screen Recording, captures come back blank. Ask once via the system prompt;
    /// after that macOS never re-prompts, so send the user straight to the settings pane.
    private static func ensurePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        let askedKey = "didRequestScreenCapture"
        if !UserDefaults.standard.bool(forKey: askedKey) {
            UserDefaults.standard.set(true, forKey: askedKey)
            return CGRequestScreenCaptureAccess()
        }
        openPrivacyPane()
        return false
    }

    private static func showBlankCaptureAlert() {
        let alert = NSAlert()
        alert.messageText = "Shortty couldn't capture the screen"
        alert.informativeText = "macOS returned an empty image. Make sure Shortty is enabled under System Settings → Privacy & Security → Screen & System Audio Recording, then try again."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { openPrivacyPane() }
    }

    private static func openPrivacyPane() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// The most recent capture, kept on disk so "Reopen Last Capture" also works after a relaunch.
enum LastCapture {
    static let url: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Shortty", isDirectory: true)
        .appendingPathComponent("last-capture.png")

    static var exists: Bool { FileManager.default.fileExists(atPath: url.path) }
    static func load() -> CGImage? { CGImage.load(from: url) }

    /// Writes a capture that didn't come from a file (scrolling capture).
    static func store(_ image: CGImage) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? ImageExport.writePNG(image, to: url)
    }

    /// Moves the fresh capture file into place (no re-encoding).
    static func keep(_ file: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.moveItem(at: file, to: url)
    }
}

extension CGImage {
    /// Pixel-exact load (ignores DPI metadata, so Retina captures keep full resolution).
    /// Reads the whole file into memory: a URL-backed image source decodes lazily, and the capture's
    /// temp file is deleted before the editor first draws.
    static func load(from url: URL) -> CGImage? {
        guard let data = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// True when every pixel is fully transparent (what screencapture returns when it has no screen access).
    var isBlank: Bool {
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(self, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn && stride(from: 3, to: pixels.count, by: 4).allSatisfy { pixels[$0] == 0 }
    }
}
