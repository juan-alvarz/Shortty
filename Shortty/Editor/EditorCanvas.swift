import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

/// Image + annotations inside a native NSScrollView: pinch and ⌘-wheel zoom anchored at the pointer,
/// scrolling when zoomed in, centered when smaller than the window.
struct EditorCanvas: NSViewRepresentable {
    let model: EditorModel
    func makeNSView(context: Context) -> CanvasScrollView { CanvasScrollView(model: model) }
    func updateNSView(_ view: CanvasScrollView, context: Context) {}
}

final class CanvasScrollView: NSScrollView {
    private static let fitPadding: CGFloat = 16
    private let model: EditorModel
    private let canvas: CanvasView
    private var shownImage: CGImage?

    init(model: EditorModel) {
        self.model = model
        canvas = CanvasView(model: model)
        super.init(frame: .zero)
        contentView = CenteringClipView()
        contentView.drawsBackground = false
        drawsBackground = false // the checkerboard behind stays fixed while zooming
        documentView = canvas
        hasVerticalScroller = true
        hasHorizontalScroller = true
        autohidesScrollers = true
        allowsMagnification = true
        minMagnification = EditorModel.zoomRange.lowerBound
        maxMagnification = EditorModel.zoomRange.upperBound

        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(boundsChanged), name: NSView.boundsDidChangeNotification, object: contentView)
        NotificationCenter.default.addObserver(self, selector: #selector(pinchEnded), name: NSScrollView.didEndLiveMagnifyNotification, object: self)
        canvas.onDragEnd = { [weak self] in self?.syncFromModel() }
        registerForDraggedTypes([.fileURL, .png, .tiff])
        syncFromModel()
        observeModel()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    // MARK: Dropping pictures from Finder (or any app)

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { dropOperation(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { dropOperation(sender) }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard dropOperation(sender) == .copy else { return false }
        return model.insertImages(from: sender.draggingPasteboard, centeredAt: canvas.imagePoint(inWindow: sender.draggingLocation)) > 0
    }

    /// Image files or image data, but not our own drag handle (that's the editor's own picture).
    private func dropOperation(_ sender: NSDraggingInfo) -> NSDragOperation {
        if sender.draggingSource is DragSourceView { return [] }
        let board = sender.draggingPasteboard
        let imageFiles: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true, .urlReadingContentsConformToTypes: [UTType.image.identifier]]
        return board.canReadObject(forClasses: [NSURL.self], options: imageFiles) || board.canReadObject(forClasses: [NSImage.self]) ? .copy : []
    }

    /// Clicks in the empty area around the image go to the canvas too, so you can draw or grab things out there.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === contentView ? documentView : hit
    }

    // MARK: Model → view

    private func observeModel() {
        withObservationTracking {
            _ = model.image
            _ = model.zoom
            _ = model.annotations
            _ = model.selection
            _ = model.editingID
            _ = model.backdrop
            _ = model.crop
            _ = model.cropBox
            _ = model.tool
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.syncFromModel()
                self?.observeModel()
            }
        }
    }

    private func syncFromModel() {
        let newImage = model.image !== shownImage
        if newImage {
            shownImage = model.image
            let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
            canvas.setCanvas(model.canvasRect, pixelsPerPoint: scale)
        } else if !canvas.isBusy, model.canvasRect != canvas.canvasRect {
            // Something was drawn or moved past the image's edges (or back): grow/shrink once the drag or typing ends.
            let old = canvas.canvasRect, origin = contentView.bounds.origin
            canvas.setCanvas(model.canvasRect, pixelsPerPoint: canvas.pixelsPerPoint)
            if model.zoom != nil { // when zoomed, keep the image where it was on screen
                let shift = CGPoint(x: (old.minX - model.canvasRect.minX) / canvas.pixelsPerPoint, y: (old.minY - model.canvasRect.minY) / canvas.pixelsPerPoint)
                contentView.scroll(to: CGPoint(x: origin.x + shift.x, y: origin.y + shift.y))
                reflectScrolledClipView(contentView)
            }
        }
        apply(model.zoom ?? fitMagnification)
    }

    private var fitMagnification: CGFloat {
        let natural = canvas.frame.size
        guard natural.width > 0, natural.height > 0 else { return 1 }
        let available = CGSize(width: max(bounds.width - 2 * Self.fitPadding, 1), height: max(bounds.height - 2 * Self.fitPadding, 1))
        return min(available.width / natural.width, available.height / natural.height, 1)
    }

    private func apply(_ target: CGFloat, centeredAt point: CGPoint? = nil) {
        let target = target.clamped(to: EditorModel.zoomRange)
        if abs(magnification - target) > 0.0001 {
            let visible = documentVisibleRect
            setMagnification(target, centeredAt: point ?? CGPoint(x: visible.midX, y: visible.midY))
        }
        boundsChanged()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if model.zoom == nil { apply(fitMagnification) } // stay fitted while the window resizes
    }

    // MARK: View → model

    /// ⌘ + wheel/trackpad scroll zooms around the pointer: away from you zooms in, toward you zooms out.
    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.contains(.command) else { return super.scrollWheel(with: event) }
        let delta = event.isDirectionInvertedFromDevice ? -event.scrollingDeltaY : event.scrollingDeltaY
        guard delta != 0 else { return }
        let factor = event.hasPreciseScrollingDeltas ? exp(delta * 0.01) : (delta > 0 ? 1.25 : 1 / 1.25)
        let target = (magnification * factor).clamped(to: EditorModel.zoomRange)
        apply(target, centeredAt: canvas.convert(event.locationInWindow, from: nil))
        model.zoom = target
    }

    @objc private func pinchEnded() { model.zoom = magnification }

    @objc private func boundsChanged() {
        model.displayedZoom = magnification
        canvas.refresh(magnification: magnification) // handles keep their on-screen size during a pinch
        updateSelectionFrame()
    }

    /// Tells the selection bar where the selection is on screen; hidden while dragging or typing.
    private func updateSelectionFrame() {
        var frame: CGRect?
        if let selected = model.selectedAnnotation, model.editingID == nil, !canvas.isBusy {
            let box = selected.bounds.standardized, ppp = canvas.pixelsPerPoint, origin = canvas.canvasRect.origin
            let inCanvas = CGRect(x: (box.minX - origin.x) / ppp, y: (box.minY - origin.y) / ppp, width: box.width / ppp, height: box.height / ppp)
            let inSelf = convert(inCanvas, from: canvas)
            frame = CGRect(x: inSelf.minX, y: isFlipped ? inSelf.minY : bounds.height - inSelf.maxY, width: inSelf.width, height: inSelf.height)
        }
        if model.selectionFrame != frame { model.selectionFrame = frame }
    }
}

/// Keeps the document centered when it's smaller than the visible area.
private final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return rect }
        let document = documentView.frame
        if rect.width > document.width { rect.origin.x = (document.width - rect.width) / 2 }
        if rect.height > document.height { rect.origin.y = (document.height - rect.height) / 2 }
        return rect
    }
}

// MARK: - Canvas

/// A resize handle around a selection, as the edges it moves: -1 the min edge, 1 the max edge, 0 neither.
/// In flipped coordinates, so min y is the top edge.
private struct Handle {
    let dx: CGFloat, dy: CGFloat
    /// All 8, clockwise from the top-left.
    static let all: [Handle] = [(-1, -1), (0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0)].map { Handle(dx: $0, dy: $1) }
    static let corners = all.filter(\.isCorner)

    var isCorner: Bool { dx != 0 && dy != 0 }
    var cursor: NSCursor { dx == 0 ? .resizeUpDown : dy == 0 ? .resizeLeftRight : .crosshair }

    func point(in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.midX + dx * rect.width / 2, y: rect.midY + dy * rect.height / 2)
    }

    /// `rect` with this handle dragged to `point`. Signed size (negative = flipped past the opposite edge).
    func resize(_ rect: CGRect, to point: CGPoint, keepAspect: Bool) -> CGRect {
        var width = dx < 0 ? rect.maxX - point.x : dx > 0 ? point.x - rect.minX : rect.width
        var height = dy < 0 ? rect.maxY - point.y : dy > 0 ? point.y - rect.minY : rect.height
        if keepAspect, isCorner, rect.width > 0, rect.height > 0 {
            let ratio = rect.width / rect.height
            if abs(width) / ratio > abs(height) {
                height = CGFloat(signOf: height, magnitudeOf: abs(width) / ratio)
            } else {
                width = CGFloat(signOf: width, magnitudeOf: abs(height) * ratio)
            }
        }
        // Keep the opposite edges fixed.
        let x = dx < 0 ? rect.maxX - width : rect.minX
        let y = dy < 0 ? rect.maxY - height : rect.minY
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

/// Something on the selection you can drag: a box handle, an arrow's start / middle (bend) / end, or a callout's pointer.
private enum Grip {
    case box(Handle)
    case arrowStart, arrowBend, arrowEnd
    case calloutPointer
    /// Magnifier corners: resizing the source keeps the zoom; resizing the enlarged copy changes it.
    case magnifierSource(Handle), magnifierTarget(Handle)

    var cursor: NSCursor { if case .box(let handle) = self { handle.cursor } else { .crosshair } }
}

/// Where an annotation's grips sit, in image pixels.
private func grips(for annotation: Annotation) -> [(grip: Grip, point: CGPoint)] {
    switch annotation.shape {
    case .arrow(let start, let end, let bend, _):
        return [(.arrowStart, start), (.arrowBend, ArrowCurve(start: start, end: end, bend: bend).middle), (.arrowEnd, end)]
    case .text(_, _, let style, let pointer):
        return style == .callout ? [(.calloutPointer, pointer)] : []
    case .magnifier(let source, let target, _):
        return Handle.corners.map { (.magnifierSource($0), $0.point(in: source.standardized)) }
            + Handle.corners.map { (.magnifierTarget($0), $0.point(in: target.standardized)) }
    case .stroke, .rectangle, .ellipse, .redact, .spotlight, .image, .step:
        break
    }
    let box = annotation.bounds
    return Handle.all.map { (.box($0), $0.point(in: box)) }
}

/// Document view at natural size (points); the scroll view's magnification scales it.
/// Handles the mouse; draws nothing itself (the image and the annotations are separate layer views).
private final class CanvasView: NSView {
    private enum Drag {
        case drawing(id: Annotation.ID, start: CGPoint)
        case moving(original: Annotation, start: CGPoint)
        case resizing(original: Annotation, handle: Handle)
        case reshaping(original: Annotation, grip: Grip)
        /// One lens of a magnifier: the source area, or the enlarged copy.
        case movingLens(original: Annotation, target: Bool, start: CGPoint)
        /// Crop tool: dragging out, resizing or moving the box (not an annotation either).
        case cropping(start: CGPoint)
        case cropResize(box: CGRect, handle: Handle)
        case cropMove(box: CGRect, start: CGPoint)
    }

    private let model: EditorModel
    private let imageView: ImageLayerView
    private let overlay: AnnotationLayerView
    private var drag: Drag?
    private var annotationsBeforeDrag: [Annotation] = []
    private var lastPoint: CGPoint = .zero
    private var shiftMonitor: Any?
    /// Pencil + Shift: points before this index stay; the rest is one straight segment to the pointer.
    private var straightFrom: Int?
    /// Text tool pressed on existing text: a click (no drag) edits it, a drag moves it.
    private var editOnClick: Annotation.ID?
    private var moved = false
    /// The inline editor while text is being typed. TextKit 1, same as the drawing code, so letters don't shift.
    private var textEditor: NSTextView?
    /// The area shown (image px): the image plus anything drawn past its edges. The view's (0,0) is its top-left.
    private(set) var canvasRect: CGRect = .zero
    /// Image pixels per view point at zoom 1 (the screen's backing scale when the image arrived).
    private(set) var pixelsPerPoint: CGFloat = 2
    /// Called when a mouse drag ends, so the scroll view can grow the canvas to fit what was drawn.
    var onDragEnd: (() -> Void)?
    /// Recognize Text: Apple's Live Text layer over the picture (native highlighting, selection, ⌘C, right-click).
    private var liveText: ImageAnalysisOverlayView?
    private var analyzedImage: CGImage?
    /// Mid-drag or mid-typing: the canvas size stays put so nothing jumps under the pointer.
    var isBusy: Bool { drag != nil || model.editingID != nil }

    init(model: EditorModel) {
        self.model = model
        imageView = ImageLayerView(model: model)
        overlay = AnnotationLayerView(model: model)
        super.init(frame: .zero)
        wantsLayer = true
        imageView.clipsToBounds = true // the picture never shows past the canvas (matters once cropped)
        for layer in [imageView, overlay] as [NSView] {
            layer.autoresizingMask = [.width, .height]
            addSubview(layer)
        }
        // .inVisibleRect keeps the area matched to the visible part as it scrolls and zooms.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .cursorUpdate, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    /// Resizes the canvas. The scroll view's `refresh` always follows and repaints.
    func setCanvas(_ rect: CGRect, pixelsPerPoint: CGFloat) {
        canvasRect = rect
        self.pixelsPerPoint = pixelsPerPoint
        setFrameSize(NSSize(width: rect.width / pixelsPerPoint, height: rect.height / pixelsPerPoint))
        // Unclipped so things dragged past the edge stay visible until the canvas grows, except once cropped.
        overlay.clipsToBounds = model.crop != nil
        for layer in [imageView, overlay] as [CanvasLayer] {
            layer.canvasRect = rect
            layer.pixelsPerPoint = pixelsPerPoint
        }
    }

    /// After any model change, zoom or scroll: repaints both layers, then lines up Live Text and the text editor.
    func refresh(magnification: CGFloat) {
        imageView.layer?.magnificationFilter = magnification > 1 ? .nearest : .linear // crisp pixels when enlarged
        imageView.needsDisplay = true
        overlay.needsDisplay = true
        updateLiveText()
        syncTextEditor()
    }

    // MARK: Geometry

    /// Image pixels per screen point at the current zoom, so hit targets stay the same size on screen.
    private var pixelsPerScreenPoint: CGFloat { pixelsPerPoint / (enclosingScrollView?.magnification ?? 1) }

    private func imagePoint(_ event: NSEvent) -> CGPoint { imagePoint(inWindow: event.locationInWindow) }

    func imagePoint(inWindow location: CGPoint) -> CGPoint {
        let point = convert(location, from: nil)
        return CGPoint(x: canvasRect.minX + point.x * pixelsPerPoint, y: canvasRect.minY + point.y * pixelsPerPoint)
    }

    private func grip(at point: CGPoint) -> Grip? {
        guard let selected = model.selectedAnnotation else { return nil }
        let reach = 7 * pixelsPerScreenPoint
        return grips(for: selected).first { hypot($0.point.x - point.x, $0.point.y - point.y) <= reach }?.grip
    }

    /// Topmost annotation under the pointer. A selected box shape can also be grabbed anywhere inside its box.
    private func annotation(at point: CGPoint) -> Annotation? {
        if let selected = model.selectedAnnotation, selected.usesBoxHandles,
           selected.bounds.insetBy(dx: -4 * pixelsPerScreenPoint, dy: -4 * pixelsPerScreenPoint).contains(point) {
            return selected
        }
        return model.annotations.last { $0.contains(point, tolerance: 5 * pixelsPerScreenPoint) }
    }

    // MARK: Cursor

    override func cursorUpdate(with event: NSEvent) { cursor(for: imagePoint(event)).set() }
    override func mouseMoved(with event: NSEvent) { if drag == nil { cursor(for: imagePoint(event)).set() } }

    private func cursor(for point: CGPoint) -> NSCursor {
        if let grip = grip(at: point) { return grip.cursor }
        if model.tool == .select { return annotation(at: point) == nil ? .arrow : .openHand }
        if model.tool == .text { return .iBeam }
        return .crosshair
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        // Clicking outside the text being typed just finishes it.
        if model.editingID != nil {
            model.endEditing()
            return
        }
        let point = imagePoint(event)
        lastPoint = point
        straightFrom = nil
        editOnClick = nil
        moved = false
        annotationsBeforeDrag = model.annotations

        if let grip = grip(at: point), let selected = model.selectedAnnotation {
            if case .box(let handle) = grip {
                drag = .resizing(original: selected, handle: handle)
                overlay.showsSize = true
            } else {
                drag = .reshaping(original: selected, grip: grip)
            }
        } else if model.tool == .select {
            guard let hit = annotation(at: point) else {
                model.select(nil)
                return
            }
            if event.clickCount == 2, hit.tool == .text {
                model.beginEditing(hit.id)
                return
            }
            model.select(hit.id)
            drag = Self.moveDrag(for: hit, at: point)
            NSCursor.closedHand.set()
        } else if model.tool == .recognizeText {
            return // Live Text handles clicks on the picture; around it there's nothing to do
        } else if model.tool == .crop {
            drag = cropDrag(at: point)
            return
        } else if let hit = annotation(at: point), hit.tool == model.tool,
                  [.step, .text].contains(hit.tool) || hit.id == model.selection && [.magnifier, .blur, .spotlight].contains(hit.tool) {
            // An existing step or text, or the effect just drawn (it stays selected): dragging moves it instead of
            // adding another; a click on text edits it.
            model.select(hit.id)
            drag = Self.moveDrag(for: hit, at: point)
            if hit.tool == .text { editOnClick = hit.id }
            NSCursor.closedHand.set()
        } else if model.tool == .text {
            startText(at: point)
            return
        } else {
            let shape: Annotation.Shape = switch model.tool {
            case .rectangle: .rectangle(CGRect(origin: point, size: .zero))
            case .ellipse: .ellipse(CGRect(origin: point, size: .zero))
            case .arrow: .arrow(start: point, end: point, bend: 0, style: model.arrowStyle)
            case .blur: .redact(rect: CGRect(origin: point, size: .zero), style: model.redactStyle, textBoxes: [])
            case .spotlight: .spotlight(rect: CGRect(origin: point, size: .zero), shape: model.spotlightShape)
            case .magnifier: .magnifier(source: CGRect(origin: point, size: .zero), target: CGRect(origin: point, size: .zero), shape: model.magnifierShape)
            case .step: .step(center: point) // keep the button down to place it precisely
            case .pencil, .select, .text, .recognizeText, .crop: .stroke([point, point]) // 2 points so a click draws a dot
            }
            let annotation = Annotation(shape: shape, color: model.color, width: model.width(for: model.tool))
            model.annotations.append(annotation)
            model.selection = annotation.tool == .pencil ? nil : annotation.id // shapes, arrows and steps stay selected to adjust right away
            drag = .drawing(id: annotation.id, start: point)
            overlay.showsSize = annotation.usesBoxHandles && annotation.tool != .pencil
        }
        // Shift pressed or released mid-drag takes effect without moving the mouse.
        shiftMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return event }
            self.update(to: self.lastPoint, shift: event.modifierFlags.contains(.shift), pointerMoved: false)
            return event
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard drag != nil else { return }
        autoscroll(with: event)
        lastPoint = imagePoint(event)
        update(to: lastPoint, shift: event.modifierFlags.contains(.shift), pointerMoved: true)
    }

    override func mouseUp(with event: NSEvent) {
        if let shiftMonitor { NSEvent.removeMonitor(shiftMonitor) }
        shiftMonitor = nil
        overlay.showsSize = false
        defer {
            drag = nil
            onDragEnd?()
            cursor(for: imagePoint(event)).set()
        }
        guard let drag else { return }
        switch drag {
        case .cropping, .cropResize, .cropMove:
            if let box = model.cropBox, box.width < 4 || box.height < 4 { model.cropBox = nil }
            return
        default: break
        }
        if case .drawing(let id, _) = drag, let index = model.annotations.firstIndex(where: { $0.id == id }),
           model.annotations[index].isDegenerate {
            model.annotations.remove(at: index)
            model.selection = nil
        }
        model.recordChange(from: annotationsBeforeDrag)
        if let id = model.selection { model.refreshTextBoxes(id) } // Blur/Erase Text (always the selection): find the text under its new area
        if let id = editOnClick, !moved { model.beginEditing(id) }
    }

    /// Crop tool: grab a handle of the box, move the box, or drag out a new one.
    private func cropDrag(at point: CGPoint) -> Drag {
        if let box = model.cropBox?.standardized {
            let reach = 7 * pixelsPerScreenPoint
            if let handle = Handle.all.first(where: { hypot($0.point(in: box).x - point.x, $0.point(in: box).y - point.y) <= reach }) {
                return .cropResize(box: box, handle: handle)
            }
            if box.contains(point) { return .cropMove(box: box, start: point) }
        }
        return .cropping(start: point)
    }

    /// Dragging a magnifier moves the lens under the pointer; anything else moves as a whole.
    private static func moveDrag(for annotation: Annotation, at point: CGPoint) -> Drag {
        if case .magnifier(_, let target, _) = annotation.shape {
            return .movingLens(original: annotation, target: target.standardized.contains(point), start: point)
        }
        return .moving(original: annotation, start: point)
    }

    /// New text where the user clicked: the caret lands about on the click.
    private func startText(at point: CGPoint) {
        let fontSize = model.width(for: .text)
        let padding = model.textStyle == .plain ? CGSize.zero : CGSize(width: (fontSize * 0.55).rounded(), height: (fontSize * 0.3).rounded())
        let origin = CGPoint(x: point.x - padding.width, y: point.y - padding.height - fontSize * 0.6)
        let pointer = CGPoint(x: origin.x + fontSize * 0.6, y: origin.y + fontSize * 2.6) // just below-left, like a speech bubble
        let annotation = Annotation(shape: .text(origin: origin, string: "", style: model.textStyle, pointer: pointer),
                                    color: model.color, width: fontSize)
        let before = model.annotations
        model.annotations.append(annotation)
        model.beginEditing(annotation.id, before: before)
    }

    private func update(to point: CGPoint, shift: Bool, pointerMoved: Bool) {
        guard let drag else { return }
        if pointerMoved { moved = true }
        switch drag {
        case .drawing(let id, let start):
            guard let index = model.annotations.firstIndex(where: { $0.id == id }) else { return }
            switch model.annotations[index].shape {
            case .stroke(var points):
                if shift {
                    // Straight line from where Shift went down (or the stroke start) toward the pointer.
                    let anchor = straightFrom ?? points.count
                    straightFrom = anchor
                    points = Array(points.prefix(anchor)) + [point]
                } else {
                    straightFrom = nil // releasing Shift continues freehand from the line's end
                    guard pointerMoved else { return }
                    points.append(point)
                }
                model.annotations[index].shape = .stroke(points)
            case .rectangle:
                model.annotations[index].shape = .rectangle(Annotation.dragRect(from: start, to: point, square: shift))
            case .ellipse:
                model.annotations[index].shape = .ellipse(Annotation.dragRect(from: start, to: point, square: shift))
            case .arrow(_, _, let bend, let style):
                model.annotations[index].shape = .arrow(start: start, end: shift ? Self.snapped(from: start, to: point) : point, bend: bend, style: style)
            case .step:
                model.annotations[index].shape = .step(center: point)
            case .text, .image:
                break // text is typed, pictures inserted
            case .redact(_, let style, let boxes):
                model.annotations[index].shape = .redact(rect: Annotation.dragRect(from: start, to: point, square: shift), style: style, textBoxes: boxes)
            case .spotlight(_, let shape):
                model.annotations[index].shape = .spotlight(rect: Annotation.dragRect(from: start, to: point, square: shift), shape: shape)
            case .magnifier(_, _, let shape):
                let source = Annotation.dragRect(from: start, to: point, square: shift)
                let target = Magnifier.target(for: source, within: model.image.bounds)
                model.annotations[index].shape = .magnifier(source: source, target: target, shape: shape)
            }
        case .moving(let original, let start), .movingLens(let original, _, let start):
            var offset = CGPoint(x: point.x - start.x, y: point.y - start.y)
            if shift { abs(offset.x) > abs(offset.y) ? (offset.y = 0) : (offset.x = 0) } // Shift: move along one axis
            guard case .movingLens(_, let movingTarget, _) = drag, case .magnifier(let source, let target, let shape) = original.shape
            else { return replace(original.moved(by: offset)) }
            var moved = original
            let shifted = { (rect: CGRect) in rect.offsetBy(dx: offset.x, dy: offset.y) }
            moved.shape = .magnifier(source: movingTarget ? source : shifted(source), target: movingTarget ? shifted(target) : target, shape: shape)
            replace(moved)
        case .resizing(let original, let handle):
            // Pictures keep their proportions unless Shift is held; shapes are the other way round.
            replace(original.resized(from: original.bounds, to: handle.resize(original.bounds, to: point, keepAspect: original.isImage ? !shift : shift)))
        case .reshaping(let original, let grip):
            var reshaped = original
            switch original.shape {
            case .arrow(var start, var end, var bend, let style):
                switch grip {
                case .arrowStart: start = shift ? Self.snapped(from: end, to: point) : point
                case .arrowEnd: end = shift ? Self.snapped(from: start, to: point) : point
                case .arrowBend: bend = shift ? 0 : ArrowCurve.bend(through: point, start: start, end: end) // Shift straightens
                case .box, .calloutPointer, .magnifierSource, .magnifierTarget: return
                }
                reshaped.shape = .arrow(start: start, end: end, bend: bend, style: style)
            case .text(let origin, let string, let style, _):
                reshaped.shape = .text(origin: origin, string: string, style: style, pointer: point)
            case .magnifier(let source, let target, let shape):
                let source = source.standardized, target = target.standardized
                switch grip {
                case .magnifierSource(let handle):
                    // New source area, same zoom, copy stays centered where it was.
                    let zoom = source.width > 0 ? target.width / source.width : Magnifier.defaultZoom
                    let newSource = handle.resize(source, to: point, keepAspect: shift).standardized
                    let size = CGSize(width: newSource.width * zoom, height: newSource.height * zoom)
                    reshaped.shape = .magnifier(source: newSource, target: CGRect(x: target.midX - size.width / 2, y: target.midY - size.height / 2,
                                                                                width: size.width, height: size.height), shape: shape)
                case .magnifierTarget(let handle):
                    // Same source, bigger or smaller copy: the zoom changes, the proportions don't.
                    reshaped.shape = .magnifier(source: source, target: handle.resize(target, to: point, keepAspect: true).standardized, shape: shape)
                default:
                    return
                }
            case .stroke, .rectangle, .ellipse, .redact, .spotlight, .image, .step:
                return
            }
            replace(reshaped)
        case .cropping(let start):
            setCropBox(Annotation.dragRect(from: start, to: point, square: shift))
        case .cropResize(let box, let handle):
            setCropBox(handle.resize(box, to: point, keepAspect: shift).standardized)
        case .cropMove(let box, let start):
            // Slide the box, kept inside the picture.
            let content = model.contentRect
            var moved = box.offsetBy(dx: point.x - start.x, dy: point.y - start.y)
            moved.origin.x = min(max(moved.minX, content.minX), content.maxX - moved.width)
            moved.origin.y = min(max(moved.minY, content.minY), content.maxY - moved.height)
            model.cropBox = moved
        }
    }

    /// The crop box never reaches past the picture.
    private func setCropBox(_ box: CGRect) {
        let clipped = box.intersection(model.contentRect)
        model.cropBox = clipped.isNull ? nil : clipped
    }

    /// Shift for arrows: point the line at the nearest 45°, keeping its length along that direction.
    private static func snapped(from anchor: CGPoint, to point: CGPoint) -> CGPoint {
        let dx = point.x - anchor.x, dy = point.y - anchor.y
        let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
        let length = dx * cos(angle) + dy * sin(angle)
        return CGPoint(x: anchor.x + cos(angle) * length, y: anchor.y + sin(angle) * length)
    }

    private func replace(_ annotation: Annotation) {
        guard let index = model.annotations.firstIndex(where: { $0.id == annotation.id }) else { return }
        model.annotations[index] = annotation
    }

    // MARK: Live Text (Recognize Text mode)

    /// Shows Live Text over the picture while Recognize Text is the tool (analyzing each new picture once), hides it otherwise.
    private func updateLiveText() {
        guard model.tool == .recognizeText, ImageAnalyzer.isSupported else {
            liveText?.isHidden = true
            if model.hasTextSelection { model.hasTextSelection = false }
            return
        }
        let overlay = liveText ?? makeLiveText()
        overlay.isHidden = false
        let image = model.image
        overlay.frame = CGRect(x: -canvasRect.minX / pixelsPerPoint, y: -canvasRect.minY / pixelsPerPoint,
                               width: CGFloat(image.width) / pixelsPerPoint, height: CGFloat(image.height) / pixelsPerPoint)
        guard analyzedImage !== image else { return }
        analyzedImage = image
        overlay.analysis = nil
        model.recognizedText = nil
        model.toast = "Finding text…"
        Task {
            let analysis = try? await ImageAnalyzer().analyze(image, orientation: .up, configuration: ImageAnalyzer.Configuration([.text]))
            guard analyzedImage === image else { return } // a newer picture arrived meanwhile
            overlay.analysis = analysis
            overlay.selectableItemsHighlighted = true // show where the text is
            let text = analysis?.transcript ?? ""
            model.recognizedText = text
            model.toast = text.isEmpty ? "No text found" : nil
        }
    }

    private func makeLiveText() -> ImageAnalysisOverlayView {
        let overlay = ImageAnalysisOverlayView()
        overlay.preferredInteractionTypes = .textSelection
        overlay.delegate = self
        addSubview(overlay) // above the picture and annotations
        liveText = overlay
        model.copySelectedText = { [weak self, weak overlay] in
            guard let self, let text = overlay?.selectedText, !text.isEmpty else { return }
            self.model.copyText(text, message: "Copied")
        }
        return overlay
    }

    // MARK: Inline text editor

    /// Shows, updates or removes the text view to match `model.editingID`.
    private func syncTextEditor() {
        guard let id = model.editingID, let annotation = model.annotations.first(where: { $0.id == id }),
              case .text(_, let string, let style, _) = annotation.shape, let layout = annotation.textBox else {
            if let textEditor {
                if window?.firstResponder === textEditor { window?.makeFirstResponder(nil) }
                textEditor.removeFromSuperview()
                self.textEditor = nil
            }
            return
        }
        let scale = pixelsPerPoint
        let attributes = TextBox.attributes(fontSize: annotation.width / scale, style: style, color: annotation.color)
        let editor = textEditor ?? makeTextEditor(string: string)
        if editor.string != string { editor.string = string }
        editor.textStorage?.setAttributes(attributes, range: NSRange(location: 0, length: (editor.string as NSString).length))
        editor.typingAttributes = attributes
        editor.insertionPointColor = attributes[.foregroundColor] as? NSColor ?? .white
        let size = TextBox.measure(string, attributes: attributes, fontSize: annotation.width / scale)
        editor.frame = CGRect(x: (layout.textRect.minX - canvasRect.minX) / scale, y: (layout.textRect.minY - canvasRect.minY) / scale,
                              width: size.width + 6, height: size.height)
    }

    private func makeTextEditor(string: String) -> NSTextView {
        let editor = NSTextView(usingTextLayoutManager: false)
        editor.delegate = self
        editor.string = string
        editor.drawsBackground = false
        editor.isRichText = false
        editor.allowsUndo = true
        editor.focusRingType = .none
        editor.textContainerInset = .zero
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.widthTracksTextView = false
        editor.textContainer?.containerSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        editor.isContinuousSpellCheckingEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        addSubview(editor)
        window?.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: (string as NSString).length, length: 0))
        textEditor = editor
        return editor
    }
}

extension CanvasView: ImageAnalysisOverlayViewDelegate {
    func textSelectionDidChange(_ overlayView: ImageAnalysisOverlayView) {
        model.hasTextSelection = overlayView.hasActiveTextSelection
    }

    /// The overlay spans exactly the picture.
    func contentsRect(for overlayView: ImageAnalysisOverlayView) -> CGRect { CGRect(x: 0, y: 0, width: 1, height: 1) }
}

extension CanvasView: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        if let textEditor { model.setText(textEditor.string) }
    }

    /// Esc finishes typing and switches to Select (the text stays selected). Return adds a line.
    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        model.tool = .select // ends editing too
        return true
    }
}

/// A canvas layer: draws in image pixels, offset by the canvas origin. Clicks go through to the canvas.
private class CanvasLayer: NSView {
    let model: EditorModel
    var canvasRect: CGRect = .zero
    var pixelsPerPoint: CGFloat = 2

    init(model: EditorModel) {
        self.model = model
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The screenshot, plus the edge-colored fill where the canvas grows past it.
private final class ImageLayerView: CanvasLayer {
    private var edgeColor: (image: CGImage, color: CGColor)?

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let image = model.image
        let content = model.contentRect
        let magnified = (enclosingScrollView?.magnification ?? 1) > 1
        context.scaleBy(x: 1 / pixelsPerPoint, y: 1 / pixelsPerPoint)
        context.translateBy(x: -canvasRect.minX, y: -canvasRect.minY) // image pixel coordinates from here on

        // The image, with the edge-colored fill where the content grows past it.
        let drawContent = {
            if content != image.bounds {
                if self.edgeColor?.image !== image { self.edgeColor = (image, image.edgeColor) }
                context.setFillColor(self.edgeColor!.color)
                context.fill(content)
            }
            context.interpolationQuality = magnified ? .none : .high
            context.drawUpright(image, in: image.bounds)
        }
        if let backdrop = model.backdrop {
            context.drawBackdrop(backdrop, canvas: canvasRect, content: content, drawContent: drawContent)
        } else {
            drawContent()
        }
    }
}

/// Annotations, the selection box with handles, and a size label while drawing or resizing shapes.
private final class AnnotationLayerView: CanvasLayer {
    var showsSize = false

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext, bounds.width > 0 else { return }
        let screenPoint = pixelsPerPoint / (enclosingScrollView?.magnification ?? 1) // one on-screen point, in image pixels
        context.scaleBy(x: 1 / pixelsPerPoint, y: 1 / pixelsPerPoint)
        context.translateBy(x: -canvasRect.minX, y: -canvasRect.minY) // image pixel coordinates from here on

        context.saveGState()
        context.drawAnnotations(model.annotations, on: model.image, canvas: model.contentRect, hidingTextOf: model.editingID)
        context.restoreGState()

        if model.tool == .crop, let crop = model.cropBox {
            drawCropBox(crop, screenPoint: screenPoint)
        }

        guard let selected = model.selectedAnnotation else { return }
        let box = selected.textBox?.box.insetBy(dx: -3, dy: -3) ?? selected.bounds

        if selected.usesBoxHandles || [.text, .step].contains(selected.tool) {
            let outline = NSBezierPath(rect: box)
            outline.lineWidth = screenPoint
            outline.setLineDash([4 * screenPoint, 3 * screenPoint], count: 2, phase: 0)
            NSColor.white.withAlphaComponent(0.85).setStroke()
            outline.stroke()
        }

        let size = 8 * screenPoint
        for (_, center) in grips(for: selected) {
            let square = NSBezierPath(roundedRect: CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size),
                                      xRadius: 2 * screenPoint, yRadius: 2 * screenPoint)
            NSColor.white.setFill()
            square.fill()
            square.lineWidth = screenPoint
            NSColor(Theme.accent).setStroke()
            square.stroke()
        }

        if showsSize, selected.usesBoxHandles, selected.tool != .pencil {
            drawSizeLabel(box, screenPoint: screenPoint)
        }
    }

    /// Crop tool: everything outside the box dimmed, a dashed outline, handles and the resulting size.
    private func drawCropBox(_ box: CGRect, screenPoint: CGFloat) {
        let dim = NSBezierPath(rect: model.contentRect)
        dim.append(NSBezierPath(rect: box))
        dim.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.55).setFill()
        dim.fill()

        let outline = NSBezierPath(rect: box)
        outline.lineWidth = 1.5 * screenPoint
        outline.setLineDash([6 * screenPoint, 4 * screenPoint], count: 2, phase: 0)
        NSColor.white.setStroke()
        outline.stroke()

        let size = 9 * screenPoint
        for handle in Handle.all {
            let center = handle.point(in: box)
            let square = NSBezierPath(roundedRect: CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size),
                                      xRadius: 2 * screenPoint, yRadius: 2 * screenPoint)
            NSColor.white.setFill()
            square.fill()
        }
        drawSizeLabel(box, screenPoint: screenPoint)
    }

    /// "W × H" in image pixels under the box's bottom-right corner, the same size at any zoom.
    private func drawSizeLabel(_ box: CGRect, screenPoint: CGFloat) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.translateBy(x: box.maxX, y: box.maxY + 10 * screenPoint)
        context.scaleBy(x: screenPoint, y: screenPoint)
        drawPill("\(Int(box.width.rounded())) × \(Int(box.height.rounded()))", font: .monospacedDigitSystemFont(ofSize: 11, weight: .medium)) {
            CGPoint(x: -$0.width, y: 0)
        }
        context.restoreGState()
    }
}
