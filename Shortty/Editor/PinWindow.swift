import AppKit
import Carbon.HIToolbox

/// A screenshot floating above every window ("pin to screen"). Drag to move, scroll or pinch to resize,
/// double-click or Esc to close; right-click for Copy / Save / Close. Several can be pinned at once.
final class PinWindow: NSPanel {
    private static var open: [PinWindow] = []
    private let image: CGImage

    /// Pins `image` at its natural size (clamped to the screen), centered on `near` when given.
    @discardableResult
    static func pin(_ image: CGImage, near frame: NSRect? = nil) -> PinWindow {
        let screen = NSScreen.screens.first { $0.frame.intersects(frame ?? .zero) } ?? NSScreen.main ?? NSScreen.screens[0]
        let scale = screen.backingScaleFactor
        var size = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let limit = screen.visibleFrame.size.applying(.init(scaleX: 0.8, y: 0.8))
        let fit = min(limit.width / size.width, limit.height / size.height, 1)
        size = NSSize(width: size.width * fit, height: size.height * fit)
        let center = frame.map { CGPoint(x: $0.midX, y: $0.midY) } ?? CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY)
        let window = PinWindow(image: image, frame: NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height))
        open.append(window)
        window.orderFrontRegardless()
        window.makeKey()
        return window
    }

    private init(image: CGImage, frame: NSRect) {
        self.image = image
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        isMovableByWindowBackground = true
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentAspectRatio = frame.size
        let view = PinView(image: image)
        view.onClose = { [weak self] in self?.close() }
        contentView = view
    }

    override var canBecomeKey: Bool { true }

    override func close() {
        super.close()
        Self.open.removeAll { $0 === self }
    }

    /// Resize around a point (scroll / pinch), keeping proportions and a sensible size.
    func resize(by factor: CGFloat, around point: CGPoint) {
        let old = frame
        let natural = CGFloat(image.width) / (screen?.backingScaleFactor ?? 2)
        let width = min(max(old.width * factor, 80), natural * 4)
        let height = width * old.height / old.width
        let fx = (point.x - old.minX) / old.width, fy = (point.y - old.minY) / old.height
        setFrame(NSRect(x: point.x - width * fx, y: point.y - height * fy, width: width, height: height), display: true)
    }

    override func keyDown(with event: NSEvent) {
        let command = event.modifierFlags.contains(.command)
        switch (command, event.charactersIgnoringModifiers?.lowercased() ?? "") {
        case (true, "c"): ImageExport.copy(image)
        case (true, "s"): _ = try? ImageExport.save(image, to: AppSettings.shared.saveFolder)
        case (true, "w"): close()
        case (false, _) where Int(event.keyCode) == kVK_Escape: close()
        default: super.keyDown(with: event)
        }
    }
}

private final class PinView: NSView {
    private let image: CGImage
    var onClose: (() -> Void)?

    init(image: CGImage) {
        self.image = image
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        toolTip = "Drag to move · scroll to resize · double-click or Esc to close"
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override var mouseDownCanMoveWindow: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.interpolationQuality = .high
        context.draw(image, in: bounds)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onClose?() } else { super.mouseDown(with: event) }
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.isDirectionInvertedFromDevice ? -event.scrollingDeltaY : event.scrollingDeltaY
        guard delta != 0, let window = window as? PinWindow else { return }
        let factor = event.hasPreciseScrollingDeltas ? exp(delta * 0.01) : (delta > 0 ? 1.1 : 1 / 1.1)
        window.resize(by: factor, around: NSEvent.mouseLocation)
    }

    override func magnify(with event: NSEvent) {
        (window as? PinWindow)?.resize(by: 1 + event.magnification, around: NSEvent.mouseLocation)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "Copy", action: #selector(copyImage), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Save", action: #selector(saveImage), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Close", action: #selector(closePin), keyEquivalent: "").target = self
        return menu
    }

    @objc private func copyImage() { ImageExport.copy(image) }
    @objc private func saveImage() { _ = try? ImageExport.save(image, to: AppSettings.shared.saveFolder) }
    @objc private func closePin() { onClose?() }
}
