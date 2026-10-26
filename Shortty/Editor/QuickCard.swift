import AppKit
import SwiftUI

/// After a capture (Settings → After a capture → Show card): a small card in the corner of the screen with the
/// picture and Copy, Save, Pin and Edit. Drag the picture into any app, or click it to edit. Doesn't take focus from
/// the app you're in, and goes away on its own unless the pointer is over it. The capture stays in the history.
enum QuickCard {
    private static var panel: OverlayPanel?

    @discardableResult
    static func show(_ image: CGImage, file: URL?) -> NSPanel {
        dismiss()
        let host = NSHostingView(rootView: QuickCardView(image: image, file: file))
        let size = host.fittingSize
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let panel = OverlayPanel(contentRect: NSRect(x: visible.maxX - size.width, y: visible.minY, width: size.width, height: size.height),
                                 level: .floating)
        panel.contentView = host
        panel.orderFrontRegardless()
        self.panel = panel
        return panel
    }

    static func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }

    /// Where the card is, so what replaces it (a pin, a toast) shows up in the same place.
    fileprivate static var frame: CGRect { panel?.frame ?? .zero }
}

private struct QuickCardView: View {
    let image: CGImage
    let file: URL?
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(decorative: image, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: 170)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(DragSource(onClick: edit) { image })
                .help("Click to edit, or drag into any app")
            HStack(spacing: 6) {
                PanelButton(title: "Copy") { finish(ImageExport.copiedNotice) { ImageExport.copy(image) } }
                PanelButton(title: "Save") { save() }
                ToolButton(icon: .pin, tooltip: nil) { pin() }
                    .help("Pin to screen")
                Spacer(minLength: 0)
                PanelButton(title: "Edit", prominent: true) { edit() }
                ToolButton(icon: .close, tooltip: nil) { QuickCard.dismiss() }
                    .help("Close")
            }
        }
        .padding(12)
        .frame(width: 300)
        .floatingPanel(cornerRadius: 14)
        .padding(16) // room for the shadow, and the gap to the screen edges
        .onHover { hovering = $0 }
        .task(id: hovering) {
            guard !hovering else { return }
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled { QuickCard.dismiss() }
        }
    }

    private func edit() {
        EditorWindowController.shared.show(image, file: file)
        QuickCard.dismiss()
    }

    private func pin() {
        PinWindow.pin(image, near: QuickCard.frame)
        QuickCard.dismiss()
    }

    private func save() {
        do {
            let url = try ImageExport.save(image, to: AppSettings.shared.saveFolder)
            finish(ImageExport.savedNotice(url)) {}
        } catch {
            finish("Couldn't save: \(error.localizedDescription)") {}
        }
    }

    /// Does `action`, closes the card, and confirms where it was.
    private func finish(_ message: String, _ action: () -> Void) {
        action()
        let frame = QuickCard.frame
        QuickCard.dismiss()
        FloatingToast.show(message, near: frame)
    }
}
