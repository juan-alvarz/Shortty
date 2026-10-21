import AppKit
import Carbon.HIToolbox

/// Full-screen crosshair overlay to drag out a rectangle, without stealing focus from the frontmost app.
/// Returns the rectangle in global AppKit coordinates (bottom-left origin), or nil on Esc / right-click.
enum RegionSelector {
    static func select() async -> CGRect? {
        await withCheckedContinuation { continuation in
            SelectionSession { continuation.resume(returning: $0) }.begin()
        }
    }
}

/// Borderless panel that takes keyboard focus (for Esc) without activating Shortty.
private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    convenience init(screen: NSScreen) {
        self.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        setFrame(screen.frame, display: false)
    }
}

private final class SelectionSession {
    private static var active: SelectionSession? // keeps the session alive while on screen
    private var panels: [OverlayPanel] = []
    private var finish: ((CGRect?) -> Void)?

    init(finish: @escaping (CGRect?) -> Void) { self.finish = finish }

    func begin() {
        Self.active = self
        let mouse = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            let panel = OverlayPanel(screen: screen)
            let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.onFinish = { [weak self, weak panel] rect in
                self?.end(rect.flatMap { panel?.convertToScreen($0) })
            }
            panel.contentView = view
            panels.append(panel)
            if NSMouseInRect(mouse, screen.frame, false) {
                panel.makeKeyAndOrderFront(nil)
                panel.makeFirstResponder(view)
            } else {
                panel.orderFrontRegardless()
            }
        }
        NSCursor.crosshair.set()
    }

    private func end(_ rect: CGRect?) {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        NSCursor.arrow.set()
        let finish = self.finish
        self.finish = nil
        Self.active = nil
        finish?(rect)
    }
}

private final class SelectionView: NSView {
    var onFinish: ((CGRect?) -> Void)?
    private var anchor: CGPoint?
    private var selection: CGRect?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect], owner: self))
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }
    override func mouseMoved(with event: NSEvent) { NSCursor.crosshair.set() }

    override func keyDown(with event: NSEvent) {
        if Int(event.keyCode) == kVK_Escape { onFinish?(nil) } else { super.keyDown(with: event) }
    }

    override func rightMouseDown(with event: NSEvent) { onFinish?(nil) }

    override func mouseDown(with event: NSEvent) {
        anchor = point(of: event)
        selection = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let anchor else { return }
        let point = point(of: event)
        selection = CGRect(x: min(anchor.x, point.x), y: min(anchor.y, point.y),
                           width: abs(point.x - anchor.x), height: abs(point.y - anchor.y)).integral
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let selection, selection.width >= 4, selection.height >= 4 else {
            // A click, not a drag: keep selecting.
            anchor = nil
            selection = nil
            needsDisplay = true
            return
        }
        onFinish?(selection)
    }

    /// Clamped to this screen: a selection never spans displays.
    private func point(of event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: min(max(point.x, 0), bounds.width), y: min(max(point.y, 0), bounds.height))
    }

    override func draw(_ dirtyRect: NSRect) {
        let dim = NSBezierPath(rect: bounds)
        if let selection {
            dim.append(NSBezierPath(rect: selection))
            dim.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(0.35).setFill()
        dim.fill()

        guard let selection else {
            drawPill("Drag to select the lazy shot area   ·   Esc to cancel") { size in
                CGPoint(x: (self.bounds.width - size.width) / 2, y: (self.bounds.height - size.height) / 2)
            }
            return
        }
        NSColor(Theme.accent).setStroke()
        let border = NSBezierPath(rect: selection.insetBy(dx: -0.75, dy: -0.75))
        border.lineWidth = 1.5
        border.stroke()

        let scale = window?.backingScaleFactor ?? 1
        drawPill("\(Int(selection.width * scale)) × \(Int(selection.height * scale))") { size in
            // Under the bottom-right corner, or inside it when there's no room.
            let below = selection.minY - size.height - 6
            return CGPoint(x: max(selection.maxX - size.width, 0), y: below >= 0 ? below : selection.minY + 6)
        }
    }
}

// MARK: - Countdown

/// Click-through outline of the lazy region with the seconds left. Hidden before the capture runs.
final class CountdownOverlay {
    private let panel: NSPanel
    private let view: CountdownView

    init(region: CGRect) {
        let screen = NSScreen.screens.first { $0.frame.intersects(region) } ?? NSScreen.screens[0]
        panel = OverlayPanel(screen: screen)
        panel.ignoresMouseEvents = true
        view = CountdownView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.region = region.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        panel.contentView = view
        panel.orderFrontRegardless()
    }

    func show(_ seconds: Int) {
        view.seconds = seconds
        view.needsDisplay = true
    }

    func close() { panel.orderOut(nil) }
}

private final class CountdownView: NSView {
    var region: CGRect = .zero
    var seconds = 0

    override func draw(_ dirtyRect: NSRect) {
        let outline = NSBezierPath(rect: region.insetBy(dx: -2, dy: -2))
        outline.lineWidth = 2
        outline.setLineDash([6, 4], count: 2, phase: 0)
        NSColor(Theme.accent).setStroke()
        outline.stroke()

        drawPill("\(seconds)", font: .monospacedDigitSystemFont(ofSize: 15, weight: .bold), fill: NSColor(Theme.accent)) { size in
            // Above the top-left corner, else below the region, else inside it.
            let above = self.region.maxY + 8
            let below = self.region.minY - 8 - size.height
            let y = above + size.height <= self.bounds.height ? above : below >= 0 ? below : self.region.maxY - size.height - 8
            return CGPoint(x: max(self.region.minX - 2, 0), y: y)
        }
    }
}
