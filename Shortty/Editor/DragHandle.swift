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
                return model.rendered
            })
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .tooltip("Drag into any app", shortcut: nil, visible: hovering)
    }
}

/// Drags out whatever `image` returns at the moment the drag starts; a click without a drag calls `onClick`.
struct DragSource: NSViewRepresentable {
    var onClick: (() -> Void)? = nil
    let image: () -> CGImage
    func makeNSView(context: Context) -> DragSourceView { DragSourceView(image: image, onClick: onClick) }
    func updateNSView(_ view: DragSourceView, context: Context) {}
}

final class DragSourceView: NSView, NSDraggingSource {
    private let image: () -> CGImage
    private let onClick: (() -> Void)?
    private var started = false

    init(image: @escaping () -> CGImage, onClick: (() -> Void)?) {
        self.image = image
        self.onClick = onClick
        super.init(frame: .zero)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override var mouseDownCanMoveWindow: Bool { false }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseDown(with event: NSEvent) { started = false }
    override func mouseUp(with event: NSEvent) { if !started { onClick?() } }

    override func mouseDragged(with event: NSEvent) {
        guard !started else { return }
        started = true
        let image = self.image()
        guard let file = try? ImageExport.temporaryFile(image) else { return }
        let item = NSDraggingItem(pasteboardWriter: file as NSURL)
        let scale = min(160 / CGFloat(image.width), 160 / CGFloat(image.height), 0.5)
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        let point = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height),
                              contents: NSImage(cgImage: image, size: size))
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
}
