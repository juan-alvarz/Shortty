import AppKit
import Observation
import SwiftUI

@Observable
final class EditorModel {
    enum Tool { case select, pencil, arrow, text, rectangle, ellipse, step, magnifier, blur, spotlight, recognizeText, crop }

    private(set) var image: CGImage
    /// False until the first capture/image is loaded (the window starts with a 1px placeholder).
    private(set) var hasImage = false
    /// The history file this capture came from, if any (the history strip highlights it).
    private(set) var sourceFile: URL?
    /// ⌘ is held: tool buttons show their keys.
    var showsShortcutHints = false
    /// Where the selection is on screen (canvas view points, top-left origin), for the selection bar.
    /// Set by the canvas; nil while nothing is selected, a drag is in progress, or text is being typed.
    var selectionFrame: CGRect?
    /// Bottom to top. Mutations made outside the methods below must call `recordChange(from:)` to be undoable.
    var annotations: [Annotation] = []
    var selection: Annotation.ID?
    var tool: Tool = .pencil {
        didSet {
            endEditing()
            if tool != .select { selection = nil }
            if tool != .crop { cropBox = nil }
        }
    }
    /// Crop tool: the box being adjusted, not applied yet (image px).
    var cropBox: CGRect?
    /// The applied crop (image px): the output is just this area. Non-destructive: Reset or undo brings the rest back.
    private(set) var crop: CGRect?
    /// Color for new annotations; picking one also recolors the selection.
    private(set) var color = Theme.accent
    /// Style for new arrows; changing it also updates a selected arrow.
    private(set) var arrowStyle: ArrowStyle = .line
    /// Style for new text; changing it also updates selected text.
    private(set) var textStyle: TextStyle = .callout
    /// The text annotation being typed into, if any.
    private(set) var editingID: Annotation.ID?
    @ObservationIgnored private var annotationsBeforeEdit: [Annotation] = []
    /// Variants for new blur/spotlight/magnifier annotations; changing them also updates the selection.
    private(set) var redactStyle: RedactStyle = .blur
    private(set) var spotlightShape: AreaShape = .rectangle
    private(set) var magnifierShape: AreaShape = .ellipse
    /// A short message shown at the bottom of the editor (e.g. after copying recognized text).
    var toast: String?
    /// Where recognized text goes. The self-check swaps in a private pasteboard.
    @ObservationIgnored var textPasteboard: NSPasteboard = .general
    /// Recognize Text mode: every word Live Text found in the picture; nil until it has looked.
    var recognizedText: String?
    /// Live Text has a selection (the panel offers Copy, ⌘C copies text instead of the image).
    var hasTextSelection = false
    /// Set by the canvas: copies the current Live Text selection.
    @ObservationIgnored var copySelectedText: (() -> Void)?
    /// Gradient Backdrop: nil = off. Applies to the whole result (shown live and exported).
    var backdrop: Backdrop?
    /// "Capture new area" in the insert menu; the window controller hides the editor, captures, and inserts.
    @ObservationIgnored var onInsertCapture: (() -> Void)?
    /// Pin to screen: the window controller floats the finished picture and closes the editor.
    @ObservationIgnored var onPin: ((CGImage) -> Void)?

    func pin() {
        endEditing()
        onPin?(rendered)
    }
    /// The slider value per tool: thickness in image px; font size for text; block size for blur; dim % for spotlight.
    private(set) var toolWidths: [Tool: CGFloat] = [.pencil: 4, .arrow: 6, .text: 28, .rectangle: 4, .ellipse: 4,
                                                    .magnifier: 4, .blur: 12, .spotlight: 60, .step: 36]
    /// nil = fit to window. Otherwise points per natural point (1 = one image pixel per screen pixel).
    var zoom: CGFloat?
    /// What the canvas actually shows right now (fit or explicit); the toolbar reads this.
    var displayedZoom: CGFloat = 1
    /// Called after copy/save so the window can close.
    var onFinish: (() -> Void)?

    /// What undo restores: the annotations and the crop.
    private struct Snapshot {
        var annotations: [Annotation]
        var crop: CGRect?
    }
    @ObservationIgnored private var undoStack: [Snapshot] = []
    @ObservationIgnored private var redoStack: [Snapshot] = []
    /// Annotations from before a live slider drag; set while one is in progress.
    @ObservationIgnored private var annotationsBeforeLiveChange: [Annotation]?
    var isLiveChanging: Bool { annotationsBeforeLiveChange != nil }

    init(image: CGImage) { self.image = image }

    /// Replaces the image for a new capture and resets edits.
    func load(_ image: CGImage, from file: URL? = nil) {
        self.image = image
        sourceFile = file
        hasImage = true
        annotations = []
        selection = nil
        crop = nil
        cropBox = nil
        recognizedText = nil
        hasTextSelection = false
        undoStack = []
        redoStack = []
        zoom = nil
    }

    /// The crop when there is one, else the image plus anything drawn past its edges.
    var contentRect: CGRect { crop ?? image.canvasRect(for: annotations) }
    /// Everything shown and exported: the content, plus the backdrop's padding when it's on.
    var canvasRect: CGRect {
        guard let backdrop else { return contentRect }
        let pad = backdrop.paddingSize(for: contentRect)
        return contentRect.insetBy(dx: -pad, dy: -pad)
    }
    var pixelSize: String { "\(Int(canvasRect.width))×\(Int(canvasRect.height))px" }
    var selectedAnnotation: Annotation? { annotations.first { $0.id == selection } }
    private var selectedIndex: Int? { annotations.firstIndex { $0.id == selection } }

    // MARK: Editing

    /// Whose options the floating panel shows: the selection's kind, else the current tool.
    var optionsTool: Tool { selectedAnnotation?.tool ?? tool }
    /// The floating options panel: for any drawing tool, or when something is selected.
    var showsOptions: Bool {
        if let selected = selectedAnnotation { return !selected.isImage } // inserted pictures have nothing to adjust
        return tool != .select
    }
    var showsArrowStyles: Bool { optionsTool == .arrow }
    var showsTextStyles: Bool { optionsTool == .text }
    /// Crop and Recognize Text have buttons instead; erase has nothing to adjust.
    var showsWidthSlider: Bool { optionsTool != .crop && optionsTool != .recognizeText && (optionsTool != .blur || redactStyle.usesStrength) }
    var currentWidthRange: ClosedRange<CGFloat> {
        switch optionsTool {
        case .text: 12...120
        case .blur: 4...40
        case .spotlight: 20...90
        case .step: 16...96
        default: 2...24
        }
    }

    /// What the thickness slider shows: the selection's width, else the current tool's.
    var currentWidth: CGFloat { selectedAnnotation?.width ?? width(for: tool) }

    func width(for tool: Tool) -> CGFloat { toolWidths[tool] ?? Theme.strokeWidth }

    func select(_ id: Annotation.ID?) {
        if id != editingID { endEditing() }
        selection = id
        guard let selected = selectedAnnotation else { return }
        color = selected.color
        if case .arrow(_, _, _, let style) = selected.shape { arrowStyle = style }
        switch selected.shape {
        case .text(_, _, let style, _): textStyle = style
        case .redact(_, let style, _): redactStyle = style
        case .spotlight(_, let shape): spotlightShape = shape
        case .magnifier(_, _, let shape): magnifierShape = shape
        default: break
        }
    }

    func setRedactStyle(_ style: RedactStyle) {
        redactStyle = style
        guard let i = selectedIndex, case .redact(let rect, _, let boxes) = annotations[i].shape else { return }
        edit { $0[i].shape = .redact(rect: rect, style: style, textBoxes: boxes) }
        refreshTextBoxes(annotations[i].id)
    }

    /// Rectangle/ellipse for the spotlight or magnifier, whichever the panel is showing.
    func setAreaShape(_ shape: AreaShape) {
        if optionsTool == .spotlight { spotlightShape = shape } else { magnifierShape = shape }
        guard let i = selectedIndex else { return }
        switch annotations[i].shape {
        case .spotlight(let rect, _): edit { $0[i].shape = .spotlight(rect: rect, shape: shape) }
        case .magnifier(let source, let target, _): edit { $0[i].shape = .magnifier(source: source, target: target, shape: shape) }
        default: break
        }
    }

    /// Re-finds the text under a Blur Text / Erase Text area after it's drawn, moved, resized or restyled.
    /// Derived data, so no undo step of its own.
    func refreshTextBoxes(_ id: Annotation.ID) {
        guard let i = annotations.firstIndex(where: { $0.id == id }), case .redact(let rect, let style, _) = annotations[i].shape else { return }
        let boxes = style.textOnly ? TextRecognition.lineBoxes(in: image, rect: rect) : []
        annotations[i].shape = .redact(rect: rect, style: style, textBoxes: boxes)
    }

    // MARK: Recognize Text (Live Text)

    /// Copies text to the clipboard (or the self-check's private pasteboard) and says so.
    func copyText(_ text: String, message: String) {
        textPasteboard.clearContents()
        textPasteboard.setString(text, forType: .string)
        toast = message
    }

    func copyAllText() {
        guard let text = recognizedText, !text.isEmpty else {
            toast = "No text found"
            return
        }
        copyText(text, message: "Copied all text")
    }

    func setTextStyle(_ style: TextStyle) {
        textStyle = style
        guard let i = selectedIndex, case .text(let origin, let string, _, let pointer) = annotations[i].shape else { return }
        edit { $0[i].shape = .text(origin: origin, string: string, style: style, pointer: pointer) }
    }

    // MARK: Text editing (the canvas shows an inline editor while `editingID` is set)

    /// `before`: annotations from before the text was created, so creating + typing is one undo step.
    func beginEditing(_ id: Annotation.ID, before: [Annotation]? = nil) {
        endEditing()
        annotationsBeforeEdit = before ?? annotations
        selection = id
        editingID = id
    }

    func setText(_ string: String) {
        guard let i = annotations.firstIndex(where: { $0.id == editingID }),
              case .text(let origin, _, let style, let pointer) = annotations[i].shape else { return }
        annotations[i].shape = .text(origin: origin, string: string, style: style, pointer: pointer)
    }

    /// Finishes typing: empty text is removed, the whole edit becomes one undo step.
    func endEditing() {
        guard let id = editingID else { return }
        editingID = nil
        if let i = annotations.firstIndex(where: { $0.id == id }), annotations[i].isDegenerate {
            annotations.remove(at: i)
            if selection == id { selection = nil }
        }
        recordChange(from: annotationsBeforeEdit)
    }

    func setArrowStyle(_ style: ArrowStyle) {
        arrowStyle = style
        guard let i = selectedIndex, case .arrow(let start, let end, let bend, _) = annotations[i].shape else { return }
        edit { $0[i].shape = .arrow(start: start, end: end, bend: bend, style: style) }
    }

    /// Sets the selection's thickness (and remembers it for that kind of annotation), or the current tool's.
    /// `undoable: false` for live slider drags, like `setColor`.
    func setWidth(_ width: CGFloat, undoable: Bool = true) {
        if let kind = selectedAnnotation.map(\.tool) ?? (tool == .select ? nil : tool) { toolWidths[kind] = width }
        updateSelection(undoable: undoable) { $0.width = width }
    }

    /// `undoable: false` for live slider drags; `liveChange(false)` records one step at the end.
    func setColor(_ newColor: Color, undoable: Bool = true) {
        color = newColor
        updateSelection(undoable: undoable) { $0.color = newColor }
    }

    // Index looked up before `edit` starts: reading `annotations` inside its inout access would be an exclusivity violation.
    private func updateSelection(undoable: Bool, _ change: (inout Annotation) -> Void) {
        guard let i = selectedIndex else { return }
        if undoable { edit { change(&$0[i]) } } else { change(&annotations[i]) }
    }

    /// Slider drags: `true` when one starts, `false` when it ends, which records the whole drag as one undo step.
    func liveChange(_ began: Bool) {
        if began {
            annotationsBeforeLiveChange = annotations
        } else if let before = annotationsBeforeLiveChange {
            recordChange(from: before)
            annotationsBeforeLiveChange = nil
        }
    }

    func deleteSelection() {
        guard let i = selectedIndex else { return }
        edit { $0.remove(at: i) }
        selection = nil
    }

    /// A copy a little down and to the right, selected.
    func duplicateSelection() {
        guard let selected = selectedAnnotation else { return }
        let copy = Annotation(shape: selected.shape, color: selected.color, width: selected.width).moved(by: CGPoint(x: 24, y: 24))
        edit { $0.append(copy) }
        select(copy.id)
    }

    /// Draws the selection above everything else (the end of the list is the top).
    func bringSelectionToFront() {
        guard let i = selectedIndex, i < annotations.count - 1 else { return }
        edit { let item = $0.remove(at: i); $0.append(item) }
    }

    /// Draws the selection under everything else, e.g. a picture behind the arrows that point at it.
    func sendSelectionToBack() {
        guard let i = selectedIndex, i > 0 else { return }
        edit { let item = $0.remove(at: i); $0.insert(item, at: 0) }
    }

    func nudgeSelection(by offset: CGPoint) {
        guard let i = selectedIndex else { return }
        edit { $0[i] = $0[i].moved(by: offset) }
        refreshTextBoxes(annotations[i].id)
    }

    /// Makes the change from `before` to the current annotations undoable (no-op if nothing changed).
    func recordChange(from before: [Annotation]) {
        guard before != annotations else { return }
        undoStack.append(Snapshot(annotations: before, crop: crop))
        redoStack.removeAll()
    }

    func undo() { step(from: &undoStack, to: &redoStack) }
    func redo() { step(from: &redoStack, to: &undoStack) }

    /// Restores the last snapshot of `source`, saving the current state onto `target`.
    private func step(from source: inout [Snapshot], to target: inout [Snapshot]) {
        guard let snapshot = source.popLast() else { return }
        target.append(Snapshot(annotations: annotations, crop: crop))
        annotations = snapshot.annotations
        crop = snapshot.crop
        if selectedIndex == nil { selection = nil }
    }

    // MARK: Crop

    /// Crops to the box being adjusted (Return or the Crop button), then goes back to Select.
    func applyCrop() {
        guard let box = cropBox?.standardized.integral, box.width >= 4, box.height >= 4 else { return }
        undoStack.append(Snapshot(annotations: annotations, crop: crop))
        redoStack.removeAll()
        crop = box
        tool = .select
    }

    /// Back to the whole picture (undoable).
    func resetCrop() {
        guard crop != nil else { return }
        undoStack.append(Snapshot(annotations: annotations, crop: crop))
        redoStack.removeAll()
        crop = nil
    }

    private func edit(_ change: (inout [Annotation]) -> Void) {
        let before = annotations
        change(&annotations)
        recordChange(from: before)
    }

    // MARK: Zoom

    static let zoomRange: ClosedRange<CGFloat> = 0.1...8
    func zoomIn() { zoom = (displayedZoom * 1.25).clamped(to: Self.zoomRange) }
    func zoomOut() { zoom = (displayedZoom / 1.25).clamped(to: Self.zoomRange) }
    func zoomToFit() { zoom = nil }

    // MARK: Output

    var rendered: CGImage { image.rendering(annotations, crop: crop, backdrop: backdrop) }

    // MARK: Inserting pictures

    /// Adds a picture as a movable, resizable object (selected, Select tool on). Big pictures are scaled to fit.
    func insertImage(_ picture: CGImage, centeredAt point: CGPoint? = nil) {
        endEditing()
        let limit = max(CGFloat(image.width), CGFloat(image.height)) * 0.6
        let scale = min(1, limit / CGFloat(max(picture.width, picture.height, 1)))
        let size = CGSize(width: (CGFloat(picture.width) * scale).rounded(), height: (CGFloat(picture.height) * scale).rounded())
        let center = point ?? CGPoint(x: image.bounds.midX, y: image.bounds.midY)
        let annotation = Annotation(shape: .image(rect: CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                                                               width: size.width, height: size.height), image: picture),
                                    color: color, width: 0)
        edit { $0.append(annotation) }
        tool = .select
        select(annotation.id)
    }

    /// Inserts every picture on `pasteboard`: image files (copied in Finder or dropped) or image data.
    /// Returns how many were inserted. Several are fanned out a little so they don't stack exactly.
    @discardableResult
    func insertImages(from pasteboard: NSPasteboard, centeredAt point: CGPoint? = nil) -> Int {
        let files = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? [])
            .compactMap { CGImage.load(from: $0) }
        let pictures = !files.isEmpty ? files : (pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage] ?? [])
            .compactMap { $0.cgImage(forProposedRect: nil, context: nil, hints: nil) }
        let start = point ?? CGPoint(x: image.bounds.midX, y: image.bounds.midY)
        for (i, picture) in pictures.enumerated() {
            insertImage(picture, centeredAt: CGPoint(x: start.x + CGFloat(i) * 24, y: start.y + CGFloat(i) * 24))
        }
        return pictures.count
    }

    func copy() {
        endEditing()
        ImageExport.copy(rendered)
        onFinish?()
    }

    func save() {
        endEditing()
        do {
            try ImageExport.save(rendered, to: AppSettings.shared.saveFolder)
            onFinish?()
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
