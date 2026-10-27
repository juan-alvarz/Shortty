// Drives the real editor views with synthetic mouse/scroll events and checks the results.
// Run via Scripts/selfcheck.sh. Add a check here for every new editor behavior.
import AppKit
import Carbon.HIToolbox
import CoreImage
import SwiftUI
import VisionKit

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
    static func same(_ a: [UInt8], _ b: [UInt8], _ tolerance: Int = 6) -> Bool { zip(a.prefix(3), b.prefix(3)).allSatisfy { abs(Int($0) - Int($1)) <= tolerance } }
    static func same(_ a: [UInt8], _ color: Color, _ tolerance: Int = 6) -> Bool { same(a, color.rgb.map { UInt8($0) }, tolerance) }
    /// An sRGB bitmap, filled with `fill` when given.
    static func bitmap(_ width: Int, _ height: Int, _ fill: CGColor? = nil) -> CGContext {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        if let fill { context.setFillColor(fill); context.fill(CGRect(x: 0, y: 0, width: width, height: height)) }
        return context
    }
    static func key(_ characters: String, _ code: Int, in window: NSWindow, flags: NSEvent.ModifierFlags = [], type: NSEvent.EventType = .keyDown) -> NSEvent {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: UInt16(code))!
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
        snapshotDir = CommandLine.arguments.dropFirst().first
        let image = fixture()

        check(ScreenCapture.rectArgument(CGRect(x: 100, y: 200, width: 300, height: 400), primaryHeight: 1000) == "100,400,300,400", "rect argument flips y")

        let model = EditorModel(image: image)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 680),
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
        check(model.annotations.count == 1 && model.annotations[0].tool == .pencil && model.selection == nil, "pencil draws a stroke, not selected")
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
        drag(CGPoint(x: 100, y: 500), CGPoint(x: 300, y: 520), [.shift, .control])
        if case .stroke(let points) = model.annotations.last!.shape {
            check(near(points.last!.x, 300) && near(points.last!.y, 500), "Shift+Control pencil snaps to 0° (end y \(Int(points.last!.y)))")
        }

        // MARK: Ruler
        let ruled = bitmap(100, 60, CGColor(gray: 1, alpha: 1))
        ruled.setFillColor(CGColor(gray: 0, alpha: 1))
        ruled.fill(CGRect(x: 20, y: 10, width: 50, height: 30)) // image px x 20..<70, y 20..<50
        let pixels = RulerPixels(ruled.makeImage()!)
        check(pixels.run(at: CGPoint(x: 30, y: 30), horizontal: true) == 20..<70 && pixels.run(at: CGPoint(x: 30, y: 30), horizontal: false) == 20..<50,
              "ruler runs stop at the edges")
        check(pixels.run(at: CGPoint(x: 5, y: 5), horizontal: true) == 0..<100 && pixels.run(at: CGPoint(x: -1, y: 5), horizontal: true) == nil,
              "ruler runs end at the picture's edge, nothing off it")
        model.tool = .ruler
        canvas.mouseMoved(with: mouse(.mouseMoved, CGPoint(x: 500, y: 300)))
        check(model.rulerPoint.map { near($0.x, 500) && near($0.y, 300) } == true, "ruler follows the pointer")
        spin(0.2)
        snapshot(window.contentView!, "ruler.png")
        model.tool = .pencil
        check(model.rulerPoint == nil, "ruler clears when another tool is picked")

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
            let exported = pixel(model.rendered, Int(mid.x), Int(mid.y))
            check(solidStyle == .solid && same(exported, solidArrow.color, 7), "export draws the solid arrow body in its color (\(exported.prefix(3)) vs \(solidArrow.color.rgb))")
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
        func callout(_ tip: CGPoint) -> TextBox { TextBox(origin: CGPoint(x: 100, y: 100), string: "Pointer base", style: .callout, pointer: tip, fontSize: 28, color: Theme.accent) }
        let probe = callout(.zero).box
        func pointerBase(_ distance: CGFloat) -> CGFloat { callout(CGPoint(x: probe.midX, y: probe.maxY + distance)).pointerPath!.boundingBox.width }
        // Rounded end, not a needle: 2.8 px before the tip the pointer is still about as wide as its rounded end.
        let farTip = CGPoint(x: probe.midX, y: probe.maxY + 300)
        let farPointer = callout(farTip).pointerPath!
        check(farPointer.contains(CGPoint(x: farTip.x + 2, y: farTip.y - 2.8)) && !farPointer.contains(CGPoint(x: farTip.x, y: farTip.y + 1)),
              "callout pointer ends in a rounded tip that touches the target")
        check(near(pointerBase(40), 33.6, 1) && pointerBase(300) > 50 && near(pointerBase(900), 67.2, 1),
              "callout pointer base widens with length (\(Int(pointerBase(40))) / \(Int(pointerBase(300))) / \(Int(pointerBase(900))) px)")

        let heightBefore = text().textBox!.box.height
        model.setWidth(48)
        check(text().textBox!.box.height > heightBefore * 1.5 && model.width(for: .text) == 48, "size slider resizes the text")

        let calloutBox = text().textBox!.box
        let paddingPoint = (Int(calloutBox.midX), Int(calloutBox.maxY - 3))
        check(same(pixel(model.rendered, paddingPoint.0, paddingPoint.1), text().color, 7), "callout box is filled in its color")
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
        click(CGPoint(x: selectBox.midX, y: selectBox.midY), clicks: 2)
        check(model.editingID == textID, "double-click edits text with the select tool")
        model.endEditing()

        // Samples of every variant for a visual check
        let yellow = Theme.palette[2]
        model.annotations.append(Annotation(shape: .text(origin: CGPoint(x: 120, y: 60), string: "Label", style: .label, pointer: .zero), color: yellow, width: 28))
        model.annotations.append(Annotation(shape: .text(origin: CGPoint(x: 120, y: 500), string: "Plain text\nsecond line", style: .plain, pointer: .zero), color: .white, width: 28))
        model.select(textID)
        spin(0.3)
        snapshot(window.contentView!, "editor-text.png")

        // MARK: Recognize Text (Live Text)
        let board = NSPasteboard.withUniqueName() // private: never the real clipboard
        model.textPasteboard = board
        model.select(nil)
        let countBeforeOCR = model.annotations.count
        model.tool = .recognizeText
        for _ in 0..<150 where model.recognizedText == nil { spin(0.1) }
        check(model.recognizedText?.contains("Shortty") == true, "Live Text finds the picture's text (\(model.recognizedText ?? "nil"))")
        let liveText = find(ImageAnalysisOverlayView.self, in: canvas)
        let pointsPerPixel = canvas.frame.width / model.canvasRect.width
        check(liveText.map { !$0.isHidden && near($0.frame.width, CGFloat(image.width) * pointsPerPixel, 1) && near($0.frame.height, CGFloat(image.height) * pointsPerPixel, 1) } == true,
              "the Live Text layer covers the picture")
        check(model.showsOptions && !model.showsWidthSlider && !model.hasTextSelection, "panel with Copy All, no slider, nothing selected yet")
        model.copyAllText()
        check(board.string(forType: .string)?.contains("Hello Shortty 42") == true && model.toast == "Copied all text", "Copy All copies every word")
        check(model.annotations.count == countBeforeOCR, "Recognize Text adds nothing to the picture")
        snapshot(window.contentView!, "editor-livetext.png")
        model.tool = .select
        spin(0.2)
        check(liveText?.isHidden == true, "leaving the mode hides Live Text")

        // MARK: Blur / Erase
        func only(_ annotation: Annotation) -> CGImage { image.rendering([annotation]) }
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
        let textBlurred = only(blurText)
        check(pixel(textBlurred, Int(firstBox.midX), Int(firstBox.midY)) != pixel(image, Int(firstBox.midX), Int(firstBox.midY))
              && pixel(textBlurred, 610, 565) == pixel(image, 610, 565), "Blur Text finds the text (\(boxes.count) box) and hides only it")

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
        check(same(pixel(lit, 650, 360), spot1.color, 8), "spotlight is outlined in its color")
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
        guard case .magnifier(let s1, let t1, _) = model.annotations.last!.shape else { finish() }
        check(s1 == source && near(t1.minX, target.minX + 30) && near(t1.minY, target.minY + 20), "dragging the copy moves only the copy")
        drag(CGPoint(x: t1.maxX, y: t1.maxY), CGPoint(x: t1.maxX + 40, y: t1.maxY + 40))
        guard case .magnifier(let s3, let t3, _) = model.annotations.last!.shape else { finish() }
        check(s3 == s1 && t3.width / s3.width > 2.3 && near(t3.width / t3.height, s1.width / s1.height, 0.02), "resizing the copy zooms in, same proportions")
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
        check(same(pixel(carded, 1, 1), Backdrop.presets[0].colors[0], 14), "the backdrop starts with the gradient's first color")
        check(pixel(carded, p + 1, p + 1) != pixel(flattened, 1, 1) && pixel(carded, p + cw / 2, p + ch / 2) == pixel(flattened, cw / 2, ch / 2),
              "the screenshot sits unchanged on a card with rounded corners")
        var noShadow = Backdrop()
        noShadow.shadow = 0
        let flat = image.rendering(model.annotations, backdrop: noShadow)
        check(pixel(carded, p + cw / 2, p + ch + 6)[0] < pixel(flat, p + cw / 2, p + ch + 6)[0], "a shadow sits under the card")
        if let snapshotDir { try? ImageExport.writePNG(carded, to: URL(fileURLWithPath: "\(snapshotDir)/backdrop-export.png")) }
        model.backdrop = nil
        spin(0.3)
        check(model.canvasRect == contentBefore, "choosing None removes it")

        // MARK: Inserting pictures
        func solid(_ width: Int, _ height: Int, _ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> CGImage {
            bitmap(width, height, CGColor(srgbRed: red, green: green, blue: blue, alpha: 1)).makeImage()!
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

        let tileFile = try! ImageExport.temporaryFile(tile) // a temp folder, replaced by the next drag file
        board.clearContents()
        board.writeObjects([tileFile as NSURL])
        let countBeforePaste = model.annotations.count
        check(model.insertImages(from: board) == 1 && model.annotations.count == countBeforePaste + 1, "a copied image file is inserted")
        board.clearContents()
        board.writeObjects([NSImage(cgImage: tile, size: .zero)])
        check(model.insertImages(from: board) == 1, "copied image data is inserted")
        board.clearContents()
        board.setString("just text", forType: .string)
        check(model.insertImages(from: board) == 0, "text on the clipboard inserts nothing")
        model.undo(); model.undo(); model.undo(); model.undo(); model.undo(); model.undo()
        check(model.annotations.count == countBeforeInsert, "undo takes the pictures back out")

        // MARK: Numbered steps
        model.select(nil)
        model.tool = .step
        check(model.showsOptions && model.currentWidth == 36 && model.currentWidthRange == 16...96, "steps: size 36 (16–96)")
        let stepsBefore = model.annotations.count
        for point in [CGPoint(x: 150, y: 620), CGPoint(x: 250, y: 620), CGPoint(x: 350, y: 620)] { click(point) }
        let steps = model.annotations.suffix(3)
        var numbers = Annotation.stepNumbers(in: model.annotations)
        check(model.annotations.count == stepsBefore + 3 && steps.map { numbers[$0.id] } == [1, 2, 3] && model.selection == steps.last?.id,
              "three clicks place steps 1, 2, 3")
        let firstStep = steps.first!
        check(same(pixel(image.rendering([firstStep]), 150 + 12, 620), firstStep.color, 10), "a step is a filled badge in its color")
        model.select(steps[steps.startIndex + 1].id)
        model.deleteSelection()
        numbers = Annotation.stepNumbers(in: model.annotations)
        check(numbers[steps.first!.id] == 1 && numbers[steps.last!.id] == 2, "deleting step 2 renumbers the rest")
        model.undo()
        check(Annotation.stepNumbers(in: model.annotations)[steps.last!.id] == 3, "undo brings it back as 2, the last is 3 again")
        model.select(steps.last!.id)
        model.setWidth(60)
        check(near(model.annotations.last!.bounds.width, 60), "the size slider resizes the selected step")
        click(CGPoint(x: 350, y: 620))
        check(model.annotations.count == stepsBefore + 3, "clicking an existing step selects it instead of adding one")
        drag(CGPoint(x: 450, y: 620), CGPoint(x: 520, y: 560))
        let dragged = model.annotations.last!.bounds
        check(model.annotations.count == stepsBefore + 4 && near(dragged.midX, 520) && near(dragged.midY, 560), "a new step follows the pointer while the button is held")
        model.undo()
        spin(0.3)
        snapshot(window.contentView!, "editor-steps.png")

        // MARK: Text Card (drag)
        model.select(nil)
        model.tool = .textCard
        var textCardArea: CGRect?
        model.onTextCard = { textCardArea = $0 }
        let countBeforeCard = model.annotations.count
        check(model.showsOptions && !model.showsWidthSlider, "text card: a hint, no slider")
        drag(CGPoint(x: 100, y: 120), CGPoint(x: 700, y: 420))
        check(textCardArea.map { near($0.minX, 100) && near($0.minY, 120) && near($0.width, 600) && near($0.height, 300) } == true
              && model.annotations.count == countBeforeCard && model.textCardBox == nil,
              "dragging with Text Card hands over the area and draws nothing")
        textCardArea = nil
        drag(CGPoint(x: 300, y: 300), CGPoint(x: 302, y: 301))
        check(textCardArea == nil, "a click with Text Card does nothing")
        model.onTextCard = nil

        // MARK: Crop
        model.select(nil)
        model.tool = .crop
        check(model.showsOptions && !model.showsWidthSlider, "crop: panel with buttons, no slider")
        drag(CGPoint(x: 200, y: 150), CGPoint(x: 600, y: 400))
        check(model.cropBox.map { near($0.minX, 200) && near($0.minY, 150) && near($0.width, 400) && near($0.height, 250) } == true, "dragging sets the crop box")
        spin(0.3)
        snapshot(window.contentView!, "editor-crop.png")
        drag(CGPoint(x: 600, y: 400), CGPoint(x: 1400, y: 900)) // bottom-right handle, far past the picture
        check(model.cropBox.map { $0.maxX <= model.contentRect.maxX + 0.5 && $0.maxY <= model.contentRect.maxY + 0.5 } == true, "the box stays inside the picture")
        drag(CGPoint(x: 600, y: 400), CGPoint(x: 600, y: 400)) // no-op click inside keeps the box
        model.cropBox = CGRect(x: 200, y: 150, width: 400, height: 250)
        let uncropped = image.rendering(model.annotations)
        let uncroppedOrigin = image.canvasRect(for: model.annotations).origin
        model.applyCrop()
        spin(0.4)
        check(model.crop == CGRect(x: 200, y: 150, width: 400, height: 250) && model.tool == .select && model.cropBox == nil, "Crop applies the box and returns to Select")
        check(model.canvasRect == model.crop! && near(canvas.frame.width, 400 / scale, 1), "the editor shows just the cropped area")
        let cropped = model.rendered
        check(cropped.width == 400 && cropped.height == 250 &&
              pixel(cropped, 30, 20) == pixel(uncropped, 230 - Int(uncroppedOrigin.x), 170 - Int(uncroppedOrigin.y)), "export is exactly the cropped area")
        model.undo()
        check(model.crop == nil, "undo removes the crop")
        model.redo()
        check(model.crop != nil, "redo brings it back")
        model.tool = .textCard
        var croppedCardArea: CGRect?
        model.onTextCard = { croppedCardArea = $0 }
        drag(CGPoint(x: 300, y: 200), CGPoint(x: 900, y: 700))
        check(croppedCardArea.map { near($0.minX, 300) && near($0.minY, 200) && near($0.maxX, 600) && near($0.maxY, 400) } == true,
              "Text Card reads only what the crop shows")
        model.onTextCard = nil
        model.tool = .select
        model.resetCrop()
        spin(0.3)
        check(model.crop == nil && model.canvasRect == model.contentRect && model.contentRect != CGRect(x: 200, y: 150, width: 400, height: 250), "Reset shows the whole picture again")

        // MARK: Pin to screen
        let pinned = PinWindow.pin(image)
        spin(0.3)
        let pinScale = pinned.screen?.backingScaleFactor ?? 2
        check(pinned.isVisible && pinned.level == .floating && near(pinned.frame.width, CGFloat(image.width) / pinScale, 1) && near(pinned.frame.height, CGFloat(image.height) / pinScale, 1),
              "pin floats the picture at its natural size")
        let widthBefore = pinned.frame.width
        pinned.resize(by: 0.5, around: CGPoint(x: pinned.frame.midX, y: pinned.frame.midY))
        check(near(pinned.frame.width, widthBefore * 0.5, 1) && near(pinned.frame.width / pinned.frame.height, CGFloat(image.width) / CGFloat(image.height), 0.01), "scrolling resizes it, same proportions")
        pinned.keyDown(with: key("\u{1b}", kVK_Escape, in: pinned))
        spin(0.2)
        check(!pinned.isVisible, "Esc closes the pin")

        // MARK: Scrolling capture stitcher (synthetic page with a sticky header and footer)
        func page(width: Int, height: Int) -> CGImage {
            let context = bitmap(width, height, CGColor(gray: 1, alpha: 1))
            var seed: UInt64 = 42
            func next(_ range: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int(seed >> 33) % range }
            for _ in 0..<320 {
                context.setFillColor(CGColor(srgbRed: CGFloat(next(255)) / 255, green: CGFloat(next(255)) / 255, blue: CGFloat(next(255)) / 255, alpha: 1))
                context.fill(CGRect(x: next(width - 40), y: next(height), width: 20 + next(180), height: 4 + next(26)))
            }
            return context.makeImage()!
        }
        let tallPage = page(width: 600, height: 2400)
        let header = 50, footer = 30, band = 320
        func frame(at offset: Int) -> CGImage {
            let total = header + band + footer
            let context = bitmap(600, total)
            context.draw(tallPage.cropping(to: CGRect(x: 0, y: offset, width: 600, height: band))!, in: CGRect(x: 0, y: footer, width: 600, height: band))
            context.setFillColor(CGColor(srgbRed: 0.1, green: 0.2, blue: 0.6, alpha: 1)) // sticky header (top)
            context.fill(CGRect(x: 0, y: total - header, width: 600, height: header))
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 20, y: total - 30, width: 140, height: 12))
            context.setFillColor(CGColor(gray: 0.85, alpha: 1)) // sticky footer (bottom)
            context.fill(CGRect(x: 0, y: 0, width: 600, height: footer))
            context.setFillColor(CGColor(gray: 0.3, alpha: 1))
            context.fill(CGRect(x: 400, y: 10, width: 120, height: 10))
            return context.makeImage()!
        }
        var stitcher = ScrollStitcher()
        var outcomes: [ScrollStitcher.Outcome] = []
        for offset in [0, 0, 90, 200, 200, 330, 470, 600, 750, 900, 1100, 1300, 1500, 1700, 1900, 2080] { outcomes.append(stitcher.add(frame(at: offset))) }
        check(outcomes.first == .started && outcomes[1] == .unchanged && outcomes[4] == .unchanged && !outcomes.contains(.lost), "frames: started, pauses ignored, every scroll matched")
        let stitched = stitcher.image()!
        check(stitched.height == header + 2400 + footer && stitcher.height == stitched.height, "stitched height is header + whole page + footer (\(stitched.height) px)")
        let rowsMatch = stride(from: 0, to: 2400, by: 37).allSatisfy { y in
            [10, 300, 590].allSatisfy { x in pixel(stitched, x, header + y) == pixel(tallPage, x, y) }
        }
        check(rowsMatch, "the stitched page matches the original row for row")
        check(pixel(stitched, 5, 5) == pixel(frame(at: 0), 5, 5) && pixel(stitched, 450, stitched.height - 15) == pixel(frame(at: 0), 450, header + band + footer - 15),
              "sticky header and footer appear once, at the top and bottom")
        var jumpy = ScrollStitcher()
        _ = jumpy.add(frame(at: 0))
        check(jumpy.add(frame(at: 600)) == .lost && jumpy.add(frame(at: 150)) == .appended(rows: 150), "a jump with no overlap is skipped, the next good frame continues")

        // MARK: Drag and drop file
        let dragFile = try! ImageExport.temporaryFile(model.rendered)
        let loaded = CGImage.load(from: dragFile)
        check(loaded?.width == image.width && dragFile.path.contains("Shortty Drag") && !dragFile.path.contains("Downloads"), "drag hands over a temporary PNG")
        let secondFile = try! ImageExport.temporaryFile(model.rendered)
        check(!FileManager.default.fileExists(atPath: dragFile.path) || dragFile == secondFile, "older drag files are cleaned up")

        // Toolbar at the minimum width (920)
        window.setContentSize(NSSize(width: 920, height: 620))
        spin(0.4)
        snapshot(window.contentView!, "toolbar-min.png")
        window.setContentSize(NSSize(width: 920, height: 680))

        // MARK: Capture actions from Shottr's list
        let ids = Dictionary(uniqueKeysWithValues: CaptureAction.allCases.map { ($0, $0.hotkeyID) })
        check(ids[.region] == 1 && ids[.screen] == 2 && ids[.lazyRegion] == 3 && ids[.lazyScreen] == 4 && ids[.reopen] == 5 && ids[.scrolling] == 6
              && Set(ids.values).count == CaptureAction.allCases.count, "existing shortcut ids are unchanged, new ones are unique")
        check(RegionSelector.keyAction(for: kVK_Escape, allowsWindow: true) == .cancel
              && RegionSelector.keyAction(for: kVK_Space, allowsWindow: true) == .pickWindow
              && RegionSelector.keyAction(for: kVK_Space, allowsWindow: false) == nil, "selector: Esc cancels, Space picks a window only for Capture Region")
        let savedRegion = CaptureController.lastRegion
        CaptureController.lastRegion = CGRect(x: 120, y: 340, width: 500, height: 260)
        check(CaptureController.lastRegion == CGRect(x: 120, y: 340, width: 500, height: 260), "Repeat Last Region remembers the area")
        CaptureController.lastRegion = savedRegion
        window.orderFrontRegardless()
        spin(0.3)
        check(ScreenCapture.frontWindowID(of: ProcessInfo.processInfo.processIdentifier) == CGWindowID(window.windowNumber),
              "Capture Active Window finds the app's front window")

        let textArea = CGRect(x: 100, y: 560, width: 520, height: 60)
        let readText = TextRecognition.readable(in: image.cropping(to: textArea)!)
        if case .text(let text)? = readText { check(text.contains("Shortty"), "Capture Text reads text (\(text))") } else { check(false, "Capture Text reads text") }
        let qrFilter = CIFilter(name: "CIQRCodeGenerator")!
        qrFilter.setValue("https://shortty.app/hello".data(using: .utf8), forKey: "inputMessage")
        let qrModules = qrFilter.outputImage!.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let qrCanvas = bitmap(Int(qrModules.extent.width) + 80, Int(qrModules.extent.height) + 80, CGColor(gray: 1, alpha: 1))
        qrCanvas.draw(CIContext().createCGImage(qrModules, from: qrModules.extent)!, in: qrModules.extent.offsetBy(dx: 40, dy: 40))
        check(TextRecognition.readable(in: qrCanvas.makeImage()!) == .code("https://shortty.app/hello"), "Capture Text reads a QR code's link")
        check(TextCapture.copy(.code("https://shortty.app/hello"), to: board) == "Copied QR code: https://shortty.app/hello"
              && board.string(forType: .string) == "https://shortty.app/hello", "a QR code's contents go to the clipboard")
        check(TextCapture.copy(.text("one\ntwo"), to: board) == "Copied 2 lines of text" && board.string(forType: .string) == "one\ntwo",
              "text goes to the clipboard, the notice counts lines")
        check(TextCapture.copy(nil, to: board) == "No text found", "nothing found says so")
        let notice = FloatingToast.show("Copied 2 lines of text", near: CGRect(x: 300, y: 300, width: 200, height: 100), for: 0.5)
        spin(0.2)
        check(notice.isVisible && notice.ignoresMouseEvents, "the floating notice appears and lets clicks through")
        spin(1.0)
        check(!notice.isVisible, "and goes away by itself")

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
        let vKey = key("v", kVK_ANSI_V, in: editorWindow)
        editor.model.tool = .text
        let typing = Annotation(shape: .text(origin: CGPoint(x: 50, y: 50), string: "x", style: .plain, pointer: .zero), color: Theme.accent, width: 28)
        editor.model.annotations.append(typing)
        editor.model.beginEditing(typing.id)
        check(!editor.handle(vKey) && editor.model.tool == .text, "while typing, V types instead of switching tool")
        editor.model.endEditing()
        check(editor.handle(vKey) && editor.model.tool == .select, "after typing, V switches to Select")
        check(editor.handle(key("m", kVK_ANSI_M, in: editorWindow)) && editor.model.tool == .magnifier, "M picks the magnifier")
        check(editor.handle(key("u", kVK_ANSI_U, in: editorWindow)) && editor.model.tool == .ruler, "U picks the ruler")
        check(editor.handle(key("1", kVK_ANSI_1, in: editorWindow)) && editor.model.rulerAxes == .horizontal, "holding 1 measures across only")
        _ = editor.handle(key("1", kVK_ANSI_1, in: editorWindow, type: .keyUp))
        check(editor.model.rulerAxes == .both, "releasing 1 measures both ways again")
        check(editor.handle(key("2", kVK_ANSI_2, in: editorWindow)) && editor.model.rulerAxes == .vertical, "holding 2 measures up and down only")
        _ = editor.handle(key("2", kVK_ANSI_2, in: editorWindow, type: .keyUp))
        editor.model.tool = .magnifier

        // One Esc clears the selection but never closes the editor; two in quick succession close it
        let escKey = key("\u{1b}", kVK_Escape, in: editorWindow)
        let slowly = NSEvent.doubleClickInterval + 0.15
        editor.model.select(typing.id)
        check(editor.model.tool == .magnifier && editor.handle(escKey) && editor.model.tool == .select && editor.model.selection == typing.id,
              "Esc with a tool active switches to Select, keeps the selection")
        spin(slowly)
        check(editor.handle(escKey) && editor.model.selection == nil && editorWindow.isVisible, "Esc on Select clears the selection, window stays")
        spin(slowly)
        check(editor.handle(escKey) && editorWindow.isVisible, "a single Esc never closes the window")
        check(editor.handle(escKey) && !editorWindow.isVisible, "a quick second Esc closes it")

        // Focus without activation: this check process is a background app, like Shortty right after a capture
        editor.show(fixture())
        spin(1.5) // key status arrives asynchronously; the editor retries for about a second
        check(editorWindow.styleMask.contains(.nonactivatingPanel) && editorWindow.isKeyWindow && editorWindow.isVisible,
              "the preview opens focused even though the app isn't frontmost (key \(editorWindow.isKeyWindow), visible \(editorWindow.isVisible), app key window \(NSApp.keyWindow.map { String(describing: type(of: $0)) } ?? "none"))")
        editor.close()

        // MARK: Selection bar, stacking order, shortcut hints
        model.tool = .select
        model.backdrop = nil
        let boxA = Annotation(shape: .rectangle(CGRect(x: 100, y: 100, width: 120, height: 80)), color: Theme.accent)
        let boxB = Annotation(shape: .rectangle(CGRect(x: 160, y: 140, width: 120, height: 80)), color: Theme.accent)
        model.annotations += [boxA, boxB]
        model.select(boxA.id)
        spin(0.3)
        let screenScale = canvas.frame.width / model.canvasRect.width
        check(model.selectionFrame.map { near($0.width, 120 * screenScale * scroll.magnification, 2) && $0.minY >= 0 } == true,
              "the selection bar knows where the selection is on screen")
        model.select(nil)
        spin(0.2)
        check(model.selectionFrame == nil, "no selection, no selection bar")
        let countBefore = model.annotations.count
        model.select(boxA.id)
        model.bringSelectionToFront()
        check(model.annotations.last?.id == boxA.id, "Bring to front draws the selection on top")
        model.sendSelectionToBack()
        check(model.annotations.first?.id == boxA.id, "Send to back draws it under everything")
        model.undo()
        check(model.annotations.last?.id == boxA.id, "each reorder is one undo step")
        model.duplicateSelection()
        let duplicate = model.annotations.last!
        check(model.annotations.count == countBefore + 1 && duplicate.id != boxA.id && duplicate.bounds == boxA.bounds.offsetBy(dx: 24, dy: 24)
              && model.selection == duplicate.id, "Duplicate adds a selected copy, a little down and right")
        model.undo()
        check(model.annotations.count == countBefore, "undo removes the copy")

        editor.show(fixture())
        let cmd: NSEvent.ModifierFlags = .command
        editor.model.annotations += [boxA, boxB]
        editor.model.select(boxA.id)
        check(editor.handle(key("]", kVK_ANSI_RightBracket, in: editorWindow, flags: cmd)) && editor.model.annotations.last?.id == boxA.id, "⌘] brings to front")
        check(editor.handle(key("[", kVK_ANSI_LeftBracket, in: editorWindow, flags: cmd)) && editor.model.annotations.first?.id == boxA.id, "⌘[ sends to back")
        check(editor.handle(key("d", kVK_ANSI_D, in: editorWindow, flags: cmd)) && editor.model.annotations.count == 3, "⌘D duplicates")
        editor.modifiersChanged(key("", kVK_Command, in: editorWindow, flags: cmd, type: .flagsChanged))
        check(editor.model.showsShortcutHints, "holding ⌘ shows the tool keys")
        editor.modifiersChanged(key("", kVK_Command, in: editorWindow, type: .flagsChanged))
        check(!editor.model.showsShortcutHints, "letting go of ⌘ hides them")
        editor.modifiersChanged(key("", kVK_Shift, in: editorWindow, flags: [.command, .shift], type: .flagsChanged))
        check(!editor.model.showsShortcutHints, "⌘ with another modifier doesn't show them")
        editor.close()
        model.showsShortcutHints = true
        spin(0.3)
        snapshot(window.contentView!, "toolbar-hints.png")
        model.showsShortcutHints = false

        // MARK: Capture history (a temporary folder, never the real Caches)
        let historyFolder = FileManager.default.temporaryDirectory.appendingPathComponent("shortty-selfcheck-history-\(UUID().uuidString)")
        let history = CaptureHistory(folder: historyFolder)
        for i in 0..<(CaptureHistory.limit + 2) { history.store(solid(40 + i, 30, 0.2, 0.4, 0.8)) }
        func pngs() -> Int { ((try? FileManager.default.contentsOfDirectory(atPath: historyFolder.path)) ?? []).filter { $0.hasSuffix(".png") }.count }
        check(history.items.count == CaptureHistory.limit && pngs() == CaptureHistory.limit && CGImage.load(from: history.latest!)?.width == 40 + CaptureHistory.limit + 1,
              "history keeps the newest \(CaptureHistory.limit) captures, newest first")
        check(CaptureHistory(folder: historyFolder).items == history.items, "history survives a relaunch")
        check(CaptureHistory.date(of: history.latest!).map { abs($0.timeIntervalSinceNow) < 60 } == true, "each capture knows when it was taken")
        let incoming = FileManager.default.temporaryDirectory.appendingPathComponent("shortty-selfcheck-\(UUID().uuidString).png")
        try? ImageExport.writePNG(solid(77, 30, 1, 0, 0), to: incoming)
        history.keep(incoming)
        check(!FileManager.default.fileExists(atPath: incoming.path) && CGImage.load(from: history.latest!)?.width == 77 && pngs() == CaptureHistory.limit,
              "a new capture's file moves into the history, the oldest goes")
        let doomed = history.items[3]
        history.remove(doomed)
        check(history.items.count == CaptureHistory.limit - 1 && !FileManager.default.fileExists(atPath: doomed.path), "× deletes one capture's file")

        // Edits are saved next to each capture and come back when it's reopened
        func hasEdits(_ capture: URL) -> Bool { FileManager.default.fileExists(atPath: CaptureHistory.editsURL(for: capture).path) }
        let editsModel = EditorModel(image: image)
        let first = history.items[0], second = history.items[1]
        editsModel.load(CGImage.load(from: first)!, from: first)
        let savedArrow = Annotation(shape: .arrow(start: CGPoint(x: 5, y: 5), end: CGPoint(x: 30, y: 20), bend: 4, style: .double),
                                    color: Color(rgb: [255, 0, 0]), width: 6)
        let savedCallout = Annotation(shape: .text(origin: CGPoint(x: 2, y: 2), string: "Saved", style: .callout, pointer: CGPoint(x: 20, y: 25)),
                                      color: Theme.accent, width: 28)
        editsModel.annotations = [savedArrow, savedCallout]
        editsModel.insertImage(solid(10, 8, 0, 1, 0))
        editsModel.load(CGImage.load(from: second)!, from: second)
        check(hasEdits(first) && editsModel.annotations.isEmpty, "opening another capture saves the first one's edits")
        let previewFile = CaptureHistory.previewURL(for: first)
        check(CGImage.load(from: previewFile).map { max($0.width, $0.height) <= 240 } == true && CaptureHistory(folder: historyFolder).items.count == history.items.count,
              "a small preview with the edits is saved for the strip, and isn't listed as a capture")
        editsModel.load(CGImage.load(from: first)!, from: first)
        let restored = editsModel.annotations
        check(restored.count == 3 && restored[0].shape == savedArrow.shape && restored[0].color.hex == savedArrow.color.hex && restored[0].width == 6
              && restored[1].shape == savedCallout.shape, "reopening it brings the edits back, still editable")
        if case .image(let rect, let picture)? = restored.last?.shape {
            check(picture.cgImage.width == 10 && rect.width > 0, "inserted pictures come back too")
        } else {
            check(false, "inserted pictures come back too")
        }
        editsModel.annotations = []
        editsModel.saveEdits()
        check(!hasEdits(first) && !FileManager.default.fileExists(atPath: previewFile.path), "with nothing drawn, no edits file or preview is kept")
        editsModel.annotations = [savedArrow]
        spin(0.8)
        check(hasEdits(first), "edits are saved on their own shortly after a change")
        history.remove(first)
        check(!hasEdits(first) && !FileManager.default.fileExists(atPath: previewFile.path), "deleting a capture deletes its edits and preview")

        // MARK: Layouts, with the history strip (snapshots show the bars)
        let settings = AppSettings.shared
        let layoutModel = EditorModel(image: image)
        layoutModel.load(image, from: history.items[1])
        let marked = Annotation(shape: .rectangle(CGRect(x: 520, y: 300, width: 200, height: 120)), color: Theme.accent)
        layoutModel.annotations = [marked]
        layoutModel.tool = .select
        let layoutWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
                                    styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        layoutWindow.appearance = NSAppearance(named: .darkAqua)
        layoutWindow.titlebarAppearsTransparent = true
        layoutWindow.contentView = NSHostingView(rootView: EditorView(model: layoutModel, history: history))
        layoutWindow.orderFrontRegardless()
        for layout in EditorLayout.allCases {
            settings.editorLayout = layout
            layoutModel.select(marked.id)
            spin(0.6)
            check(find(CanvasScrollView.self, in: layoutWindow.contentView!) != nil && layoutModel.selectionFrame != nil, "\(layout.rawValue) layout: canvas and selection bar")
            snapshot(layoutWindow.contentView!, "layout-\(layout.rawValue).png")
        }
        check(HistoryStrip.height(for: history) == HistoryStrip.foldedHeight, "recent captures start folded into a slim bar")
        UserDefaults.standard.set(true, forKey: HistoryStrip.expandedKey)
        spin(0.4)
        check(HistoryStrip.height(for: history) == HistoryStrip.expandedHeight, "opened, the strip shows the thumbnails")
        snapshot(layoutWindow.contentView!, "history-expanded.png")
        UserDefaults.standard.removeObject(forKey: HistoryStrip.expandedKey)
        layoutWindow.close()
        settings.editorLayout = .classic
        UserDefaults.standard.removeObject(forKey: "editorLayout")
        history.removeAll()
        check(history.items.isEmpty && pngs() == 0, "the trash deletes every capture")
        try? FileManager.default.removeItem(at: historyFolder)

        // MARK: Shortcuts and the selection cursor
        check(CaptureAction.allCases.allSatisfy { UserDefaults.standard.string(forKey: $0.hotkeyKey) != nil || settings.hotkeys[$0]?.isNone == true },
              "no action has a shortcut until one is recorded")
        check(NSCursor.allowChangesInBackground(), "the region selector can show the crosshair while another app is in front")
        let shortcutsView = NSHostingView(rootView: ShortcutsSettingsView().frame(width: 460))
        let shortcutsWindow = NSWindow(contentRect: NSRect(origin: .zero, size: shortcutsView.fittingSize), styleMask: [.titled], backing: .buffered, defer: false)
        shortcutsWindow.appearance = NSAppearance(named: .darkAqua)
        shortcutsWindow.contentView = shortcutsView
        shortcutsWindow.orderFrontRegardless()
        spin(0.5)
        snapshot(shortcutsView, "settings-shortcuts.png")
        shortcutsWindow.close()

        // MARK: Quick card
        let card = QuickCard.show(image, file: nil)
        spin(0.3)
        check(card.isVisible && !card.isKeyWindow, "the quick card shows without taking focus")
        snapshot(card.contentView!, "quick-card.png")
        QuickCard.dismiss()
        check(!card.isVisible, "the quick card closes")
        // MARK: Selection color
        check(settings.selectionColorHex == nil && Color(nsColor: settings.selectionColor).hex == Color(nsColor: .controlAccentColor).hex,
              "the selection overlay follows the Mac's accent color out of the box")
        settings.selectionColorHex = "#22CC88"
        check(Color(nsColor: settings.selectionColor).hex == "#22CC88" && UserDefaults.standard.string(forKey: "selectionColor") == "#22CC88",
              "a picked selection color is used and remembered")
        settings.selectionColorHex = nil
        check(UserDefaults.standard.string(forKey: "selectionColor") == nil && Color(nsColor: settings.selectionColor).hex == Color(nsColor: .controlAccentColor).hex,
              "Use Accent Color goes back to the system's")

        // MARK: Text Card (recognition, card, panel)
        // A fake code screenshot: monospaced text on a dark editor background, the keyword in its own color, line 2 indented.
        let codeBackground = NSColor(srgbRed: 0.118, green: 0.118, blue: 0.118, alpha: 1)
        let keyword = NSColor(srgbRed: 1, green: 0.482, blue: 0.447, alpha: 1), plain = NSColor(srgbRed: 0.475, green: 0.753, blue: 1, alpha: 1)
        let codeContext = bitmap(900, 330, codeBackground.cgColor)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: codeContext, flipped: false)
        let codeFont = NSFont.monospacedSystemFont(ofSize: 30, weight: .regular)
        let advance = ("M" as NSString).size(withAttributes: [.font: codeFont]).width
        for (line, column, word, color) in [(0, 0, "func", keyword), (0, 5, "run()", plain), (0, 11, "{", plain),
                                            (1, 4, "let", keyword), (1, 8, "x", plain), (1, 10, "=", plain), (1, 12, "1", plain), (3, 0, "}", plain)] {
            (word as NSString).draw(at: CGPoint(x: 40 + CGFloat(column) * advance, y: 270 - CGFloat(line) * 70),
                                    withAttributes: [.font: codeFont, .foregroundColor: color])
        }
        NSGraphicsContext.restoreGraphicsState()
        let codeShot = codeContext.makeImage()!
        func colorAt(_ text: NSAttributedString, _ word: String) -> NSColor? {
            let range = (text.string as NSString).range(of: word)
            return range.location == NSNotFound ? nil : text.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor
        }
        let styled = TextRecognition.styledText(in: codeShot, rect: CGRect(x: 0, y: 0, width: 900, height: 330))
        let styledLines = styled?.text.string.components(separatedBy: "\n") ?? []
        check(styledLines.count == 4 && styledLines.first?.hasPrefix("func run") == true && styledLines[safe: 1]?.hasPrefix("    let") == true
              && styledLines[safe: 2] == "" && styledLines.last == "}", "Text Card reads the lines, keeps the indentation and the blank line (\(styledLines))")
        check(styled.map { $0.background.distance(to: codeBackground) < 0.05 } == true, "the card's background comes from the screenshot")
        check(styled.flatMap { colorAt($0.text, "func") }.map { $0.distance(to: keyword) < 0.12 } == true
              && styled.flatMap { colorAt($0.text, "run") }.map { $0.distance(to: plain) < 0.12 } == true
              && styled.flatMap { colorAt($0.text, "let") } == styled.flatMap { colorAt($0.text, "func") },
              "each word keeps its color from the screenshot, the same color once for every keyword")
        check(TextRecognition.styledText(in: codeShot, rect: CGRect(x: 0, y: 0, width: 4, height: 4)) == nil
              && TextRecognition.styledText(in: bitmap(200, 100, codeBackground.cgColor).makeImage()!, rect: CGRect(x: 0, y: 0, width: 200, height: 100)) == nil,
              "no text, no card")
        let erasedModel = EditorModel(image: codeShot)
        erasedModel.annotations = [Annotation(shape: .redact(rect: CGRect(x: 0, y: 0, width: 900, height: 330), style: .erase, textBoxes: []), color: Theme.accent, width: 12)]
        check(TextRecognition.styledText(in: erasedModel.textCardSource, rect: CGRect(x: 0, y: 0, width: 900, height: 330)) == nil,
              "Text Card doesn't bring back erased text")

        let sample = StyledText(text: {
            let text = NSMutableAttributedString(string: "func", attributes: [.foregroundColor: keyword])
            text.append(NSAttributedString(string: " run() {   \n    let x = 1\n}\n\n"))
            return text
        }(), background: codeBackground)
        let prepared = TextCard.prepare(sample, fontSize: 14)
        let preparedFont = prepared.text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        check(prepared.text.string == "func run() {\n    let x = 1\n}" && prepared.background == codeBackground && prepared.textColor.luminance > 0.5,
              "the card trims trailing spaces and blank lines; uncolored text gets a color that reads on the background")
        check(preparedFont?.pointSize == 14 && preparedFont?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true
              && colorAt(prepared.text, "func")?.distance(to: keyword) ?? 1 < 0.01 && prepared.text.attribute(TextCard.followsTextColor, at: 0, effectiveRange: nil) == nil
              && prepared.text.attribute(TextCard.followsTextColor, at: 5, effectiveRange: nil) != nil,
              "monospaced at the chosen size; recognized colors stay, the rest follows the text color")
        let cardStyle = TextCard.Style(background: codeBackground, windowBar: true, title: "main.swift")
        let cardSize = TextCard.size(of: prepared.text, style: cardStyle)
        if let card = TextCard.render(prepared.text, style: cardStyle) {
            check(card.width == Int(cardSize.width * 2) && card.height == Int(cardSize.height * 2), "the card renders at 2× its size")
            check(pixel(card, 1, 1)[3] == 0 && same(pixel(card, 8, card.height / 2), [30, 30, 30]), "the card has transparent rounded corners and its background inside")
            check(same(pixel(card, 2 * 24, 2 * 18), [255, 95, 87], 12), "the title bar has the window buttons")
            if let snapshotDir { try? ImageExport.writePNG(card, to: URL(fileURLWithPath: "\(snapshotDir)/text-card-render.png")) }
        } else {
            check(false, "the card renders")
        }

        let cardModel = TextCardModel(sample)
        let cardHost = NSHostingView(rootView: TextCardView(model: cardModel))
        let cardWindow = NSWindow(contentRect: NSRect(origin: .zero, size: cardHost.fittingSize), styleMask: [.titled], backing: .buffered, defer: false)
        cardWindow.appearance = NSAppearance(named: .darkAqua)
        cardWindow.contentView = cardHost
        cardWindow.orderFrontRegardless()
        spin(0.4)
        if let textView = cardModel.textView {
            check(textView.string == "func run() {\n    let x = 1\n}", "the panel shows the card's text, ready to edit")
            textView.setSelectedRange((textView.string as NSString).range(of: "run"))
            check(cardModel.hasSelection, "selecting text switches the picker to the selection")
            let green = NSColor(srgbRed: 0.2, green: 0.78, blue: 0.35, alpha: 1)
            cardModel.pick(green)
            check(colorAt(textView.attributedString(), "run") == green && colorAt(textView.attributedString(), "func")?.distance(to: keyword) ?? 1 < 0.01,
                  "picking a color recolors only the selected text")
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            cardModel.textColor = .white
            check(!cardModel.hasSelection && colorAt(textView.attributedString(), "run") == green && colorAt(textView.attributedString(), "let") == .white,
                  "the text color changes the rest; a recolored word keeps its color")
            cardModel.fontSize = 18
            check((textView.attributedString().attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 18
                  && UserDefaults.standard.double(forKey: "textCardFontSize") == 18, "the size applies to all the text and is remembered")
            cardModel.title = "main.swift"
            spin(0.2)
            snapshot(cardHost, "text-card.png")
            var finished: CGImage?
            cardModel.onFinish = { finished = $0 }
            cardModel.finish(true)
            check(finished.map { CGFloat($0.width) == TextCard.size(of: textView.attributedString(), style: cardModel.style).width * 2 } == true,
                  "Create Card hands over the card as tuned")
        } else {
            check(false, "the panel has a text view")
        }
        cardWindow.close()
        ["textCardFontSize", "textCardWindowBar"].forEach(UserDefaults.standard.removeObject(forKey:))
        settings.textCardFontSize = 14

        // MARK: Settings + icon
        // Save folder: saving into a missing folder creates it (temp folder, never the real Downloads)
        let originalFolder = settings.saveFolder
        let saveRoot = FileManager.default.temporaryDirectory.appendingPathComponent("shortty-selfcheck-save-\(UUID().uuidString)")
        let nested = saveRoot.appendingPathComponent("screens/2026", isDirectory: true)
        settings.saveFolder = nested
        check(UserDefaults.standard.string(forKey: "saveFolder") == nested.path, "the chosen folder is remembered")
        let saved = try? ImageExport.save(image, to: settings.saveFolder)
        check(saved.map { $0.deletingLastPathComponent().standardizedFileURL == nested.standardizedFileURL && CGImage.load(from: $0)?.width == image.width } == true
              && saved!.lastPathComponent.hasPrefix("shortty-") && saved!.lastPathComponent.hasSuffix("-image.png"),
              "Save writes shortty-…-image.png into the chosen folder, creating it")
        // Save in the editor closes it and says where the file went (Copy isn't checked: it would touch the real clipboard)
        editor.show(image)
        spin(1.1) // file names have a one-second timestamp
        let noticesBefore = NSApp.windows.filter { $0 is OverlayPanel && $0.isVisible }.count
        editor.model.save()
        let savedFiles = (try? FileManager.default.contentsOfDirectory(atPath: nested.path)) ?? []
        check(!editorWindow.isVisible && savedFiles.count == 2 && NSApp.windows.filter { $0 is OverlayPanel && $0.isVisible }.count == noticesBefore + 1,
              "Save in the editor writes the file, closes the editor and shows a notice")
        check(ImageExport.savedNotice(URL(fileURLWithPath: NSHomeDirectory() + "/Downloads/shortty-1-image.png")) == "Saved to ~/Downloads/shortty-1-image.png",
              "the notice names the file, with ~ for the home folder")
        // After a capture: Copy and Save happen right away, then the editor, the card, or only a notice (never the real clipboard)
        let captureBoard = NSPasteboard.withUniqueName()
        func savedCount() -> Int { (try? FileManager.default.contentsOfDirectory(atPath: nested.path))?.count ?? 0 }
        func toasts() -> [NSWindow] { NSApp.windows.filter { $0 is OverlayPanel && $0.isVisible && $0.ignoresMouseEvents } }
        settings.copyAfterCapture = true
        settings.saveAfterCapture = true
        for show in AfterCapture.allCases {
            settings.afterCapture = show
            toasts().forEach { $0.orderOut(nil) }
            spin(1.1) // file names have a one-second timestamp
            let (copiesBefore, savesBefore) = (captureBoard.changeCount, savedCount())
            CaptureController.deliver(image, pasteboard: captureBoard)
            spin(0.2)
            let cardShown = NSApp.windows.contains { $0 is OverlayPanel && $0.isVisible && !$0.ignoresMouseEvents }
            check(captureBoard.changeCount > copiesBefore && savedCount() == savesBefore + 1 && editorWindow.isVisible == (show == .editor)
                  && cardShown == (show == .card) && toasts().isEmpty == (show != .nothing),
                  "after a capture, \(show.title) + Copy + Save copies, saves and shows only that")
            if show == .nothing, let toast = toasts().first { snapshot(toast.contentView!, "toast-after-capture.png") }
            editor.close()
            QuickCard.dismiss()
        }
        settings.copyAfterCapture = false
        settings.saveAfterCapture = false
        toasts().forEach { $0.orderOut(nil) }
        let (copiesBefore, savesBefore) = (captureBoard.changeCount, savedCount())
        CaptureController.deliver(image, pasteboard: captureBoard)
        check(captureBoard.changeCount == copiesBefore && savedCount() == savesBefore && toasts().count == 1, "Nothing without Copy or Save still says it captured")
        check(UserDefaults.standard.string(forKey: "afterCapture") == "nothing" && UserDefaults.standard.object(forKey: "copyAfterCapture") as? Bool == false,
              "the after-capture choices are remembered")
        settings.afterCapture = .editor
        settings.copyAfterCapture = true
        ["afterCapture", "copyAfterCapture", "saveAfterCapture"].forEach(UserDefaults.standard.removeObject(forKey:))

        try? FileManager.default.removeItem(at: saveRoot)
        settings.saveFolder = originalFolder
        if originalFolder == AppSettings.downloadsFolder { UserDefaults.standard.removeObject(forKey: "saveFolder") }

        let general = NSHostingView(rootView: GeneralSettingsView().frame(width: 460))
        let generalWindow = NSWindow(contentRect: NSRect(origin: .zero, size: general.fittingSize), styleMask: [.titled], backing: .buffered, defer: false)
        generalWindow.appearance = NSAppearance(named: .darkAqua)
        generalWindow.contentView = general
        generalWindow.orderFrontRegardless()
        spin(0.5)
        snapshot(general, "settings-general.png")
        generalWindow.close()
        let sizes = [16, 32, 128, 256, 512].flatMap { p in [("icon_\(p)x\(p)", p), ("icon_\(p)x\(p)@2x", 2 * p)] }
        check(sizes.allSatisfy { size in // the self-check runs from the repo root
            (try? Data(contentsOf: URL(fileURLWithPath: "Shortty/Resources/Assets.xcassets/AppIcon.appiconset/\(size.0).png"))).flatMap { NSBitmapImageRep(data: $0) }?.pixelsWide == size.1
        }, "all 10 app icon PNGs at the right size")
        let barIcon = Icon.menuBar()
        check(barIcon.isTemplate && barIcon.size == NSSize(width: 18, height: 18) && Icon.menuBar(countdown: 3).size.width > 18,
              "the menu bar icon is an 18 pt template image, wider while counting down")
        if let snapshotDir { // 8× on white, to look at the outline
            let big = NSImage(size: NSSize(width: 144, height: 144), flipped: false) { rect in
                NSColor.white.setFill()
                rect.fill()
                barIcon.draw(in: rect)
                return true
            }
            try? big.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }?
                .write(to: URL(fileURLWithPath: "\(snapshotDir)/menubar-icon.png"))
        }

        // MARK: Regular app while a window is open
        // The editor puts Shortty in the Dock and ⌘Tab (its own menu bar, so ⌘, opens Settings); closing it goes back
        // to the menu bar only. Last, because the observers stay for the rest of the run.
        NSApp.windows.filter { $0 !== editorWindow && AppPresence.isAppWindow($0) }.forEach { $0.orderOut(nil) } // earlier checks' windows
        AppPresence.start()
        editor.show(image)
        spin(1.5)
        check(NSApp.activationPolicy() == .regular && editorWindow.isKeyWindow,
              "an open editor makes Shortty a regular app and keeps keyboard focus (policy \(NSApp.activationPolicy().rawValue), key \(editorWindow.isKeyWindow))")
        check(editor.handle(key("w", kVK_ANSI_W, in: editorWindow, flags: .command)) && !editorWindow.isVisible, "⌘W closes the editor")
        spin(0.3)
        check(NSApp.activationPolicy() == .accessory, "closing the last window leaves only the menu bar icon")

        finish()
    }

    static func finish() -> Never {
        print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
