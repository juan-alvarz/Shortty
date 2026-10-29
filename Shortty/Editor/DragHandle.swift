import AppKit
import SwiftUI

/// Toolbar handle: drag the annotated image straight into any app or website upload box.
/// It hands over a temporary PNG file (what upload boxes expect); nothing is saved to Downloads.
struct DragHandle: View {
    let model: EditorModel
    @State private var hovering = false

    var body: some View {
        Icon(kind: .drag)
            .foregroundStyle(hovering ? Color.white : Theme.chromeText)
            .frame(width: 28, height: 28)
            .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(hovering ? 0.08 : 0)))
            .overlay(DragSource {
                model.endEditing()
                return (try? ImageExport.temporaryFile(model.rendered)).map { [$0] } ?? []
            })
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .tooltip("Drag into any app", shortcut: nil, visible: hovering)
    }
}

/// Drags out the image files `files` returns at the moment the drag starts; a click without a drag calls `onClick`
/// with the modifier keys held. `onHover` comes from here because SwiftUI's hover misses enters and exits over this view.
struct DragSource: NSViewRepresentable {
    var onClick: ((NSEvent.ModifierFlags) -> Void)? = nil
    var onHover: ((Bool) -> Void)? = nil
    let files: () -> [URL]
    func makeNSView(context: Context) -> DragSourceView { DragSourceView(files: files, onClick: onClick) }
    func updateNSView(_ view: DragSourceView, context: Context) { view.files = files; view.onClick = onClick; view.onHover = onHover }
}

final class DragSourceView: NSView, NSDraggingSource {
    var files: () -> [URL]
    var onClick: ((NSEvent.ModifierFlags) -> Void)?
    var onHover: ((Bool) -> Void)?
    /// Where the button went down on this view; nil when the press began elsewhere.
    private var downAt: CGPoint?
    private var started = false

    init(files: @escaping () -> [URL], onClick: ((NSEvent.ModifierFlags) -> Void)?) {
        self.files = files
        self.onClick = onClick
        super.init(frame: .zero)
        // Geometric, so the pointer over a button on top of this view still counts as inside.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override var mouseDownCanMoveWindow: Bool { false }
    /// The first click on an inactive editor works too, like the SwiftUI buttons around it.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func mouseDown(with event: NSEvent) { started = false; downAt = event.locationInWindow }
    override func mouseUp(with event: NSEvent) {
        if downAt != nil, !started { onClick?(event.modifierFlags) }
        downAt = nil
    }

    override func mouseDragged(with event: NSEvent) {
        // A hand that shakes a little mid-click is still a click.
        guard !started, let downAt, hypot(event.locationInWindow.x - downAt.x, event.locationInWindow.y - downAt.y) >= 3 else { return }
        started = true
        let point = convert(event.locationInWindow, from: nil)
        // Several files fan out a little, so the drag shows how many there are.
        let items = files().enumerated().compactMap { index, file -> NSDraggingItem? in
            guard let preview = CaptureHistory.thumbnail(of: file, maxPixels: 320) else { return nil }
            let scale = min(160 / CGFloat(preview.width), 160 / CGFloat(preview.height), 0.5)
            let size = CGSize(width: CGFloat(preview.width) * scale, height: CGFloat(preview.height) * scale)
            let offset = CGFloat(min(index, 4)) * 8
            let item = NSDraggingItem(pasteboardWriter: file as NSURL)
            item.setDraggingFrame(CGRect(x: point.x - size.width / 2 + offset, y: point.y - size.height / 2 - offset, width: size.width, height: size.height),
                                  contents: NSImage(cgImage: preview, size: size))
            return item
        }
        guard !items.isEmpty else { return }
        beginDraggingSession(with: items, event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
}
