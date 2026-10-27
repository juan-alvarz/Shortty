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

    let model: EditorModel

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
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: EditorView(model: model))

        model.onFinish = { [weak self] notice in // the window goes away, so the notice floats where it was
            guard let self, let frame = self.window?.frame else { return }
            close()
            FloatingToast.show(notice, near: frame)
        }
        model.onInsertCapture = { [weak self] in self?.captureAndInsert() }
        model.onTextCard = { [weak self] area in self?.makeTextCard(from: area) }
        model.onPin = { [weak self] image in
            PinWindow.pin(image, near: self?.window?.frame)
            self?.close()
        }
        _ = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in // lives as long as the app
            guard let self, event.window === self.window else { return event }
            return self.handle(event) ? nil : event
        }
        // Holding ⌘ alone shows each tool's key on its button.
        _ = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            self.modifiersChanged(event)
            return event
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.showsShortcutHints = false }
        }
        fitLayout()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    /// Loads a new image (edits reset) and brings the window up. `file`: where it's kept in the capture history.
    func show(_ image: CGImage, file: URL? = nil) {
        guard let window else { return }
        model.load(image, from: file)
        window.setContentSize(Self.size(for: image, layout: AppSettings.shared.editorLayout))
        if !window.isVisible { window.center() }
        present()
    }

    var canReopen: Bool { model.hasImage || CaptureHistory.shared.latest != nil }

    /// "Capture New Area" in the insert menu: steps aside so the editor isn't in the way, then adds the capture.
    func captureAndInsert() {
        window?.orderOut(nil)
        Task {
            let picture = await ScreenCapture.captureRegion()
            present()
            if let picture { model.insertImage(picture) }
        }
    }

    /// Text Card: reads the area's text with its colors, lets the card be tuned in a sheet, then opens it as a new
    /// capture (kept in the history; the screenshot keeps its edits there too).
    func makeTextCard(from area: CGRect) {
        guard let window else { return }
        let image = model.textCardSource
        model.toast = "Reading text…"
        Task {
            let found = await Task.detached(priority: .userInitiated) { TextRecognition.styledText(in: image, rect: area) }.value
            guard let found else {
                model.toast = "No text found there"
                return
            }
            model.toast = nil
            guard window.isVisible, let card = await TextCardPanel.edit(found, over: window) else { return } // closed while reading
            CaptureHistory.shared.store(card)
            show(card, file: CaptureHistory.shared.latest)
            model.tool = .select
        }
    }

    /// Brings back the last capture with its edits; after a relaunch, the last capture from disk.
    func reopen() {
        if model.hasImage {
            present()
        } else if let file = CaptureHistory.shared.latest, let image = CGImage.load(from: file) {
            show(image, file: file)
        }
    }

    /// Shows the panel on top with keyboard focus. Deliberately no `NSApp.activate()` before it: a non-activating panel
    /// can only take focus while Shortty is a background process, and a half-granted activation makes it "foreground"
    /// without focus (WindowServer: "a foreground app can't steal keyboard focus"). `AppPresence` activates afterwards.
    private func present() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    /// Natural size (1 image px = 1 screen px) plus the layout's bars, clamped to 85% of the screen.
    private static func size(for image: CGImage, layout: EditorLayout) -> NSSize {
        let screen = NSScreen.main
        let scale = screen?.backingScaleFactor ?? 2
        let maxSize = (screen?.visibleFrame.size ?? NSSize(width: 1440, height: 900)).applying(.init(scaleX: 0.85, y: 0.85))
        let historyHeight = HistoryStrip.height(for: CaptureHistory.shared)
        let natural = NSSize(width: CGFloat(image.width) / scale + 32 + layout.chrome.width,
                             height: CGFloat(image.height) / scale + 32 + layout.chrome.height + historyHeight)
        return NSSize(width: max(layout.minWidth, min(natural.width, maxSize.width)), height: max(320, min(natural.height, maxSize.height)))
    }

    /// Keeps the window at least as wide as the current layout needs, also when the setting changes while it's open.
    private func fitLayout() {
        let minWidth = withObservationTracking { AppSettings.shared.editorLayout.minWidth } onChange: { [weak self] in
            Task { @MainActor in self?.fitLayout() }
        }
        guard let window else { return }
        window.contentMinSize = NSSize(width: minWidth, height: 320)
        let size = window.contentLayoutRect.size
        if size.width < minWidth { window.setContentSize(NSSize(width: minWidth, height: size.height)) }
    }

    private static let toolKeys: [String: EditorModel.Tool] = [
        "v": .select, "p": .pencil, "a": .arrow, "t": .text, "r": .rectangle, "o": .ellipse,
        "m": .magnifier, "b": .blur, "s": .spotlight, "x": .recognizeText, "n": .step, "k": .textCard, "c": .crop,
    ]

    /// Holding ⌘ alone shows each tool's key on its button. Internal for the self-check.
    func modifiersChanged(_ event: NSEvent) {
        model.showsShortcutHints = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
    }

    /// When Esc was last pressed: a second press within the double-click time closes the editor.
    private var lastEscape: Date?

    /// The capture's edits are on disk before the window goes away (they also save on their own as you work).
    override func close() {
        model.saveEdits()
        super.close()
    }

    /// Editor shortcuts. Returns false to let the event through (e.g. to the text being typed). Internal for the self-check.
    func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let isEscape = Int(event.keyCode) == kVK_Escape
        let doubleEscape = isEscape && lastEscape.map { Date.now.timeIntervalSince($0) < NSEvent.doubleClickInterval } == true
        lastEscape = isEscape && !doubleEscape ? .now : nil

        // While typing text, keys go to the text (Esc finishes it). ⌘S still saves; ⌘C copies the image unless text is selected.
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
            case "c" where model.tool == .recognizeText && model.hasTextSelection: model.copySelectedText?()
            case "c": model.copy()
            case "s": model.save()
            case "w": close()
            case "v": if model.insertImages(from: .general) == 0 { model.toast = "No picture on the clipboard" }
            case "z": flags.contains(.shift) ? model.redo() : model.undo()
            case "d": model.duplicateSelection()
            case "]": model.bringSelectionToFront()
            case "[": model.sendSelectionToBack()
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
        case kVK_Escape where doubleEscape:
            close()
        case kVK_Escape:
            // Back to the plain pointer: a tool → Select; on Select, deselect. Once never closes the window
            // (consumed, so the panel doesn't treat it as cancel either).
            if model.tool != .select { model.tool = .select } else { model.select(nil) }
        case kVK_Return where model.tool == .crop, kVK_ANSI_KeypadEnter where model.tool == .crop:
            model.applyCrop()
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
