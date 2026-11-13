import AppKit
import Observation

/// Runs capture actions, including lazy shots, and hands results to the editor or the quick card.
@Observable
final class CaptureController {
    static let shared = CaptureController()

    /// Seconds left on a lazy shot; the menu bar shows it next to the icon.
    private(set) var countdown: Int?
    /// A GIF is being recorded: `countdown` is the seconds left, and `cancel` stops it and keeps what was recorded.
    private(set) var isRecording = false
    private var task: Task<Void, Never>?

    private init() {}

    func perform(_ action: CaptureAction) {
        if action == .reopen { return EditorWindowController.shared.reopen() }
        guard task == nil else { // one capture at a time; a GIF shortcut again stops the recording
            if isRecording, action.isGIF { cancel() }
            return
        }
        task = Task {
            await run(action)
            countdown = nil
            task = nil
        }
    }

    func cancel() { task?.cancel() }

    private func run(_ action: CaptureAction) async {
        let image: CGImage?
        switch action {
        case .region:
            image = await captureChosenArea()
        case .repeatRegion: // nothing to repeat yet: pick an area
            image = if let last = Self.lastRegion { await ScreenCapture.captureRect(last) } else { await captureChosenArea() }
        case .screen:
            image = await ScreenCapture.captureScreen()
        case .lazyScreen:
            guard await countDown() else { return }
            image = await ScreenCapture.captureScreen()
        case .lazyRegion: // pick the area first, then wait, then capture exactly that area
            guard let region = await RegionSelector.select() else { return }
            Self.lastRegion = region
            guard await countDown(outlining: region) else { return }
            image = await ScreenCapture.captureRect(region)
        case .window:
            image = await ScreenCapture.captureWindow()
        case .activeWindow:
            image = await ScreenCapture.captureActiveWindow()
        case .scrolling:
            image = await ScrollCaptureSession.capture()
        case .captureText:
            return await TextCapture.run()
        case .gifRegion:
            guard let region = await RegionSelector.select(hint: "Drag to select the GIF area   ·   Esc to cancel") else { return }
            Self.lastRegion = region
            guard await countDown(outlining: region) else { return }
            return await recordGIF(of: region)
        case .gifScreen:
            guard await countDown() else { return }
            let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.screens[0]
            return await recordGIF(of: screen.frame)
        case .gifWindow: // where the window is when the countdown ends; the recording doesn't follow it
            guard await countDown(), let frame = ScreenCapture.activeWindow()?.frame else { return }
            let screen = NSScreen.screens.first { $0.frame.intersects(frame) }?.frame ?? frame
            return await recordGIF(of: frame.intersection(screen))
        case .reopen:
            return // handled in perform
        }
        if let image { Self.deliver(image) }
    }

    /// A finished capture (already in the history, as `file`): copied and saved right away if those are on, then shown in
    /// the editor or the quick card. With nothing to show, a notice says what happened. `image` is the first frame of a
    /// GIF recording, which is copied and saved as a GIF. The self-check passes its own file and pasteboard.
    static func deliver(_ image: CGImage, file: URL? = CaptureHistory.shared.latest, pasteboard: NSPasteboard = .general) {
        let settings = AppSettings.shared
        let gif = file?.pathExtension == "gif" ? file : nil
        var done: [String] = []
        var saveFailed = false
        do {
            if settings.copyAfterCapture {
                if let gif { try ImageExport.copyGIF(gif, to: pasteboard) } else { ImageExport.copy(image, to: pasteboard) }
                done.append(ImageExport.copiedNotice)
            }
            if settings.saveAfterCapture {
                let folder = settings.saveFolder
                done.append(ImageExport.savedNotice(try gif.map { try ImageExport.saveGIF($0, to: folder) } ?? ImageExport.save(image, to: folder)))
            }
        } catch {
            done.append("Couldn't save: \(error.localizedDescription)")
            saveFailed = true
        }
        switch settings.afterCapture {
        case .editor: EditorWindowController.shared.show(image, file: file)
        case .card: QuickCard.show(image, file: file)
        case .nothing: break
        }
        if settings.afterCapture == .nothing || saveFailed { // next to the pointer, where the capture just ended
            FloatingToast.show(done.isEmpty ? "Captured" : done.joined(separator: " · "),
                               near: CGRect(origin: NSEvent.mouseLocation, size: CGSize(width: 1, height: 1)))
        }
    }

    /// Records `rect` for the GIF length, the seconds left next to the menu bar icon and a plain outline around it
    /// (outside the recording), then writes the GIF. Cancelling stops early and keeps what was recorded.
    private func recordGIF(of rect: CGRect) async {
        guard let recording = ScreenCapture.Recording(of: rect) else { return }
        let overlay = CountdownOverlay(region: rect)
        isRecording = true
        for remaining in stride(from: AppSettings.shared.gifDuration, to: 0, by: -1) {
            countdown = remaining
            do { try await Task.sleep(for: .seconds(1)) } catch { break }
        }
        countdown = nil
        isRecording = false
        overlay.close()
        guard let movie = await recording.finish() else {
            FloatingToast.show("Couldn't record the screen", near: rect)
            return
        }
        defer { try? FileManager.default.removeItem(at: movie) }
        FloatingToast.show("Making the GIF…", near: rect)
        do {
            let gif = URL.temporaryDirectory.appending(path: "shortty-\(UUID().uuidString).gif")
            try await Task.detached(priority: .userInitiated) { try await GIF.write(movie: movie, of: rect.size, to: gif) }.value
            CaptureHistory.shared.keep(gif) // a capture like any other: in the history, then the editor, the card or a notice
            guard let file = CaptureHistory.shared.latest, file.pathExtension == "gif", let image = CGImage.load(from: file)
            else { throw CocoaError(.fileWriteUnknown) }
            Self.deliver(image)
        } catch {
            FloatingToast.show("Couldn't make the GIF: \(error.localizedDescription)", near: rect)
        }
    }

    /// Counts down the lazy delay next to the menu bar icon (and around `region`). False when cancelled.
    private func countDown(outlining region: CGRect? = nil) async -> Bool {
        let overlay = region.map(CountdownOverlay.init(region:))
        defer { overlay?.close() }
        for remaining in stride(from: AppSettings.shared.lazyDelay, to: 0, by: -1) {
            countdown = remaining
            overlay?.show(remaining)
            do { try await Task.sleep(for: .seconds(1)) } catch { return false }
        }
        countdown = nil
        overlay?.close()
        do { try await Task.sleep(for: .milliseconds(150)) } catch { return false } // let the overlay and digits leave the screen
        return true
    }

    /// Capture Region uses Shortty's own selector (so Repeat Last Region knows the area); Space switches to a window.
    private func captureChosenArea() async -> CGImage? {
        let pointer = ScreenCapture.Pointer.now()
        switch await RegionSelector.choose(hint: "Drag over an area   ·   Space for a window   ·   Esc to cancel", allowsWindow: true) {
        case .area(let rect)?:
            Self.lastRegion = rect
            return await ScreenCapture.captureRect(rect, pointer: pointer)
        case .window?:
            return await ScreenCapture.captureWindow()
        case nil:
            return nil
        }
    }

    /// The last area picked (screen coordinates), for Repeat Last Region. Survives relaunches.
    static var lastRegion: CGRect? {
        get {
            guard let text = UserDefaults.standard.string(forKey: "lastRegion") else { return nil }
            let rect = NSRectFromString(text)
            return rect.width > 0 && rect.height > 0 ? rect : nil
        }
        set { UserDefaults.standard.set(newValue.map { NSStringFromRect($0) }, forKey: "lastRegion") }
    }
}
