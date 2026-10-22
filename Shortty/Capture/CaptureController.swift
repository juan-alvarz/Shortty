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
        switch action {
        case .scrolling:
            if let image = await ScrollCapture.run() { EditorWindowController.shared.show(image) }
            return
        case .captureText:
            await TextCapture.run()
            return
        default:
            break
        }

        // Lazy region: pick the area first, then wait, then capture exactly that area.
        var region: CGRect?
        if action == .lazyRegion {
            guard let selected = await RegionSelector.select() else { return }
            region = selected
            Self.lastRegion = selected
        }

        if action.isLazy {
            let overlay = region.map(CountdownOverlay.init(region:))
            defer { overlay?.close() }
            for remaining in stride(from: AppSettings.shared.lazyDelay, to: 0, by: -1) {
                countdown = remaining
                overlay?.show(remaining)
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            countdown = nil
            overlay?.close()
            try? await Task.sleep(for: .milliseconds(150)) // let the overlay and menu bar digits leave the screen
            if Task.isCancelled { return }
        }

        let image: CGImage?
        switch action {
        case .lazyRegion:
            guard let region else { return }
            image = await ScreenCapture.captureRect(region)
        case .region:
            image = await captureChosenArea()
        case .repeatRegion:
            if let last = Self.lastRegion {
                image = await ScreenCapture.captureRect(last)
            } else {
                image = await captureChosenArea() // nothing to repeat yet
            }
        case .screen, .lazyScreen:
            image = await ScreenCapture.captureScreen()
        case .window:
            image = await ScreenCapture.captureWindow()
        case .activeWindow:
            image = await ScreenCapture.captureActiveWindow()
        case .reopen, .scrolling, .captureText:
            return
        }
        if let image { EditorWindowController.shared.show(image) }
    }

    /// Capture Region uses Shortty's own selector (so Repeat Last Region knows the area); Space switches to a window.
    private func captureChosenArea() async -> CGImage? {
        guard ScreenCapture.hasPermission() else { return nil }
        switch await RegionSelector.choose(hint: "Drag over an area   ·   Space for a window   ·   Esc to cancel", allowsWindow: true) {
        case .area(let rect)?:
            Self.lastRegion = rect
            try? await Task.sleep(for: .milliseconds(80)) // let the selection overlay leave the screen first
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
