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
        if action == .scrolling {
            if let image = await ScrollCapture.run() { EditorWindowController.shared.show(image) }
            return
        }
        // Lazy region: pick the area first, then wait, then capture exactly that area.
        var region: CGRect?
        if action == .lazyRegion {
            guard let selected = await RegionSelector.select() else { return }
            region = selected
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
        if let region {
            image = await ScreenCapture.captureRect(region)
        } else if action.isScreen {
            image = await ScreenCapture.captureScreen()
        } else {
            image = await ScreenCapture.captureRegion()
        }
        if let image { EditorWindowController.shared.show(image) }
    }
}
