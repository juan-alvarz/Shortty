import AppKit
import SwiftUI

/// A short notice next to where you worked, for actions that don't open the editor (Capture Text).
/// Click-through, fades out on its own.
enum FloatingToast {
    private static var current: NSPanel?

    @discardableResult
    static func show(_ text: String, near rect: CGRect, for seconds: Double = 2.2) -> NSPanel {
        current?.orderOut(nil)
        let host = NSHostingView(rootView: Toast(text: text).padding(12)) // room for the shadow
        let size = host.fittingSize
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = host

        // Centered under the area, or above it near the bottom of the screen.
        let screen = NSScreen.screens.first { $0.frame.intersects(rect) }?.visibleFrame ?? rect
        let x = min(max(rect.midX - size.width / 2, screen.minX), screen.maxX - size.width)
        let below = rect.minY - size.height
        panel.setFrameOrigin(CGPoint(x: x, y: below >= screen.minY ? below : min(rect.maxY, screen.maxY - size.height)))
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
