import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // menu bar only, also when run outside a bundle
        AppPresence.start()
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

/// Shortty lives in the menu bar, but while one of its windows is open (the editor, Settings) it acts like a regular app:
/// in the Dock and ⌘Tab, with its own menu bar (⌘, opens Settings), and window managers can move the window. Closing the
/// last one hands focus back to the app you were in and leaves only the menu bar icon; Shortty keeps running.
enum AppPresence {
    /// The last other app in front, which gets focus back when Shortty's last window closes.
    private static var previous: NSRunningApplication?

    static func start() {
        previous = NSWorkspace.shared.frontmostApplication
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { if let app, app != .current { previous = app } }
        }
        let center = NotificationCenter.default
        // Window notifications arrive on the main queue, so handing the window to the main actor is safe.
        center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
            nonisolated(unsafe) let object = note.object
            MainActor.assumeIsolated { if let window = object as? NSWindow { windowBecameKey(window) } }
        }
        center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            nonisolated(unsafe) let object = note.object
            MainActor.assumeIsolated { if let window = object as? NSWindow { windowWillClose(window) } }
        }
    }

    /// A non-activating panel only takes keyboard focus while Shortty is a background (menu bar) process. Once a window
    /// made it a regular app and another app went active, WindowServer refuses ("a foreground app can't steal keyboard
    /// focus") and keys go to that app. Stepping back first restores the path; `windowBecameKey` makes it regular again.
    @discardableResult
    static func prepareForPanelFocus() -> Bool {
        guard NSApp.activationPolicy() == .regular, !NSApp.isActive else { return false }
        NSApp.setActivationPolicy(.accessory)
        return true
    }

    /// Titled windows (the editor, Settings), not the borderless overlays, toasts, cards and pins.
    static func isAppWindow(_ window: NSWindow) -> Bool { window.isVisible && window.styleMask.contains(.titled) }

    /// Activates only once the window already has keyboard focus: asking before that can leave Shortty "foreground"
    /// without focus (see `EditorWindowController.present`). A click or shortcut just happened, so macOS allows it.
    private static func windowBecameKey(_ window: NSWindow) {
        guard isAppWindow(window) else { return }
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
        if !NSApp.isActive { NSApp.activate() }
    }

    private static func windowWillClose(_ window: NSWindow) {
        guard isAppWindow(window), !NSApp.windows.contains(where: { $0 !== window && isAppWindow($0) }) else { return }
        NSApp.setActivationPolicy(.accessory)
        if NSApp.isActive, let previous, !previous.isTerminated { previous.activate() }
    }
}
