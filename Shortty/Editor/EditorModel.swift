import AppKit
import Observation
import SwiftUI

@Observable
final class EditorModel {
    enum Tool { case select, pencil, arrow, text, rectangle, ellipse, step, magnifier, blur, spotlight, recognizeText, crop }

    private(set) var image: CGImage
    /// False until the first capture/image is loaded (the window starts with a 1px placeholder).
    private(set) var hasImage = false
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

    static func widthRange(for tool: Tool) -> ClosedRange<CGFloat> {
        switch tool {
        case .text: 12...120
        case .blur: 4...40
        case .spotlight: 20...90
        case .step: 16...96
        default: 2...24
        }
    }
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

    init(image: CGImage) { self.image = image }

    /// Replaces the image for a new capture and resets edits.
    func load(_ image: CGImage) {
        self.image = image
        hasImage = true
        annotations = []
        selection = nil
        crop = nil
        cropBox = nil
        undoStack = []
        redoStack = []
        zoom = nil
    }

    /// The image plus anything drawn past its edges, in image pixels.
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
        return tool != .select && tool != .recognizeText
    }
    var showsArrowStyles: Bool { optionsTool == .arrow }
    var showsTextStyles: Bool { optionsTool == .text }
    /// Erase has nothing to adjust.
    var showsWidthSlider: Bool { optionsTool != .crop && (optionsTool != .blur || redactStyle.usesStrength) } // crop has buttons instead
    var currentWidthRange: ClosedRange<CGFloat> { Self.widthRange(for: optionsTool) }

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

    /// Recognize Text mode: copies the text inside `rect` to the clipboard and says so in a toast.
    func recognizeText(in rect: CGRect) {
        let pasteboard = textPasteboard
        let area = rect.standardized.integral.intersection(image.bounds)
        guard !area.isNull, area.width >= 4, area.height >= 4, let crop = image.cropping(to: area) else { return }
        toast = "Reading text…"
        let job = SendableImage(image: crop)
        Task {
            let lines = await Task.detached(priority: .userInitiated) { TextRecognition.lines(in: job.image) }.value
            guard !lines.isEmpty else {
                toast = "No text found"
                return
            }
            pasteboard.clearContents()
            pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
            toast = "Copied \(lines.count == 1 ? "1 line" : "\(lines.count) lines") of text"
        }
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
        guard let i = selectedIndex else { return }
        if undoable {
            edit { $0[i].width = width }
        } else {
            annotations[i].width = width
        }
    }

    // Index looked up before `edit` starts: reading `annotations` inside its inout access would be an exclusivity violation.

    /// `undoable: false` for live slider drags; the caller records one step with `recordChange(from:)` at the end.
    func setColor(_ newColor: Color, undoable: Bool = true) {
        color = newColor
        guard let i = selectedIndex else { return }
        if undoable {
            edit { $0[i].color = newColor }
        } else {
            annotations[i].color = newColor
        }
    }

    func deleteSelection() {
        guard let i = selectedIndex else { return }
        edit { $0.remove(at: i) }
        selection = nil
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

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(Snapshot(annotations: annotations, crop: crop))
        restore(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(Snapshot(annotations: annotations, crop: crop))
        restore(next)
    }

    private func restore(_ snapshot: Snapshot) {
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
    static func clampZoom(_ zoom: CGFloat) -> CGFloat { zoom.clamped(to: zoomRange) }
    func zoomIn() { zoom = Self.clampZoom(displayedZoom * 1.25) }
    func zoomOut() { zoom = Self.clampZoom(displayedZoom / 1.25) }
    func zoomToFit() { zoom = nil }

    // MARK: Output

    var rendered: CGImage {
        let content = image.rendering(annotations, crop: crop)
        return backdrop.map(content.addingBackdrop) ?? content
    }

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
        let before = annotations
        annotations.append(annotation)
        recordChange(from: before)
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
