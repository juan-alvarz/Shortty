import AppKit
import Observation
import SwiftUI

/// Scrolling capture: pick an area, scroll the page, press Done. Frames are captured and stitched as you scroll.
enum ScrollCapture {
    static func run() async -> CGImage? {
        guard ScreenCapture.hasPermission() else { return nil }
        guard let region = await RegionSelector.select(hint: "Drag over the area you'll scroll   ·   Esc to cancel") else { return nil }
        try? await Task.sleep(for: .milliseconds(80)) // the selection overlay must be gone before the first frame
        let image = await ScrollCaptureSession(region: region).run()
        if let image { LastCapture.store(image) }
        return image
    }
}

@Observable
final class ScrollCaptureSession {
    private enum State { case running, done, cancelled }
    static let maxHeight = 30_000

    let region: CGRect
    private(set) var height = 0
    private(set) var status = "Scroll down slowly"
    private var state = State.running
    @ObservationIgnored private var stitcher = ScrollStitcher()

    init(region: CGRect) { self.region = region }

    func finish() { if state == .running { state = .done } }
    func cancel() { state = .cancelled }

    /// Captures until Done/Cancel (or the height limit). The outline and panel stay outside the area,
    /// so they never end up in the frames.
    func run() async -> CGImage? {
        let outline = CountdownOverlay(region: region)
        let panel = ScrollCapturePanel(session: self)
        defer {
            outline.close()
            panel.close()
        }
        while state == .running {
            if let frame = await ScreenCapture.frame(of: region) {
                switch stitcher.add(frame) {
                case .started, .appended:
                    height = stitcher.height
                    status = "Scroll down slowly"
                case .lost:
                    status = "Scroll a little slower"
                case .unchanged:
                    break
                }
                if stitcher.height >= Self.maxHeight { state = .done }
            }
            try? await Task.sleep(for: .milliseconds(40))
        }
        return state == .done ? stitcher.image() : nil
    }
}

/// Small floating panel next to the area: progress, Done (Return) and Cancel (Esc).
private final class ScrollCapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }

    init(session: ScrollCaptureSession) {
        let content = NSHostingView(rootView: ScrollCaptureHUD(session: session))
        let size = content.fittingSize
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = content
        setFrameOrigin(Self.origin(for: size, beside: session.region))
        orderFrontRegardless()
        makeKey() // Return / Esc work; scrolling still goes to the page under the pointer
    }

    /// Below the area, else above it, else inside its bottom edge (the only case where it can show in frames).
    private static func origin(for size: CGSize, beside region: CGRect) -> CGPoint {
        let screen = NSScreen.screens.first { $0.frame.intersects(region) }?.visibleFrame ?? region
        let x = min(max(region.midX - size.width / 2, screen.minX + 8), screen.maxX - size.width - 8)
        if region.minY - size.height - 12 >= screen.minY { return CGPoint(x: x, y: region.minY - size.height - 12) }
        if region.maxY + size.height + 12 <= screen.maxY { return CGPoint(x: x, y: region.maxY + 12) }
        return CGPoint(x: x, y: region.minY + 12)
    }
}

private struct ScrollCaptureHUD: View {
    let session: ScrollCaptureSession

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.status).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                Text("\(session.height) px").font(.system(size: 11).monospacedDigit()).foregroundStyle(.white.opacity(0.55))
            }
            .frame(minWidth: 150, alignment: .leading)
            Button("Cancel") { session.cancel() }
                .keyboardShortcut(.cancelAction)
            Button("Done") { session.finish() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.1).opacity(0.95)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.12)))
        .environment(\.colorScheme, .dark)
    }
}
