import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A panel that takes keyboard focus without activating Shortty. Since macOS 14 a background app can't make
/// itself active, so a plain window opened after a capture would land behind the frontmost app.
private final class EditorPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The single editor window. A new capture replaces the content instead of opening another window.
final class EditorWindowController: NSWindowController {
    static let shared = EditorWindowController()
    private static let toolbarHeight: CGFloat = 52

    let model: EditorModel
    private var keyMonitor: Any?

    private init() {
        model = EditorModel(image: Self.placeholder)
        let window = EditorPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 720, height: 480)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false)
        super.init(window: window)
        window.hidesOnDeactivate = false // stay up when another app is clicked

        window.title = "Shortty"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.isMovableByWindowBackground = false // otherwise AppKit drags the window instead of drawing
        window.contentMinSize = NSSize(width: 720, height: 320)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: EditorView(model: model))

        model.onFinish = { [weak self] in self?.close() }
        model.onInsertCapture = { [weak self] in self?.captureAndInsert() }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            return self.handle(event) ? nil : event
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    /// Loads a new image (edits reset) and brings the window up.
    func show(_ image: CGImage) {
        guard let window else { return }
        model.load(image)
        window.setContentSize(Self.size(for: image))
        if !window.isVisible { window.center() }
        present()
    }

    var canReopen: Bool { model.hasImage || LastCapture.exists }

    /// "Capture New Area" in the insert menu: steps aside so the editor isn't in the way, then adds the capture.
    func captureAndInsert() {
        window?.orderOut(nil)
        Task {
            let picture = await ScreenCapture.captureRegion(keepAsLast: false)
            present()
            if let picture { model.insertImage(picture) }
        }
    }

    /// Brings back the last capture with its edits; after a relaunch, the last capture from disk.
    func reopen() {
        if model.hasImage {
            present()
        } else if let image = LastCapture.load() {
            show(image)
        }
    }

    /// Shows the panel on top with keyboard focus. Deliberately no `NSApp.activate()`: a non-activating panel can only
    /// take focus while Shortty is a background process, and a half-granted activation makes it "foreground" without
    /// focus (WindowServer: "a foreground app can't steal keyboard focus").
    private func present() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    /// Natural size (1 image px = 1 screen px) plus toolbar, clamped to 85% of the screen.
    private static func size(for image: CGImage) -> NSSize {
        let screen = NSScreen.main
        let scale = screen?.backingScaleFactor ?? 2
        let maxSize = (screen?.visibleFrame.size ?? NSSize(width: 1440, height: 900)).applying(.init(scaleX: 0.85, y: 0.85))
        let natural = NSSize(width: CGFloat(image.width) / scale + 32, height: CGFloat(image.height) / scale + 32 + toolbarHeight)
        return NSSize(width: max(720, min(natural.width, maxSize.width)), height: max(320, min(natural.height, maxSize.height)))
    }

    private static let toolKeys: [String: EditorModel.Tool] = [
        "v": .select, "p": .pencil, "a": .arrow, "t": .text, "r": .rectangle, "o": .ellipse,
        "m": .magnifier, "b": .blur, "s": .spotlight, "x": .recognizeText,
    ]

    /// Editor shortcuts. Returns false to let the event through (e.g. to the text being typed). Internal for the self-check.
    func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

        // While typing text, keys go to the text. ⌘S still saves; ⌘C copies the image unless text is selected.
        if model.editingID != nil {
            let hasTextSelection = ((window?.firstResponder as? NSTextView)?.selectedRange().length ?? 0) > 0
            switch (flags.contains(.command), key) {
            case (true, "s"): model.save()
            case (true, "c") where !hasTextSelection: model.copy()
            default: return false
            }
            return true
        }

        if flags.contains(.command) {
            switch key {
            case "c": model.copy()
            case "s": model.save()
            case "v": if model.insertImages(from: .general) == 0 { model.toast = "No picture on the clipboard" }
            case "z": flags.contains(.shift) ? model.redo() : model.undo()
            case "=", "+": model.zoomIn()
            case "-": model.zoomOut()
            case "0": model.zoomToFit()
            default: return false
            }
            return true
        }

        let hasSelection = model.selection != nil
        let step: CGFloat = flags.contains(.shift) ? 10 : 1
        switch Int(event.keyCode) {
        case kVK_Escape:
            // Back to the plain pointer: a tool → Select; on Select, deselect. Never closes the window
            // (consumed, so the panel doesn't treat it as cancel either).
            if model.tool != .select { model.tool = .select } else { model.select(nil) }
        case kVK_Delete where hasSelection, kVK_ForwardDelete where hasSelection:
            model.deleteSelection()
        case kVK_LeftArrow where hasSelection: model.nudgeSelection(by: CGPoint(x: -step, y: 0))
        case kVK_RightArrow where hasSelection: model.nudgeSelection(by: CGPoint(x: step, y: 0))
        case kVK_UpArrow where hasSelection: model.nudgeSelection(by: CGPoint(x: 0, y: -step))
        case kVK_DownArrow where hasSelection: model.nudgeSelection(by: CGPoint(x: 0, y: step))
        default:
            guard flags.isDisjoint(with: [.option, .control]), let tool = Self.toolKeys[key] else { return false }
            model.tool = tool
        }
        return true
    }

    private static let placeholder: CGImage = {
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }()
}
