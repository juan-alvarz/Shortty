// Drives the real editor views with synthetic mouse/scroll events and checks the results.
// Run via Scripts/selfcheck.sh. Add a check here for every new editor behavior.
import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
@main
struct SelfCheck {
    static var failures = 0
    static var snapshotDir: String?

    static func check(_ ok: Bool, _ label: String) {
        print(ok ? "PASS" : "FAIL", label)
        if !ok { failures += 1 }
    }
    static func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 1.5) -> Bool { abs(a - b) <= tolerance }
    static func spin(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
    static func snapshot(_ view: NSView, _ name: String) {
        guard let snapshotDir else { return }
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(snapshotDir)/\(name)"))
    }
    static func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for sub in view.subviews { if let match = find(type, in: sub) { return match } }
        return nil
    }
    static func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        return data
    }

    /// A fake dark "screenshot": panel with text-like bars.
    static func fixture() -> CGImage {
        let context = CGContext(data: nil, width: 1000, height: 640, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(gray: 0.12, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 1000, height: 640))
        context.setFillColor(gray: 0.2, alpha: 1)
        context.fill(CGRect(x: 80, y: 80, width: 840, height: 480))
        context.setFillColor(gray: 0.7, alpha: 1)
        for i in 0..<12 { context.fill(CGRect(x: 120, y: 120 + i * 32, width: 260 + (i * 53) % 420, height: 10)) }
        // Real text for Vision, on the dark band under the panel (top-left y ≈ 572–602).
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        ("Hello Shortty 42" as NSString).draw(at: CGPoint(x: 120, y: 38),
                                              withAttributes: [.font: NSFont.systemFont(ofSize: 28, weight: .bold), .foregroundColor: NSColor.white])
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()!
    }

    static func main() {
        NSApplication.shared.setActivationPolicy(.accessory)
        let repo = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath
        snapshotDir = CommandLine.arguments.count > 2 && !CommandLine.arguments[2].isEmpty ? CommandLine.arguments[2] : nil
        let image = fixture()

        check(ScreenCapture.rectArgument(CGRect(x: 100, y: 200, width: 300, height: 400), primaryHeight: 1000) == "100,400,300,400", "rect argument flips y")

        let model = EditorModel(image: image)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = true
        window.contentView = NSHostingView(rootView: EditorView(model: model))
        window.setFrameOrigin(.zero) // window coordinates == screen coordinates for synthetic events
        window.orderFrontRegardless()
        spin(1)
        let scroll = find(CanvasScrollView.self, in: window.contentView!)!
        let canvas = scroll.documentView!
        let fit = scroll.magnification
        check(model.zoom == nil && fit > 0 && fit <= 1, "starts fitted")

        // MARK: Zoom
        let pointer = CGPoint(x: scroll.convert(scroll.bounds, to: nil).midX + 150, y: scroll.convert(scroll.bounds, to: nil).midY - 80)
        func wheel(_ lines: Int32, command: Bool = true) {
            let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0)!
            event.flags = command ? .maskCommand : [] // explicit: otherwise the live keyboard state (e.g. a held ⌘) leaks in
            event.location = CGPoint(x: pointer.x, y: NSScreen.screens[0].frame.height - pointer.y)
            scroll.scrollWheel(with: NSEvent(cgEvent: event)!)
            spin(0.15)
        }
        let before = canvas.convert(pointer, from: nil)
        wheel(1); wheel(1)
        let after = canvas.convert(pointer, from: nil)
        check(near(scroll.magnification, fit * 1.5625, 0.01) && hypot(before.x - after.x, before.y - after.y) < 1.5, "⌘+wheel zooms in, anchored at pointer")
        wheel(-1)
        check(near(scroll.magnification, fit * 1.25, 0.01), "⌘+wheel down zooms out")
        let zoomBefore = scroll.magnification
        wheel(-3, command: false)
        check(scroll.magnification == zoomBefore, "plain wheel scrolls, no zoom")
        model.zoomToFit(); spin(0.2)
        check(near(scroll.magnification, fit, 0.001), "⌘0 fits")

        // MARK: Mouse helpers (image pixel coordinates)
        // The canvas can grow past the image, so its top-left isn't always image pixel (0,0).
        // A drag keeps the mapping it started with, like the editor keeps the canvas still mid-drag.
        var frozenCanvas: CGRect?
        func toWindow(_ px: CGPoint) -> CGPoint {
            let area = frozenCanvas ?? model.canvasRect
            let pixelsPerPoint = area.width / canvas.bounds.width
            return canvas.convert(CGPoint(x: (px.x - area.minX) / pixelsPerPoint, y: (px.y - area.minY) / pixelsPerPoint), to: nil)
        }
        func mouse(_ type: NSEvent.EventType, _ px: CGPoint, _ flags: NSEvent.ModifierFlags = [], clicks: Int = 1) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: toWindow(px), modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber,
                               context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
        }
        func click(_ px: CGPoint, clicks: Int = 1) {
            canvas.mouseDown(with: mouse(.leftMouseDown, px, clicks: clicks))
            canvas.mouseUp(with: mouse(.leftMouseUp, px, clicks: clicks))
            spin(0.2)
        }
        func drag(_ from: CGPoint, _ to: CGPoint, _ flags: NSEvent.ModifierFlags = []) {
            frozenCanvas = model.canvasRect
            defer { frozenCanvas = nil }
            canvas.mouseDown(with: mouse(.leftMouseDown, from, flags))
            for i in 1...10 {
                let t = CGFloat(i) / 10
                canvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t), flags))
            }
            canvas.mouseUp(with: mouse(.leftMouseUp, to, flags))
            spin(0.1)
        }
        func bounds(_ i: Int) -> CGRect { model.annotations[i].bounds }

        // MARK: Pencil + shapes
        model.tool = .pencil
        let origin = window.frame.origin
        drag(CGPoint(x: 100, y: 450), CGPoint(x: 250, y: 520))
        check(model.annotations.count == 1 && model.annotations[0].isStroke && model.selection == nil, "pencil draws a stroke, not selected")
        check(window.frame.origin == origin, "drawing does not move the window")

        model.tool = .rectangle
        drag(CGPoint(x: 200, y: 150), CGPoint(x: 400, y: 260), .shift)
        check(model.annotations.count == 2 && near(bounds(1).width, 200) && near(bounds(1).height, 200), "Shift rectangle is square")
        check(model.selection == model.annotations[1].id, "new rectangle is selected")
        drag(CGPoint(x: 400, y: 350), CGPoint(x: 500, y: 400))
        check(near(bounds(1).minX, 200) && near(bounds(1).minY, 150) && near(bounds(1).width, 300) && near(bounds(1).height, 250), "handle resize keeps opposite corner")
        drag(CGPoint(x: 500, y: 400), CGPoint(x: 600, y: 420), .shift)
        check(near(bounds(1).width / bounds(1).height, 1.2, 0.02) && model.annotations.count == 2, "Shift corner resize keeps aspect")

        model.tool = .ellipse
        drag(CGPoint(x: 650, y: 300), CGPoint(x: 750, y: 360))
        let ellipse = model.annotations[2]
        check(near(ellipse.bounds.width, 100) && near(ellipse.bounds.height, 60), "ellipse drawn 100×60")
        check(ellipse.contains(CGPoint(x: 700, y: 300), tolerance: 3) && !ellipse.contains(CGPoint(x: 700, y: 330), tolerance: 3), "ellipse hit test: outline only")

        model.tool = .rectangle
        drag(CGPoint(x: 50, y: 50), CGPoint(x: 50, y: 50))
        check(model.annotations.count == 3, "click without drag adds no shape")

        // MARK: Select, move, recolor, nudge, delete, undo/redo
        model.tool = .select
        let strokeBefore = bounds(0)
        drag(CGPoint(x: 175, y: 485), CGPoint(x: 205, y: 505))
        check(model.selection == model.annotations[0].id && near(bounds(0).minX, strokeBefore.minX + 30) && near(bounds(0).minY, strokeBefore.minY + 20), "select tool picks and moves the stroke")
        let blue = Theme.palette[5]
        model.setColor(blue)
        check(model.annotations[0].color == blue && model.annotations[1].color == Theme.accent, "color recolors only the selection")
        let beforeNudge = bounds(0)
        model.nudgeSelection(by: CGPoint(x: 10, y: 0))
        model.deleteSelection()
        check(model.annotations.count == 2 && model.selection == nil, "delete removes it")
        model.undo()
        model.undo()
        check(model.annotations.count == 3 && near(bounds(0).minX, beforeNudge.minX), "undo restores delete, then nudge")
        model.redo(); model.redo()
        check(model.annotations.count == 2, "redo re-applies")
        model.undo(); model.undo(); model.undo()
        check(model.annotations[0].color == Theme.accent, "undo reverts recolor")
        model.select(model.annotations[1].id)
        drag(CGPoint(x: 900, y: 100), CGPoint(x: 900, y: 100))
        check(model.selection == nil, "click on empty space deselects")

        // MARK: Pencil + Shift
        model.tool = .pencil
        drag(CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 180), .shift)
        if case .stroke(let points) = model.annotations.last!.shape {
            check(points.count == 3 && near(points.last!.x, 300) && near(points.last!.y, 180), "Shift pencil draws one straight segment")
        }
        canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 100, y: 300)))
        for i in 1...5 { canvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 100 + CGFloat(i) * 10, y: 300 + CGFloat(i * i)))) }
        for i in 1...5 { canvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 150 + CGFloat(i) * 30, y: 325 - CGFloat(i) * 7), .shift)) }
        for i in 1...3 { canvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 300 + CGFloat(i) * 5, y: 290 + CGFloat(i * 4)))) }
        canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 315, y: 302)))
        spin(0.1)
        if case .stroke(let points) = model.annotations.last!.shape {
            check(points.count == 11 && near(points[7].x, 300) && near(points[7].y, 290), "freehand → Shift straight → freehand")
        }

        // MARK: Color picker model
        model.select(model.annotations.last!.id)
        let originalColor = model.annotations.last!.color
        let beforeColorDrag = model.annotations
        for value in stride(from: 0.0, through: 255, by: 51) { model.setColor(Color(rgb: [value, 40, 200]), undoable: false) }
        model.recordChange(from: beforeColorDrag)
        check(model.annotations.last!.color.hex == "#FF28C8", "slider drag recolors live")
        model.undo()
        check(model.annotations.last!.color.hex == originalColor.hex, "one undo reverts a whole slider drag")
        check(Color(hex: "#ff6b3d")?.hex == "#FF6B3D" && Color(hex: "fff")?.hex == "#FFFFFF" && Color(hex: "zzz") == nil, "hex parsing")

        // MARK: Arrows
        model.select(nil)
        model.tool = .arrow
        spin(0.2)
        check(model.showsOptions && model.showsArrowStyles, "arrow tool shows thickness and styles")
        let countBeforeArrow = model.annotations.count
        drag(CGPoint(x: 500, y: 500), CGPoint(x: 700, y: 440))
        let arrowIndex = model.annotations.count - 1
        guard case .arrow(let start, let end, let bend, let style) = model.annotations[arrowIndex].shape else {
            check(false, "arrow tool draws an arrow")
            finish()
        }
        check(model.annotations.count == countBeforeArrow + 1 && near(start.x, 500) && near(end.x, 700) && near(end.y, 440) && bend == 0 && style == .line,
              "arrow drawn straight, line style")
        check(model.selection == model.annotations[arrowIndex].id && model.annotations[arrowIndex].width == 6, "new arrow selected, default width 6")

        drag(CGPoint(x: 500, y: 560), CGPoint(x: 700, y: 572), .shift)
        if case .arrow(_, let snappedEnd, _, _) = model.annotations.last!.shape {
            check(near(snappedEnd.y, 560), "Shift snaps arrow to 0° (end y \(Int(snappedEnd.y)))")
        }
        model.undo() // drop the snapped one
        model.select(model.annotations[arrowIndex].id)

        // Bend: drag the middle grip off the line
        let middle = CGPoint(x: 600, y: 470)
        drag(middle, CGPoint(x: middle.x + 12, y: middle.y + 40))
        guard case .arrow(let s2, let e2, let bent, _) = model.annotations[arrowIndex].shape else { finish() }
        let curveMiddle = ArrowCurve(start: s2, end: e2, bend: bent).middle
        check(abs(bent) > 30 && near(s2.x, 500) && near(e2.x, 700), "middle grip bends the arrow (bend \(Int(bent)))")
        check(model.annotations[arrowIndex].contains(curveMiddle, tolerance: 2) && !model.annotations[arrowIndex].contains(middle, tolerance: 2),
              "hit test follows the curve")

        // Move the end grip
        drag(CGPoint(x: 700, y: 440), CGPoint(x: 760, y: 400))
        if case .arrow(_, let movedEnd, let keptBend, _) = model.annotations[arrowIndex].shape {
            check(near(movedEnd.x, 760) && near(movedEnd.y, 400) && keptBend == bent, "end grip moves the tip, curve kept")
        }

        // Style + width apply to the selected arrow; width drag is one undo
        model.setArrowStyle(.solid)
        if case .arrow(_, _, _, let newStyle) = model.annotations[arrowIndex].shape { check(newStyle == .solid, "style applies to selected arrow") }
        let beforeWidthDrag = model.annotations
        for width in [8.0, 12, 16] { model.setWidth(width, undoable: false) }
        model.recordChange(from: beforeWidthDrag)
        check(model.annotations[arrowIndex].width == 16, "width applies live")
        model.undo()
        check(model.annotations[arrowIndex].width == 6, "one undo reverts the width drag")
        model.undo()
        if case .arrow(_, _, _, let revertedStyle) = model.annotations[arrowIndex].shape { check(revertedStyle == .line, "undo reverts style") }

        // All four styles render and export
        model.tool = .arrow
        for (i, arrowStyle) in ArrowStyle.allCases.enumerated() {
            model.select(nil) // otherwise picking a style restyles the arrow just drawn (it stays selected)
            model.setArrowStyle(arrowStyle)
            drag(CGPoint(x: 420 + CGFloat(i) * 110, y: 150), CGPoint(x: 500 + CGFloat(i) * 110, y: 240))
        }
        let solidArrow = model.annotations[model.annotations.count - 3]
        if case .arrow(let a, let b, _, let solidStyle) = solidArrow.shape {
            let mid = CGPoint(x: (a.x + b.x) / 2 + (b.x - a.x) * 0.2, y: (a.y + b.y) / 2 + (b.y - a.y) * 0.2)
            let exported = pixel(model.rendered, Int(mid.x), Int(mid.y)).prefix(3).map(Double.init)
            let expected = solidArrow.color.rgb
            check(solidStyle == .solid && zip(exported, expected).allSatisfy { abs($0 - $1) < 8 }, "export draws the solid arrow body in its color (\(exported) vs \(expected))")
        }

        // Options bar receives clicks (it floats above the canvas)
        model.select(model.annotations.last!.id)
        spin(0.3)
        let barPoint = CGPoint(x: scroll.convert(scroll.bounds, to: nil).maxX - 60, y: scroll.convert(scroll.bounds, to: nil).maxY - 30)
        let hit = window.contentView!.hitTest(barPoint)
        check(hit != nil && !(hit!.isDescendant(of: scroll)), "clicks on the arrow options go to the panel, not the canvas")
        snapshot(window.contentView!, "editor-arrows.png")

        // MARK: Thickness for every tool
        model.select(nil)
        model.tool = .select
        check(!model.showsOptions, "select tool with nothing selected: no options panel")
        model.tool = .pencil
        check(model.showsOptions && !model.showsArrowStyles && model.currentWidth == 4, "pencil: panel with thickness only, default 4")
        model.setWidth(10)
        model.tool = .rectangle
        check(model.currentWidth == 4, "each tool keeps its own thickness")
        model.tool = .pencil
        check(model.currentWidth == 10, "pencil remembers 10")
        drag(CGPoint(x: 120, y: 580), CGPoint(x: 300, y: 600))
        check(model.annotations.last!.width == 10, "new stroke uses the pencil thickness")
        snapshot(window.contentView!, "editor-pencil-panel.png")

        model.tool = .select
        model.select(model.annotations[1].id) // the rectangle
        check(model.showsOptions && !model.showsArrowStyles && model.currentWidth == 4, "selected rectangle: slider shows its width")
        let beforeRectWidth = model.annotations
        for width in [8.0, 14] { model.setWidth(width, undoable: false) }
        model.recordChange(from: beforeRectWidth)
        check(model.annotations[1].width == 14 && model.width(for: .rectangle) == 14, "width applies to the selected rectangle and becomes the rectangle default")
        model.undo()
        check(model.annotations[1].width == 4, "one undo reverts it")

        // MARK: Export with a rectangle edge
        let rect = bounds(1)
        let edge = pixel(model.rendered, Int(rect.midX), Int(rect.minY))
        check(edge[0] > 200 && edge[2] < 120, "export has the rectangle edge in accent")

        // MARK: Text (callout / label / plain)
        model.select(nil)
        model.tool = .text
        check(model.showsOptions && model.showsTextStyles && !model.showsArrowStyles && model.currentWidth == 28 && model.currentWidthRange == 12...120,
              "text tool: size 28 (12–120) and variants")
        let countBeforeText = model.annotations.count
        click(CGPoint(x: 560, y: 380))
        let textID = model.editingID
        check(textID != nil && model.annotations.count == countBeforeText + 1 && model.selection == textID, "click starts a new callout, editing")
        guard let textID, let textEditor = find(NSTextView.self, in: canvas) else {
            check(false, "inline editor appears")
            finish()
        }
        check(window.firstResponder === textEditor, "inline editor has keyboard focus")
        textEditor.insertText("Icon here", replacementRange: NSRange(location: NSNotFound, length: 0))
        spin(0.2)
        func text() -> Annotation { model.annotations.first { $0.id == textID }! }
        if case .text(_, let string, let style, _) = text().shape { check(string == "Icon here" && style == .callout, "typing updates the callout") }
        let pixelsPerPoint = CGFloat(image.width) / canvas.bounds.width
        let typedLayout = text().textBox!
        check(near(textEditor.frame.minX, typedLayout.textRect.minX / pixelsPerPoint, 0.5) && near(textEditor.frame.minY, typedLayout.textRect.minY / pixelsPerPoint, 0.5),
              "editor sits exactly on the drawn text")

        textEditor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        spin(0.2)
        check(model.editingID == nil && model.selection == textID && find(NSTextView.self, in: canvas) == nil && model.tool == .select,
              "Esc finishes typing and switches to Select: text kept and selected, editor gone")
        model.tool = .text
        model.undo()
        check(!model.annotations.contains { $0.id == textID }, "one undo removes the whole new callout")
        model.redo()
        check(model.annotations.contains { $0.id == textID }, "redo brings it back")

        let countWithCallout = model.annotations.count
        click(CGPoint(x: 600, y: 600))
        check(model.editingID != nil, "click on empty space starts another text")
        click(CGPoint(x: 900, y: 600))
        check(model.editingID == nil && model.annotations.count == countWithCallout, "text left empty disappears")
        model.undo()
        check(!model.annotations.contains { $0.id == textID }, "empty text leaves no undo step")
        model.redo()

        let box = text().textBox!.box
        click(CGPoint(x: box.midX, y: box.midY))
        check(model.editingID == textID && find(NSTextView.self, in: canvas)?.string == "Icon here", "clicking existing text edits it")
        model.endEditing()

        guard case .text(let originBefore, _, _, let pointerBefore) = text().shape else { finish() }
        drag(CGPoint(x: box.midX, y: box.midY), CGPoint(x: box.midX + 40, y: box.midY + 10))
        if case .text(let originAfter, _, _, let pointerAfter) = text().shape {
            check(model.editingID == nil && near(originAfter.x, originBefore.x + 40) && near(originAfter.y, originBefore.y + 10) && near(pointerAfter.x, pointerBefore.x + 40),
                  "dragging text moves it (pointer too)")
        }

        model.select(textID)
        guard case .text(_, _, _, let pointer) = text().shape else { finish() }
        drag(pointer, CGPoint(x: pointer.x - 60, y: pointer.y + 50))
        if case .text(_, _, _, let moved) = text().shape { check(near(moved.x, pointer.x - 60) && near(moved.y, pointer.y + 50), "dragging the pointer grip re-aims the callout") }

        // Pointer base: at least 1.2× the font size, wider for long pointers, never past the box edge.
        func pointerBase(_ distance: CGFloat) -> CGFloat {
            let probe = TextBox(origin: CGPoint(x: 100, y: 100), string: "Pointer base", style: .callout, pointer: .zero, fontSize: 28, color: Theme.accent)
            let tip = CGPoint(x: probe.box.midX, y: probe.box.maxY + distance)
            return TextBox(origin: CGPoint(x: 100, y: 100), string: "Pointer base", style: .callout, pointer: tip, fontSize: 28, color: Theme.accent)
                .pointerPath!.boundingBox.width
        }
        // Rounded end, not a needle: 2.8 px before the tip the pointer is still about as wide as its rounded end.
        let probe = TextBox(origin: CGPoint(x: 100, y: 100), string: "Pointer base", style: .callout, pointer: .zero, fontSize: 28, color: Theme.accent)
        let farTip = CGPoint(x: probe.box.midX, y: probe.box.maxY + 300)
        let farPointer = TextBox(origin: CGPoint(x: 100, y: 100), string: "Pointer base", style: .callout, pointer: farTip, fontSize: 28, color: Theme.accent).pointerPath!
        check(farPointer.contains(CGPoint(x: farTip.x + 2, y: farTip.y - 2.8)) && !farPointer.contains(CGPoint(x: farTip.x, y: farTip.y + 1)),
              "callout pointer ends in a rounded tip that touches the target")
        check(near(pointerBase(40), 33.6, 1) && pointerBase(300) > 50 && near(pointerBase(900), 67.2, 1),
              "callout pointer base widens with length (\(Int(pointerBase(40))) / \(Int(pointerBase(300))) / \(Int(pointerBase(900))) px)")

        let heightBefore = text().textBox!.box.height
        model.setWidth(48)
        check(text().textBox!.box.height > heightBefore * 1.5 && model.width(for: .text) == 48, "size slider resizes the text")

        let calloutBox = text().textBox!.box
        let paddingPoint = (Int(calloutBox.midX), Int(calloutBox.maxY - 3))
        let calloutPixel = pixel(model.rendered, paddingPoint.0, paddingPoint.1).prefix(3).map(Double.init)
        check(zip(calloutPixel, text().color.rgb).allSatisfy { abs($0 - $1) < 8 }, "callout box is filled in its color")
        model.setTextStyle(.plain)
        let withoutText = image.rendering(model.annotations.filter { $0.id != textID })
        check(Array(pixel(model.rendered, paddingPoint.0, paddingPoint.1)) == Array(pixel(withoutText, paddingPoint.0, paddingPoint.1)), "plain text has no background")
        model.setTextStyle(.label)
        model.select(textID)
        check(text().textBox!.pointerPath == nil, "label has no pointer")
        model.undo()
        model.undo()
        if case .text(_, _, let restored, _) = text().shape { check(restored == .callout, "undo restores the callout style") }

        model.tool = .select
        let selectBox = text().textBox!.box
        canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: selectBox.midX, y: selectBox.midY), clicks: 2))
        canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: selectBox.midX, y: selectBox.midY), clicks: 2))
        spin(0.2)
        check(model.editingID == textID, "double-click edits text with the select tool")
        model.endEditing()

        // Samples of every variant for a visual check
        let yellow = Theme.palette[2]
        model.annotations.append(Annotation(shape: .text(origin: CGPoint(x: 120, y: 60), string: "Label", style: .label, pointer: .zero), color: yellow, width: 28))
        model.annotations.append(Annotation(shape: .text(origin: CGPoint(x: 120, y: 500), string: "Plain text\nsecond line", style: .plain, pointer: .zero), color: .white, width: 28))
        model.select(textID)
        spin(0.3)
        snapshot(window.contentView!, "editor-text.png")

        // MARK: Recognize Text
        func waitForToast() {
            for _ in 0..<100 where !(model.toast ?? "").hasPrefix("Copied") && model.toast != "No text found" { spin(0.1) }
        }
        let board = NSPasteboard(name: NSPasteboard.Name("com.socialgoodsoftware.Shortty.selfcheck"))
        board.clearContents()
        model.textPasteboard = board
        model.select(nil)
        model.tool = .recognizeText
        check(!model.showsOptions, "Recognize Text has no options panel")
        let countBeforeOCR = model.annotations.count
        drag(CGPoint(x: 100, y: 560), CGPoint(x: 620, y: 620))
        waitForToast()
        check(model.annotations.count == countBeforeOCR, "Recognize Text adds nothing to the image")
        check(board.string(forType: .string)?.contains("Shortty") == true && model.toast == "Copied 1 line of text",
              "Recognize Text copies the words (\(board.string(forType: .string) ?? "nil"), toast: \(model.toast ?? "nil"))")
        drag(CGPoint(x: 850, y: 40), CGPoint(x: 950, y: 70))
        for _ in 0..<100 where model.toast != "No text found" { spin(0.1) }
        check(model.toast == "No text found", "an area without text says so")

        // MARK: Blur / Erase
        func only(_ annotation: Annotation) -> CGImage { image.rendering([annotation]) }
        func same(_ a: [UInt8], _ b: [UInt8], _ tolerance: Int = 6) -> Bool { zip(a.prefix(3), b.prefix(3)).allSatisfy { abs(Int($0) - Int($1)) <= tolerance } }
        model.tool = .blur
        check(model.showsWidthSlider && model.currentWidth == 12 && model.currentWidthRange == 4...40, "blur: strength 12 (4–40)")
        drag(CGPoint(x: 120, y: 120), CGPoint(x: 360, y: 240))
        let blur = model.annotations.last!
        if case .redact(let rect, .blur, _) = blur.shape { check(near(rect.width, 240) && near(rect.height, 120), "blur area drawn") }
        let blurred = only(blur)
        // Bars are drawn bottom-up: in top-left coordinates bar 11 spans y 158–168, x 120–543.
        check(pixel(blurred, 125, 160) == pixel(blurred, 130, 165) && pixel(blurred, 125, 160) != pixel(image, 125, 165), "blur pixelates in 12px blocks")
        check(pixel(blurred, 400, 125) == pixel(image, 400, 125), "blur stays inside its area")

        model.select(nil)
        model.setRedactStyle(.blurText)
        drag(CGPoint(x: 100, y: 560), CGPoint(x: 620, y: 620))
        let blurText = model.annotations.last!
        guard case .redact(_, .blurText, let boxes) = blurText.shape, let firstBox = boxes.first else {
            check(false, "Blur Text finds the text")
            finish()
        }
        check(true, "Blur Text finds the text (\(boxes.count) box)")
        let textBlurred = only(blurText)
        check(pixel(textBlurred, Int(firstBox.midX), Int(firstBox.midY)) != pixel(image, Int(firstBox.midX), Int(firstBox.midY))
              && pixel(textBlurred, 610, 565) == pixel(image, 610, 565), "Blur Text hides only the text")

        model.setRedactStyle(.eraseText)
        check(!model.showsWidthSlider, "erase has no strength slider")
        let erased = only(model.annotations.last!)
        let background = pixel(image, 110, 610)
        check(same(pixel(erased, Int(firstBox.midX), Int(firstBox.midY)), background) && same(pixel(erased, Int(firstBox.minX) + 30, Int(firstBox.midY) + 3), background),
              "Erase Text paints the text over with the background")
        model.undo()
        if case .redact(_, let style, _) = model.annotations.last!.shape { check(style == .blurText, "undo restores Blur Text") }

        model.select(nil)
        model.setRedactStyle(.erase)
        drag(CGPoint(x: 115, y: 278), CGPoint(x: 300, y: 318))
        let wiped = only(model.annotations.last!)
        check(pixel(wiped, 130, 285) == pixel(wiped, 290, 312) && pixel(wiped, 130, 285) != pixel(image, 130, 286), "Erase fills the area with one surrounding color")
        model.setRedactStyle(.blur)

        // MARK: Spotlight
        model.select(nil)
        model.tool = .spotlight
        check(model.currentWidth == 60 && model.currentWidthRange == 20...90, "spotlight: dim 60% (20–90)")
        drag(CGPoint(x: 650, y: 300), CGPoint(x: 800, y: 420))
        let spot1 = model.annotations.last!
        model.select(nil)
        drag(CGPoint(x: 760, y: 380), CGPoint(x: 880, y: 480))
        let spot2 = model.annotations.last!
        let lit = image.rendering([spot1, spot2])
        let outsideBefore = pixel(image, 50, 50), outsideAfter = pixel(lit, 50, 50)
        check(pixel(lit, 700, 350) == pixel(image, 700, 350) && Double(outsideAfter[0]) < Double(outsideBefore[0]) * 0.5 + 2,
              "spotlight keeps its area, dims the rest (\(outsideBefore[0]) → \(outsideAfter[0]))")
        check(pixel(lit, 780, 400) == pixel(image, 780, 400), "overlapping spotlights share one dim layer")
        check(same(pixel(lit, 650, 360), spot1.color.rgb.map { UInt8($0) }, 8), "spotlight is outlined in its color")
        model.setAreaShape(.ellipse)
        let litEllipse = image.rendering([spot1, model.annotations.last!])
        check(pixel(litEllipse, 864, 470) != pixel(image, 864, 470) && pixel(litEllipse, 820, 430) == pixel(image, 820, 430), "ellipse spotlight lights only the ellipse")

        // MARK: Magnifier
        model.select(nil)
        model.tool = .magnifier
        drag(CGPoint(x: 140, y: 150), CGPoint(x: 180, y: 176)) // over bar 11
        guard case .magnifier(let source, let target, let lens) = model.annotations.last!.shape else { check(false, "magnifier drawn"); finish() }
        check(lens == .ellipse && near(target.width, source.width * 2) && near(target.height, source.height * 2) && image.bounds.contains(target) && !source.intersects(target),
              "magnifier puts a 2× copy beside the area")
        let magnified = only(model.annotations.last!)
        check(same(pixel(magnified, Int(target.midX), Int(target.midY)), pixel(image, Int(source.midX), Int(source.midY)), 12), "the copy shows the area enlarged")
        drag(CGPoint(x: target.midX, y: target.midY), CGPoint(x: target.midX + 30, y: target.midY + 20))
        if case .magnifier(let s, let t, _) = model.annotations.last!.shape {
            check(s == source && near(t.minX, target.minX + 30) && near(t.minY, target.minY + 20), "dragging the copy moves only the copy")
        }
        guard case .magnifier(let s1, let t1, _) = model.annotations.last!.shape else { finish() }
        drag(CGPoint(x: t1.maxX, y: t1.maxY), CGPoint(x: t1.maxX + 40, y: t1.maxY + 40))
        if case .magnifier(let s2, let t2, _) = model.annotations.last!.shape {
            check(s2 == s1 && t2.width / s2.width > 2.3 && near(t2.width / t2.height, s1.width / s1.height, 0.02), "resizing the copy zooms in, same proportions")
        }
        guard case .magnifier(let s3, let t3, _) = model.annotations.last!.shape else { finish() }
        drag(CGPoint(x: s3.maxX, y: s3.maxY), CGPoint(x: s3.maxX + 10, y: s3.maxY + 4))
        if case .magnifier(let s4, let t4, _) = model.annotations.last!.shape {
            check(near(t4.width / s4.width, t3.width / s3.width, 0.02) && near(t4.midX, t3.midX), "resizing the area keeps the zoom")
        }
        spin(0.3)
        snapshot(window.contentView!, "editor-effects.png")

        // MARK: Canvas grows past the image
        model.select(nil)
        let canvasBefore = model.canvasRect
        let scale = canvasBefore.width / canvas.frame.width // image px per point (1× or 2× display)
        model.tool = .rectangle
        drag(CGPoint(x: -150, y: -80), CGPoint(x: -40, y: -20)) // above and left of the image
        spin(0.2)
        let outside = model.annotations.last!
        check(model.canvasRect.minX <= -152 && model.canvasRect.minY <= -82, "drawing past the edge grows the canvas (\(model.canvasRect))")
        check(near(canvas.frame.width, model.canvasRect.width / scale, 1) && near(canvas.frame.height, model.canvasRect.height / scale, 1),
              "the editor's canvas grows with it (\(Int(canvas.frame.width))×\(Int(canvas.frame.height)) pt)")
        let grown = image.rendering([outside])
        let grownArea = image.canvasRect(for: [outside])
        check(grown.width == Int(grownArea.width) && grown.height == Int(grownArea.height) && grown.width > image.width, "export grows too")
        check(pixel(grown, 950 - Int(grownArea.minX), 20 - Int(grownArea.minY)) == pixel(image, 950, 20), "the image sits at its offset in the grown export")
        check(same(pixel(grown, 500 - Int(grownArea.minX), -50 - Int(grownArea.minY)), pixel(image, 2, 2)), "the new area is filled with the image's edge color")

        snapshot(window.contentView!, "editor-grown.png")
        let around = window.contentView!.convert(CGPoint(x: 4, y: 4), from: scroll)
        check(window.contentView!.hitTest(around) === canvas, "clicks in the empty area around the image reach the canvas")
        model.tool = .select
        click(CGPoint(x: -150, y: -50))
        check(model.selection == outside.id, "things past the edge can be grabbed again")
        model.undo()
        spin(0.3)
        check(model.canvasRect == canvasBefore && near(canvas.frame.width, canvasBefore.width / scale, 1), "removing it shrinks the canvas back")

        // MARK: Backdrop
        model.select(nil)
        let contentBefore = model.contentRect
        model.backdrop = Backdrop()
        spin(0.3)
        let pad = Backdrop().paddingSize(for: contentBefore)
        check(model.canvasRect == contentBefore.insetBy(dx: -pad, dy: -pad) && near(canvas.frame.width, model.canvasRect.width / scale, 1),
              "backdrop adds padding around everything, in the editor too")
        snapshot(window.contentView!, "editor-backdrop.png")
        let flattened = image.rendering(model.annotations)
        let carded = model.rendered
        let p = Int(pad), cw = flattened.width, ch = flattened.height
        check(carded.width == cw + 2 * p && carded.height == ch + 2 * p, "export includes the backdrop")
        check(same(pixel(carded, 1, 1), Backdrop.presets[0].colors[0].rgb.map { UInt8($0) }, 14), "the backdrop starts with the gradient's first color")
        check(pixel(carded, p + 1, p + 1) != pixel(flattened, 1, 1) && pixel(carded, p + cw / 2, p + ch / 2) == pixel(flattened, cw / 2, ch / 2),
              "the screenshot sits unchanged on a card with rounded corners")
        var noShadow = Backdrop()
        noShadow.shadow = 0
        let flat = flattened.addingBackdrop(noShadow)
        check(pixel(carded, p + cw / 2, p + ch + 6)[0] < pixel(flat, p + cw / 2, p + ch + 6)[0], "a shadow sits under the card")
        if let snapshotDir { try? NSBitmapImageRep(cgImage: carded).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(snapshotDir)/backdrop-export.png")) }
        model.backdrop = nil
        spin(0.3)
        check(model.canvasRect == contentBefore, "choosing None removes it")

        // MARK: Inserting pictures
        func solid(_ width: Int, _ height: Int, _ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> CGImage {
            let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            return context.makeImage()!
        }
        let tile = solid(120, 60, 1, 0, 0)
        model.tool = .pencil
        let countBeforeInsert = model.annotations.count
        model.insertImage(tile, centeredAt: CGPoint(x: 500, y: 300))
        let insertedIndex = model.annotations.count - 1
        let inserted = model.annotations[insertedIndex]
        check(model.annotations.count == countBeforeInsert + 1 && inserted.isImage && model.selection == inserted.id && model.tool == .select && !model.showsOptions,
              "an inserted picture is selected with the Select tool, no options panel")
        check(bounds(insertedIndex) == CGRect(x: 440, y: 270, width: 120, height: 60), "placed at its own size, centered")
        check(same(pixel(image.rendering([inserted]), 500, 300), [255, 0, 0]), "the picture is in the export")
        spin(0.2)
        drag(CGPoint(x: 500, y: 300), CGPoint(x: 540, y: 320))
        let moved = bounds(insertedIndex)
        check(near(moved.minX, 480) && near(moved.minY, 290) && near(moved.width, 120) && near(moved.height, 60), "dragging moves it")
        drag(CGPoint(x: 600, y: 350), CGPoint(x: 660, y: 360))
        check(near(bounds(insertedIndex).width / bounds(insertedIndex).height, 2, 0.01) && bounds(insertedIndex).width > 150, "resizing keeps its proportions")
        model.insertImage(solid(3000, 1000, 0, 0, 1))
        check(near(bounds(model.annotations.count - 1).width, 600) && near(bounds(model.annotations.count - 1).height, 200), "a big picture is scaled to fit")

        let tileFile = FileManager.default.temporaryDirectory.appendingPathComponent("shortty-selfcheck-tile.png")
        try! NSBitmapImageRep(cgImage: tile).representation(using: .png, properties: [:])!.write(to: tileFile)
        let pictureBoard = NSPasteboard(name: NSPasteboard.Name("com.socialgoodsoftware.Shortty.selfcheck.pictures"))
        pictureBoard.clearContents()
        pictureBoard.writeObjects([tileFile as NSURL])
        let countBeforePaste = model.annotations.count
        check(model.insertImages(from: pictureBoard) == 1 && model.annotations.count == countBeforePaste + 1, "a copied image file is inserted")
        pictureBoard.clearContents()
        pictureBoard.writeObjects([NSImage(cgImage: tile, size: .zero)])
        check(model.insertImages(from: pictureBoard) == 1, "copied image data is inserted")
        pictureBoard.clearContents()
        pictureBoard.setString("just text", forType: .string)
        check(model.insertImages(from: pictureBoard) == 0, "text on the clipboard inserts nothing")
        try? FileManager.default.removeItem(at: tileFile)
        model.undo(); model.undo(); model.undo(); model.undo(); model.undo(); model.undo()
        check(model.annotations.count == countBeforeInsert, "undo takes the pictures back out")

        // MARK: Drag and drop file
        let dragFile = try! ImageExport.temporaryFile(model.rendered)
        let loaded = CGImage.load(from: dragFile)
        check(loaded?.width == image.width && dragFile.path.contains("Shortty Drag") && !dragFile.path.contains("Downloads"), "drag hands over a temporary PNG")
        let secondFile = try! ImageExport.temporaryFile(model.rendered)
        check(!FileManager.default.fileExists(atPath: dragFile.path) || dragFile == secondFile, "older drag files are cleaned up")

        // Toolbar at the minimum width
        window.setContentSize(NSSize(width: 720, height: 620))
        spin(0.4)
        snapshot(window.contentView!, "toolbar-720.png")
        window.setContentSize(NSSize(width: 900, height: 620))

        // MARK: Shortcut labels (needs a layout where the number row prints digits, e.g. US/UK/Spanish)
        check(Hotkey.keyName(for: UInt32(kVK_ANSI_0)) == "0" && Hotkey.keyName(for: UInt32(kVK_ANSI_Backslash)) == "\\", "shortcut labels use the key, not the shifted symbol")
        check(Hotkey(rawValue: "29|1179648|)")?.display == "⇧⌘0", "a label saved as ⇧⌘) now shows ⇧⌘0")

        // MARK: Reopen last capture (one editor window, edits kept)
        let editor = EditorWindowController.shared
        check(!editor.model.hasImage, "editor starts with no capture")
        editor.show(image)
        spin(0.3)
        let editorWindow = editor.window!
        editor.model.annotations.append(Annotation(shape: .rectangle(CGRect(x: 10, y: 10, width: 50, height: 50)), color: Theme.accent))
        editor.close()
        spin(0.2)
        check(!editorWindow.isVisible, "closing hides the editor")
        editor.reopen()
        spin(0.3)
        check(editor.window === editorWindow && editorWindow.isVisible && editor.model.image === image && editor.model.annotations.count == 1,
              "reopen shows the same window with the last capture and its edits")
        editor.show(fixture())
        spin(0.2)
        check(editor.window === editorWindow && editor.model.annotations.isEmpty && editor.model.image !== image, "a new capture reuses the window and starts clean")

        // Keys while typing go to the text, not to tool shortcuts
        let vKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: editorWindow.windowNumber, context: nil,
                                    characters: "v", charactersIgnoringModifiers: "v", isARepeat: false, keyCode: UInt16(kVK_ANSI_V))!
        editor.model.tool = .text
        let typing = Annotation(shape: .text(origin: CGPoint(x: 50, y: 50), string: "x", style: .plain, pointer: .zero), color: Theme.accent, width: 28)
        editor.model.annotations.append(typing)
        editor.model.beginEditing(typing.id)
        check(!editor.handle(vKey) && editor.model.tool == .text, "while typing, V types instead of switching tool")
        editor.model.endEditing()
        check(editor.handle(vKey) && editor.model.tool == .select, "after typing, V switches to Select")
        let mKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: editorWindow.windowNumber, context: nil,
                                    characters: "m", charactersIgnoringModifiers: "m", isARepeat: false, keyCode: UInt16(kVK_ANSI_M))!
        check(editor.handle(mKey) && editor.model.tool == .magnifier, "M picks the magnifier")

        // Esc clears the selection but never closes the editor
        let escKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: editorWindow.windowNumber, context: nil,
                                      characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: UInt16(kVK_Escape))!
        editor.model.select(typing.id)
        check(editor.model.tool == .magnifier && editor.handle(escKey) && editor.model.tool == .select && editor.model.selection == typing.id,
              "Esc with a tool active switches to Select, keeps the selection")
        check(editor.handle(escKey) && editor.model.selection == nil && editorWindow.isVisible, "Esc on Select clears the selection, window stays")
        check(editor.handle(escKey) && editorWindow.isVisible, "Esc again does not close the window")
        editor.close()

        // Focus without activation: this check process is a background app, like Shortty right after a capture
        editor.show(fixture())
        spin(1.5) // key status arrives asynchronously; the editor retries for about a second
        check(editorWindow.styleMask.contains(.nonactivatingPanel) && editorWindow.isKeyWindow && editorWindow.isVisible,
              "the preview opens focused even though the app isn't frontmost (key \(editorWindow.isKeyWindow), visible \(editorWindow.isVisible), app key window \(NSApp.keyWindow.map { String(describing: type(of: $0)) } ?? "none"))")
        editor.close()

        // MARK: Settings + icon
        check(AppSettings.shared.lazyDelay >= 1 && AppSettings.shared.lazyDelay <= 30, "lazy delay within 1–30")
        let iconDir = "\(repo)/Shortty/Resources/Assets.xcassets/AppIcon.appiconset"
        let sizes = [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64), ("icon_128x128", 128),
                     ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)]
        check(sizes.allSatisfy { size in
            (try? Data(contentsOf: URL(fileURLWithPath: "\(iconDir)/\(size.0).png"))).flatMap { NSBitmapImageRep(data: $0) }?.pixelsWide == size.1
        }, "all 10 app icon PNGs at the right size")

        finish()
    }

    static func finish() -> Never {
        print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
