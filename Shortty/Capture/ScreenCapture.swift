import AppKit
import ImageIO
import os

enum ScreenCapture {
    static let log = Logger(subsystem: "com.shortty.Shortty", category: "capture")

    /// System interactive capture (crosshair; Space toggles window mode; Esc cancels → nil), for pictures inserted
    /// into the editor: not kept as the last capture, so "Reopen Last Capture" still means the main one.
    static func captureRegion() async -> CGImage? { await capture(["-i"], keepInHistory: false) }

    /// The whole display under the mouse pointer.
    static func captureScreen() async -> CGImage? {
        let mouse = NSEvent.mouseLocation
        let index = NSScreen.screens.firstIndex { NSMouseInRect(mouse, $0.frame, false) } ?? 0
        return await capture(["-D", "\(index + 1)"], over: NSScreen.screens[index].frame)
    }

    /// One quiet frame of a fixed area (scrolling capture, Capture Text): no sound, not kept as the last capture.
    /// TIFF because it's the fastest format for `screencapture` to write and us to read (~120 ms a frame).
    static func frame(of rect: CGRect) async -> CGImage? {
        let (url, _) = await screencapture(["-x", "-R", rectArgument(rect)], type: "tiff")
        defer { try? FileManager.default.removeItem(at: url) }
        return CGImage.load(from: url)
    }

    /// Click a window to capture it (no shadow).
    static func captureWindow() async -> CGImage? { await capture(["-i", "-W", "-o"]) }

    /// The frontmost app's front window, no clicking (no shadow).
    static func captureActiveWindow() async -> CGImage? {
        guard let app = NSWorkspace.shared.frontmostApplication, let id = frontWindowID(of: app.processIdentifier) else {
            NSSound.beep()
            return nil
        }
        let info = (CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]])?.first
        let bounds = (info?[kCGWindowBounds as String] as! CFDictionary?).flatMap { CGRect(dictionaryRepresentation: $0) }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0 // window bounds have a top-left origin
        return await capture(["-l", "\(id)", "-o"], over: bounds.map { CGRect(x: $0.minX, y: primaryHeight - $0.maxY, width: $0.width, height: $0.height) })
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

    /// A fixed rectangle in global AppKit coordinates (bottom-left origin). `pointer` defaults to the pointer as it is now.
    static func captureRect(_ rect: CGRect, pointer: Pointer? = nil) async -> CGImage? {
        await capture(["-R", rectArgument(rect)], over: rect.integral, pointer: pointer)
    }

    /// The pointer as it is now, drawn by Shortty: `screencapture -C` draws nothing with `-R` (macOS 15.7), and an
    /// area picked by dragging takes it from before the selector opened. Nil when the setting is off.
    struct Pointer {
        let image: NSImage, hotSpot: CGPoint, location: CGPoint
        static func now() -> Pointer? {
            guard AppSettings.shared.showsCursor else { return nil }
            let cursor = NSCursor.currentSystem ?? .arrow
            return Pointer(image: cursor.image, hotSpot: cursor.hotSpot, location: NSEvent.mouseLocation)
        }
    }

    /// `screencapture -R` takes x,y,w,h in points with the origin at the top-left of the primary display.
    static func rectArgument(_ rect: CGRect, primaryHeight: CGFloat = NSScreen.screens.first?.frame.height ?? 0) -> String {
        let rect = rect.integral
        return "\(Int(rect.minX)),\(Int(primaryHeight - rect.maxY)),\(Int(rect.width)),\(Int(rect.height))"
    }

    /// Captures `options` with the user's sound setting. With `rect` (the area captured, global AppKit coordinates) the
    /// pointer is drawn in when the setting is on. Quiet frames (`frame(of:)`) skip both: a pointer would break scroll
    /// stitching and text recognition.
    private static func capture(_ options: [String], keepInHistory: Bool = true, over rect: CGRect? = nil, pointer: Pointer? = nil) async -> CGImage? {
        let pointer = rect == nil ? nil : pointer ?? Pointer.now()
        guard hasPermission() else {
            log.notice("capture skipped: Screen Recording not granted")
            return nil
        }
        let (url, result) = await screencapture((AppSettings.shared.captureSound ? [] : ["-x"]) + options, type: "png")
        defer { try? FileManager.default.removeItem(at: url) }
        let image = CGImage.load(from: url)
        let summary = image.map { "\($0.width)x\($0.height) blank=\($0.isBlank)" } ?? "no file"
        log.notice("screencapture \(options, privacy: .public) \(result, privacy: .public) image=\(summary, privacy: .public)")

        guard var image else { return nil } // cancelled
        guard !image.isBlank else {
            showBlankCaptureAlert()
            return nil
        }
        if let pointer, let rect {
            image = image.drawing(pointer, over: rect)
            try? ImageExport.writePNG(image, to: url) // the history keeps what the editor shows
        }
        if keepInHistory { CaptureHistory.shared.keep(url) }
        return image
    }

    /// Runs `screencapture` into a new temp file, which the caller deletes. Also returns "exit=… stderr=…" for the log.
    private static func screencapture(_ arguments: [String], type: String) async -> (URL, String) {
        let url = URL.temporaryDirectory.appending(path: "shortty-\(UUID().uuidString).\(type)")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = arguments + ["-t", type, url.path]
        let stderr = Pipe()
        process.standardError = stderr
        await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in continuation.resume() }
            do { try process.run() } catch { continuation.resume() }
        }
        let errorText = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return (url, "exit=\(process.terminationStatus) stderr=\(errorText)")
    }

    /// Without Screen Recording, captures come back blank. Ask once via the system prompt;
    /// after that macOS never re-prompts, so send the user straight to the settings pane.
    static func hasPermission() -> Bool {
        let askedKey = "didRequestScreenCapture"
        // A grant that later stops matching (new signing cert, tccutil reset) must be asked for again, not dead-end in Settings.
        if CGPreflightScreenCaptureAccess() {
            UserDefaults.standard.removeObject(forKey: askedKey)
            return true
        }
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

extension CGImage {
    /// Pixel-exact load (ignores DPI metadata, so Retina captures keep full resolution).
    /// Reads the whole file into memory: a URL-backed image source decodes lazily, and the capture's
    /// temp file is deleted before the editor first draws.
    static func load(from url: URL) -> CGImage? {
        guard let data = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// `pointer` drawn where it was, this image being `rect` (global AppKit coordinates) of the screen.
    func drawing(_ pointer: ScreenCapture.Pointer, over rect: CGRect) -> CGImage {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return self }
        context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
        let scale = CGFloat(width) / rect.width
        context.scaleBy(x: scale, y: scale)
        let size = pointer.image.size // the hot spot is measured from the cursor image's top-left
        let frame = CGRect(x: pointer.location.x - rect.minX - pointer.hotSpot.x,
                           y: pointer.location.y - rect.minY - size.height + pointer.hotSpot.y, width: size.width, height: size.height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        pointer.image.draw(in: frame)
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage() ?? self
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
