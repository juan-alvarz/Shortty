import SwiftUI

@main
struct ShorttyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            CaptureMenu()
        } label: {
            MenuBarLabel()
        }
        Settings { SettingsView() }
    }
}

private struct MenuBarLabel: View {
    private let capture = CaptureController.shared

    var body: some View {
        Image(nsImage: Icon.menuBar(countdown: capture.countdown))
    }
}

private struct CaptureMenu: View {
    @Environment(\.openSettings) private var openSettings
    private let settings = AppSettings.shared
    private let capture = CaptureController.shared

    var body: some View {
        if capture.countdown != nil {
            Button("Cancel Lazy Shot") { capture.cancel() }
            Divider()
        }
        item(.region)
        item(.repeatRegion)
        item(.screen)
        item(.window)
        item(.activeWindow)
        item(.scrolling)
        Divider()
        item(.captureText)
        Divider()
        item(.lazyRegion)
        item(.lazyScreen)
        Divider()
        item(.reopen)
            .disabled(!EditorWindowController.shared.canReopen)
        Divider()
        // shortcut: points at the GitHub repo until the landing page is live, then swap the URL.
        Link("Shortty Website", destination: URL(string: "https://github.com/juan-alvarz/Shortty")!)
        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        Button("Quit Shortty") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func item(_ action: CaptureAction) -> some View {
        var title = action.title
        if action.isLazy { title += " (\(settings.lazyDelay)s)" }
        if let hotkey = settings.hotkeys[action], !hotkey.isNone { title += "    \(hotkey.display)" }
        return Button(title) { capture.perform(action) }
    }
}
