import AppKit
import SwiftUI

/// After a capture (Settings → After a capture → Show card): a small card in the corner of the screen with the
/// picture and Copy, Save, Pin and Edit. Drag the picture into any app, or click it to edit. Doesn't take focus from
/// the app you're in, and goes away on its own unless the pointer is over it. The capture stays in the history.
/// A GIF recording plays on it, and Copy, Save and drags hand over the GIF (it can't be pinned).
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
    private var gif: URL? { file?.pathExtension == "gif" ? file : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if let gif {
                    AnimatedImage(url: gif, size: CGSize(width: image.width, height: image.height))
                        .aspectRatio(CGSize(width: image.width, height: image.height), contentMode: .fit)
                } else {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 170)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(DragSource(onClick: { _ in edit() }) {
                (try? gif.map { try ImageExport.temporaryGIF($0) } ?? ImageExport.temporaryFile(image)).map { [$0] } ?? []
            })
            .help("Click to edit, or drag into any app")
            HStack(spacing: 6) {
                PanelButton(title: "Copy") { copy() }
                PanelButton(title: "Save") { save() }
                if gif == nil {
                    ToolButton(icon: .pin, tooltip: nil) { pin() }
                        .help("Pin to screen")
                }
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

    private func copy() {
        do {
            if let gif { try ImageExport.copyGIF(gif) } else { ImageExport.copy(image) }
            finish(ImageExport.copiedNotice) {}
        } catch {
            finish("Couldn't copy: \(error.localizedDescription)") {}
        }
    }

    private func save() {
        do {
            let folder = AppSettings.shared.saveFolder
            let url = try gif.map { try ImageExport.saveGIF($0, to: folder) } ?? ImageExport.save(image, to: folder)
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

/// SwiftUI's `Image` draws only a GIF's first frame; `NSImageView` plays it.
private struct AnimatedImage: NSViewRepresentable {
    let url: URL
    let size: CGSize

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.image = NSImage(contentsOf: url)
        view.animates = true
        view.imageScaling = .scaleProportionallyUpOrDown
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {}

    /// Whatever it's offered: an image view asks for its picture's full size otherwise.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSImageView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: size)
    }
}
