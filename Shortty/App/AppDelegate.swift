import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // menu bar only, also when run outside a bundle
        HotkeyManager.shared.onPress = { CaptureController.shared.perform($0) }
        HotkeyManager.shared.register(AppSettings.shared.hotkeys)
        ScreenCapture.log.notice("launched from \(Bundle.main.bundlePath, privacy: .public); screen recording granted=\(CGPreflightScreenCaptureAccess())")
    }

    /// Finder "Open With" / `open -a Shortty image.png`: edit an existing image.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let image = CGImage.load(from: url) else { continue }
            EditorWindowController.shared.show(image)
        }
    }
}
