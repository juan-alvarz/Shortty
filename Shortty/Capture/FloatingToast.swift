import AppKit
import SwiftUI

/// A short notice next to where you worked, for actions that don't open the editor (Capture Text).
/// Click-through, fades out on its own.
enum FloatingToast {
    private static var current: NSPanel?

    @discardableResult
    static func show(_ text: String, near rect: CGRect, for seconds: Double = 2.2) -> NSPanel {
        current?.orderOut(nil)
        let host = NSHostingView(rootView: Toast(text: text).padding(12)) // room for the shadow, and the gap to the area
        let panel = OverlayPanel(contentRect: NSRect(origin: .zero, size: host.fittingSize), level: .statusBar)
        panel.ignoresMouseEvents = true
        panel.contentView = host
        panel.place(beside: rect, gap: 0)
        panel.orderFrontRegardless()
        current = panel

        Task {
            try? await Task.sleep(for: .seconds(seconds))
            panel.animator().alphaValue = 0
            try? await Task.sleep(for: .milliseconds(300))
            panel.orderOut(nil)
            if current === panel { current = nil }
        }
        return panel
    }
}
