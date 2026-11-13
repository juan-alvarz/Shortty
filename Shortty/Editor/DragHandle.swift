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
            .overlay(DragSource(isEditorPicture: true) {
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
/// The canvas refuses drops from the `isEditorPicture` source: that's the editor's own picture.
struct DragSource: NSViewRepresentable {
    var isEditorPicture = false
    var onClick: ((NSEvent.ModifierFlags) -> Void)? = nil
    var onHover: ((Bool) -> Void)? = nil
    let files: () -> [URL]
    func makeNSView(context: Context) -> DragSourceView { DragSourceView(files: files, onClick: onClick, isEditorPicture: isEditorPicture) }
    func updateNSView(_ view: DragSourceView, context: Context) { view.files = files; view.onClick = onClick; view.onHover = onHover }
}

final class DragSourceView: NSView, NSDraggingSource {
    var files: () -> [URL]
    var onClick: ((NSEvent.ModifierFlags) -> Void)?
    var onHover: ((Bool) -> Void)?
    let isEditorPicture: Bool
    /// Where the button went down on this view; nil when the press began elsewhere.
    private var downAt: CGPoint?
    private var started = false
    private(set) var hovering = false

    init(files: @escaping () -> [URL], onClick: ((NSEvent.ModifierFlags) -> Void)?, isEditorPicture: Bool = false) {
        self.files = files
        self.onClick = onClick
        self.isEditorPicture = isEditorPicture
        super.init(frame: .zero)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override var mouseDownCanMoveWindow: Bool { false }
    /// The first click on an inactive editor works too, like the SwiftUI buttons around it.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// What's on screen of this view. Inside SwiftUI, `visibleRect` reaches far past it (a thumbnail's spans the strip,
    /// the toolbar handle's the whole window), so it's clipped to bounds.
    var shownRect: CGRect { bounds.intersection(visibleRect) }
    /// A thumbnail is clicked (pointing hand); the toolbar handle only drags. Pressed, both show the closed hand.
    private var cursor: NSCursor { isEditorPicture ? .openHand : .pointingHand }
    /// Cursor rects go stale when the strip scrolls; a cursor update from the tracking area doesn't.
    override func cursorUpdate(with event: NSEvent) { cursor.set() }
    override func mouseEntered(with event: NSEvent) { hover(at: event.locationInWindow) }
    override func mouseExited(with event: NSEvent) { hover(at: nil) }
    /// Rebuilt whenever the view moves: an `.inVisibleRect` area spans whatever `visibleRect` does, so every thumbnail
    /// heard the pointer anywhere over the strip (and the handle over the canvas), and hover stuck on the wrong one.
    /// Geometric, so the pointer over a button on top of this view still counts as inside.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        if !shownRect.isEmpty { // scrolled out of the strip
            addTrackingArea(NSTrackingArea(rect: shownRect, options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways], owner: self))
        }
        // Enter and exit events go missing when the view moves under a still pointer (scrolling, thumbnails shifting).
        // Deferred: this runs during layout, when SwiftUI state mustn't change.
        Task { @MainActor [weak self] in self?.hover(at: self?.window?.mouseLocationOutsideOfEventStream) }
    }

    /// Hover from where the pointer is (window coordinates; nil: not over the window). Internal for the self-check.
    func hover(at point: CGPoint?) {
        let inside = point.map { shownRect.contains(convert($0, from: nil)) } ?? false
        guard inside != hovering else { return }
        hovering = inside
        onHover?(inside)
    }

    override func mouseDown(with event: NSEvent) {
        started = false
        downAt = event.locationInWindow
        NSCursor.closedHand.set()
        BugReport.shared.note("source down, hovering \(hovering)")
    }
    override func mouseUp(with event: NSEvent) {
        BugReport.shared.note("source up, pressed here \(downAt != nil), dragged \(started)")
        if downAt != nil, !started { onClick?(event.modifierFlags) }
        downAt = nil
        if hovering { cursor.set() }
    }

    /// How far a press moves before it's a drag: a trackpad click often drifts 3–4 pt.
    static let dragDistance: CGFloat = 6

    override func mouseDragged(with event: NSEvent) {
        guard !started, let downAt, hypot(event.locationInWindow.x - downAt.x, event.locationInWindow.y - downAt.y) >= Self.dragDistance else { return }
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
        BugReport.shared.note("source drag starts, \(items.count) items")
        guard !items.isEmpty else { return started = false } // nothing to drag: the release is still a click
        // A failed drag otherwise slides back for a moment, swallowing the next clicks.
        beginDraggingSession(with: items, event: event, source: self).animatesToStartingPositionsOnCancelOrFail = false
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        dragEnded(at: window?.convertPoint(fromScreen: screenPoint), dropped: operation != [])
    }

    /// The drag swallows the exit event, so the hover follows where it ended. Released back on this view without
    /// a drop, it was a wobbly click. Internal for the self-check (a drag session can't be faked).
    func dragEnded(at point: CGPoint?, dropped: Bool) {
        downAt = nil
        hover(at: point)
        if hovering { cursor.set() }
        BugReport.shared.note("source drag ended, dropped \(dropped), back on it \(hovering)")
        if !dropped, hovering { onClick?(NSEvent.modifierFlags) }
    }
}
