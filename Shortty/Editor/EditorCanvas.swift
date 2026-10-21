import AppKit
import Observation
import SwiftUI

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
        let hasImageFile = (board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true,
                                                                                .urlReadingContentsConformToTypes: ["public.image"]]) ?? []).isEmpty == false
        return hasImageFile || board.canReadObject(forClasses: [NSImage.self], options: nil) ? .copy : []
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
        canvas.annotationsChanged()
        apply(model.zoom ?? fitMagnification)
    }

    private var fitMagnification: CGFloat {
        let natural = canvas.frame.size
        guard natural.width > 0, natural.height > 0 else { return 1 }
        let available = CGSize(width: max(bounds.width - 2 * Self.fitPadding, 1), height: max(bounds.height - 2 * Self.fitPadding, 1))
        return min(available.width / natural.width, available.height / natural.height, 1)
    }

    private func apply(_ target: CGFloat, centeredAt point: CGPoint? = nil) {
        let target = EditorModel.clampZoom(target)
        if abs(magnification - target) > 0.0001 {
            let visible = documentVisibleRect
            setMagnification(target, centeredAt: point ?? CGPoint(x: visible.midX, y: visible.midY))
        }
        canvas.scaleChanged(to: magnification)
        model.displayedZoom = magnification
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
        let target = EditorModel.clampZoom(magnification * factor)
        apply(target, centeredAt: canvas.convert(event.locationInWindow, from: nil))
        model.zoom = target
    }

    @objc private func pinchEnded() { model.zoom = magnification }

    @objc private func boundsChanged() {
        model.displayedZoom = magnification
        canvas.scaleChanged(to: magnification) // handles keep their on-screen size during a pinch
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

/// The 8 resize handles around a selection. In flipped coordinates, so min y is the top edge.
private enum Handle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    /// -1 moves the min edge, 1 the max edge, 0 neither.
    var dx: CGFloat {
        switch self {
        case .topLeft, .left, .bottomLeft: -1
        case .top, .bottom: 0
        case .topRight, .right, .bottomRight: 1
        }
    }

    var dy: CGFloat {
        switch self {
        case .topLeft, .top, .topRight: -1
        case .left, .right: 0
        case .bottomLeft, .bottom, .bottomRight: 1
        }
    }

    var isCorner: Bool { dx != 0 && dy != 0 }
    static let corners: [Handle] = [.topLeft, .topRight, .bottomRight, .bottomLeft]

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

    var cursor: NSCursor {
        switch self {
        case .box(let handle): handle.cursor
        case .arrowStart, .arrowBend, .arrowEnd, .calloutPointer, .magnifierSource, .magnifierTarget: .crosshair
        }
    }
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
    return Handle.allCases.map { (.box($0), $0.point(in: box)) }
}

/// Document view at natural size (points); the scroll view's magnification scales it.
/// Handles the mouse; draws nothing itself (image and annotations are separate layers so edits never repaint the image).
private final class CanvasView: NSView {
    private enum Drag {
        case drawing(id: Annotation.ID, start: CGPoint)
        case moving(original: Annotation, start: CGPoint)
        case resizing(original: Annotation, box: CGRect, handle: Handle)
        case reshaping(original: Annotation, grip: Grip)
        /// One lens of a magnifier: the source area, or the enlarged copy.
        case movingLens(original: Annotation, target: Bool, start: CGPoint)
        /// Recognize Text: a temporary selection, not an annotation.
        case recognizing(start: CGPoint)
        /// Crop tool: dragging out, resizing or moving the box (not an annotation either).
        case cropping(start: CGPoint)
        case cropResize(box: CGRect, handle: Handle)
        case cropMove(box: CGRect, start: CGPoint)

        var annotationID: Annotation.ID? {
            switch self {
            case .drawing(let id, _): id
            case .moving(let original, _), .resizing(let original, _, _), .reshaping(let original, _), .movingLens(let original, _, _): original.id
            case .recognizing, .cropping, .cropResize, .cropMove: nil
            }
        }
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
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

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
        imageView.needsDisplay = true
        overlay.needsDisplay = true
        syncTextEditor()
    }

    /// What the image layer last drew around the image; it only repaints when these change (not on every stroke).
    private var drawnPlate: (content: CGRect, backdrop: Backdrop?) = (.null, nil)

    func annotationsChanged() {
        overlay.needsDisplay = true
        if drawnPlate.content != model.contentRect || drawnPlate.backdrop != model.backdrop {
            drawnPlate = (model.contentRect, model.backdrop)
            imageView.needsDisplay = true
        }
        syncTextEditor()
    }

    func scaleChanged(to magnification: CGFloat) {
        imageView.layer?.magnificationFilter = magnification > 1 ? .nearest : .linear // crisp pixels when enlarged
        imageView.needsDisplay = true
        overlay.needsDisplay = true
        syncTextEditor() // the canvas size (points per pixel) may have changed with a new image
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

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .cursorUpdate, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

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
                drag = .resizing(original: selected, box: selected.bounds, handle: handle)
                overlay.showsSize = true
            } else {
                drag = .reshaping(original: selected, grip: grip)
            }
        } else if model.tool == .select {
            guard let hit = annotation(at: point) else {
                model.select(nil)
                return
            }
            if event.clickCount == 2, hit.isText {
                model.beginEditing(hit.id)
                return
            }
            model.select(hit.id)
            drag = Self.moveDrag(for: hit, at: point)
            NSCursor.closedHand.set()
        } else if model.tool == .recognizeText {
            drag = .recognizing(start: point)
            return
        } else if model.tool == .crop {
            drag = cropDrag(at: point)
            return
        } else if model.tool == .step {
            if let hit = annotation(at: point), hit.isStep {
                model.select(hit.id)
                drag = .moving(original: hit, start: point)
            } else {
                let step = Annotation(shape: .step(center: point), color: model.color, width: model.width(for: .step))
                model.annotations.append(step)
                model.selection = step.id
                drag = .moving(original: step, start: point) // keep the button down to place it precisely
            }
        } else if let selected = model.selectedAnnotation, [.magnifier, .blur, .spotlight].contains(selected.tool),
                  selected.tool == model.tool, selected.contains(point, tolerance: 4 * pixelsPerScreenPoint) {
            // The effect just drawn stays selected; dragging it moves it instead of drawing another.
            drag = Self.moveDrag(for: selected, at: point)
            NSCursor.closedHand.set()
        } else if model.tool == .text {
            if let hit = annotation(at: point), hit.isText {
                model.select(hit.id)
                drag = .moving(original: hit, start: point)
                editOnClick = hit.id
            } else {
                startText(at: point)
                return
            }
        } else {
            let shape: Annotation.Shape = switch model.tool {
            case .rectangle: .rectangle(CGRect(origin: point, size: .zero))
            case .ellipse: .ellipse(CGRect(origin: point, size: .zero))
            case .arrow: .arrow(start: point, end: point, bend: 0, style: model.arrowStyle)
            case .blur: .redact(rect: CGRect(origin: point, size: .zero), style: model.redactStyle, textBoxes: [])
            case .spotlight: .spotlight(rect: CGRect(origin: point, size: .zero), shape: model.spotlightShape)
            case .magnifier: .magnifier(source: CGRect(origin: point, size: .zero), target: CGRect(origin: point, size: .zero), shape: model.magnifierShape)
            case .pencil, .select, .text, .recognizeText, .step, .crop: .stroke([point, point]) // 2 points so a click draws a dot
            }
            let annotation = Annotation(shape: shape, color: model.color, width: model.width(for: model.tool))
            model.annotations.append(annotation)
            model.selection = annotation.isStroke ? nil : annotation.id // shapes and arrows stay selected to adjust right away
            drag = .drawing(id: annotation.id, start: point)
            overlay.showsSize = annotation.usesBoxHandles && !annotation.isStroke
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
        overlay.needsDisplay = true
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
        if case .recognizing = drag {
            if let area = overlay.recognizeArea { model.recognizeText(in: area) }
            overlay.recognizeArea = nil
            return
        }
        if case .drawing(let id, _) = drag, let index = model.annotations.firstIndex(where: { $0.id == id }),
           model.annotations[index].isDegenerate {
            model.annotations.remove(at: index)
            model.selection = nil
        }
        model.recordChange(from: annotationsBeforeDrag)
        if let id = drag.annotationID { model.refreshTextBoxes(id) } // Blur/Erase Text: find the text under its new area
        if let id = editOnClick, !moved { model.beginEditing(id) }
    }

    /// Crop tool: grab a handle of the box, move the box, or drag out a new one.
    private func cropDrag(at point: CGPoint) -> Drag {
        if let box = model.cropBox?.standardized {
            let reach = 7 * pixelsPerScreenPoint
            if let handle = Handle.allCases.first(where: { hypot($0.point(in: box).x - point.x, $0.point(in: box).y - point.y) <= reach }) {
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
            case .text, .image, .step:
                break // text is typed, pictures inserted, steps placed with a click
            case .redact(_, let style, let boxes):
                model.annotations[index].shape = .redact(rect: Annotation.dragRect(from: start, to: point, square: shift), style: style, textBoxes: boxes)
            case .spotlight(_, let shape):
                model.annotations[index].shape = .spotlight(rect: Annotation.dragRect(from: start, to: point, square: shift), shape: shape)
            case .magnifier(_, _, let shape):
                let source = Annotation.dragRect(from: start, to: point, square: shift)
                let target = Magnifier.target(for: source, zoom: Magnifier.defaultZoom, within: model.image.bounds)
                model.annotations[index].shape = .magnifier(source: source, target: target, shape: shape)
            }
        case .moving(let original, let start):
            var offset = CGPoint(x: point.x - start.x, y: point.y - start.y)
            if shift { abs(offset.x) > abs(offset.y) ? (offset.y = 0) : (offset.x = 0) } // Shift: move along one axis
            replace(original.moved(by: offset))
        case .resizing(let original, let box, let handle):
            // Pictures keep their proportions unless Shift is held; shapes are the other way round.
            replace(original.resized(from: box, to: handle.resize(box, to: point, keepAspect: original.isImage ? !shift : shift)))
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
        case .movingLens(let original, let movingTarget, let start):
            guard case .magnifier(let source, let target, let shape) = original.shape else { return }
            var offset = CGPoint(x: point.x - start.x, y: point.y - start.y)
            if shift { abs(offset.x) > abs(offset.y) ? (offset.y = 0) : (offset.x = 0) }
            var moved = original
            let shifted = { (rect: CGRect) in rect.offsetBy(dx: offset.x, dy: offset.y) }
            moved.shape = .magnifier(source: movingTarget ? source : shifted(source), target: movingTarget ? shifted(target) : target, shape: shape)
            replace(moved)
        case .recognizing(let start):
            overlay.recognizeArea = Annotation.dragRect(from: start, to: point, square: false)
            overlay.needsDisplay = true
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

/// A canvas layer that draws in image pixels, offset by the canvas origin.
private protocol CanvasLayer: AnyObject {
    var canvasRect: CGRect { get set }
    var pixelsPerPoint: CGFloat { get set }
}

/// The screenshot, plus the edge-colored fill where the canvas grows past it. Redrawn only when those or the zoom change.
private final class ImageLayerView: NSView, CanvasLayer {
    private let model: EditorModel
    var canvasRect: CGRect = .zero
    var pixelsPerPoint: CGFloat = 2
    private var edgeColor: (image: CGImage, color: CGColor)?

    init(model: EditorModel) {
        self.model = model
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

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
private final class AnnotationLayerView: NSView, CanvasLayer {
    private let model: EditorModel
    var canvasRect: CGRect = .zero
    var pixelsPerPoint: CGFloat = 2
    var showsSize = false
    /// Recognize Text: the area being dragged out (image px).
    var recognizeArea: CGRect?

    init(model: EditorModel) {
        self.model = model
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext, bounds.width > 0 else { return }
        let screenPoint = 1 / (enclosingScrollView?.magnification ?? 1) // one on-screen point, in view units
        // From here on, (x / pixelsPerPoint) maps image pixels to view points.
        context.translateBy(x: -canvasRect.minX / pixelsPerPoint, y: -canvasRect.minY / pixelsPerPoint)

        context.saveGState()
        context.scaleBy(x: 1 / pixelsPerPoint, y: 1 / pixelsPerPoint)
        context.drawAnnotations(model.annotations, on: model.image, canvas: model.contentRect, hidingTextOf: model.editingID)
        context.restoreGState()

        if let area = recognizeArea {
            let rect = CGRect(x: area.minX / pixelsPerPoint, y: area.minY / pixelsPerPoint, width: area.width / pixelsPerPoint, height: area.height / pixelsPerPoint)
            NSColor(Theme.accent).withAlphaComponent(0.12).setFill()
            rect.fill()
            let outline = NSBezierPath(rect: rect)
            outline.lineWidth = 1.5 * screenPoint
            outline.setLineDash([5 * screenPoint, 3 * screenPoint], count: 2, phase: 0)
            NSColor(Theme.accent).setStroke()
            outline.stroke()
        }

        if model.tool == .crop, let crop = model.cropBox {
            drawCropBox(crop, screenPoint: screenPoint)
        }

        guard let selected = model.selectedAnnotation else { return }
        let pixels = selected.textBox?.box.insetBy(dx: -3, dy: -3) ?? selected.bounds
        let box = CGRect(x: pixels.minX / pixelsPerPoint, y: pixels.minY / pixelsPerPoint,
                         width: pixels.width / pixelsPerPoint, height: pixels.height / pixelsPerPoint)

        if selected.usesBoxHandles || selected.isText || selected.isStep {
            let outline = NSBezierPath(rect: box)
            outline.lineWidth = screenPoint
            outline.setLineDash([4 * screenPoint, 3 * screenPoint], count: 2, phase: 0)
            NSColor.white.withAlphaComponent(0.85).setStroke()
            outline.stroke()
        }

        let size = 8 * screenPoint
        for (_, pixel) in grips(for: selected) {
            let center = CGPoint(x: pixel.x / pixelsPerPoint, y: pixel.y / pixelsPerPoint)
            let square = NSBezierPath(roundedRect: CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size),
                                      xRadius: 2 * screenPoint, yRadius: 2 * screenPoint)
            NSColor.white.setFill()
            square.fill()
            square.lineWidth = screenPoint
            NSColor(Theme.accent).setStroke()
            square.stroke()
        }

        if showsSize, selected.usesBoxHandles, !selected.isStroke {
            context.saveGState()
            context.translateBy(x: box.maxX, y: box.maxY + 10 * screenPoint)
            context.scaleBy(x: screenPoint, y: screenPoint) // label stays the same size at any zoom
            drawPill("\(Int(pixels.width.rounded())) × \(Int(pixels.height.rounded()))", font: .monospacedDigitSystemFont(ofSize: 11, weight: .medium)) { size in
                CGPoint(x: -size.width, y: 0)
            }
            context.restoreGState()
        }
    }

    /// Crop tool: everything outside the box dimmed, a dashed outline, handles and the resulting size.
    private func drawCropBox(_ crop: CGRect, screenPoint: CGFloat) {
        func view(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX / pixelsPerPoint, y: rect.minY / pixelsPerPoint, width: rect.width / pixelsPerPoint, height: rect.height / pixelsPerPoint)
        }
        let box = view(crop)
        let dim = NSBezierPath(rect: view(model.contentRect))
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
        for handle in Handle.allCases {
            let center = handle.point(in: box)
            let square = NSBezierPath(roundedRect: CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size),
                                      xRadius: 2 * screenPoint, yRadius: 2 * screenPoint)
            NSColor.white.setFill()
            square.fill()
        }

        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.translateBy(x: box.maxX, y: box.maxY + 10 * screenPoint)
        context.scaleBy(x: screenPoint, y: screenPoint)
        drawPill("\(Int(crop.width)) × \(Int(crop.height))", font: .monospacedDigitSystemFont(ofSize: 11, weight: .medium)) { size in
            CGPoint(x: -size.width, y: 0)
        }
        context.restoreGState()
    }
}
