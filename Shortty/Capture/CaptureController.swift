import AppKit
import Observation

/// Runs capture actions, including lazy shots, and hands results to the editor.
@Observable
final class CaptureController {
    static let shared = CaptureController()

    /// Seconds left on a lazy shot; the menu bar shows it next to the icon.
    private(set) var countdown: Int?
    private var task: Task<Void, Never>?

    private init() {}

    func perform(_ action: CaptureAction) {
        if action == .reopen { return EditorWindowController.shared.reopen() }
        guard task == nil else { return } // one capture at a time
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
        case .reopen:
            return // handled in perform
        }
        if let image { EditorWindowController.shared.show(image) }
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
        switch await RegionSelector.choose(hint: "Drag over an area   ·   Space for a window   ·   Esc to cancel", allowsWindow: true) {
        case .area(let rect)?:
            Self.lastRegion = rect
            return await ScreenCapture.captureRect(rect)
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
