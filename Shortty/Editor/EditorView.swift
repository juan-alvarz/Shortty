import SwiftUI

struct EditorView: View {
    @Bindable var model: EditorModel

    var body: some View {
        VStack(spacing: 0) {
            EditorToolbar(model: model)
                .zIndex(1) // tooltips hang below the bar, over the canvas
            EditorCanvas(model: model)
                .background(Image(nsImage: Theme.checkerboard).resizable(resizingMode: .tile))
                .overlay(alignment: .topTrailing) {
                    if model.showsOptions {
                        ToolOptionsBar(model: model).padding(12)
                    }
                }
                .overlay(alignment: .bottom) {
                    if let toast = model.toast {
                        Toast(text: toast).padding(.bottom, 18)
                    }
                }
                .task(id: model.toast) {
                    guard let shown = model.toast else { return }
                    try? await Task.sleep(for: .seconds(2.5))
                    if model.toast == shown { model.toast = nil }
                }
        }
        .frame(minWidth: 780, minHeight: 320)
    }
}

// MARK: - Toolbar

private struct EditorToolbar: View {
    @Bindable var model: EditorModel

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 30, height: 30)
                .help("Shortty")

            divider
            ToolButton(icon: .copy, tooltip: "Copy", shortcut: "⌘C") { model.copy() }
            ToolButton(icon: .save, tooltip: "Save to Downloads", shortcut: "⌘S") { model.save() }
            DragHandle(model: model)
            InsertImageButton(model: model)
            divider
            tool(.select, icon: .cursor, "Select", key: "V")
            tool(.pencil, icon: .pencil, "Pencil", key: "P")
            tool(.arrow, icon: .arrow, "Arrow", key: "A")
            tool(.text, icon: .text, "Text", key: "T")
            tool(.rectangle, icon: .rectangle, "Rectangle", key: "R")
            tool(.ellipse, icon: .ellipse, "Ellipse", key: "O")
            divider
            tool(.magnifier, icon: .magnifier, "Magnifier", key: "M")
            tool(.blur, icon: .blur, "Blur", key: "B")
            tool(.spotlight, icon: .spotlight, "Spotlight", key: "S")
            tool(.recognizeText, icon: .recognizeText, "Recognize Text", key: "X")
            divider
            ColorButton(model: model)
            BackdropButton(model: model)

            Spacer()

            Stat(value: model.pixelSize, label: "Image size")
            divider
            Stat(value: "\(Int((model.displayedZoom * 100).rounded()))%", label: "Zoom", tooltip: "Fit to window", shortcut: "⌘0") {
                model.zoomToFit()
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(Theme.chrome)
    }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: 24)
    }

    private func tool(_ tool: EditorModel.Tool, icon: IconKind, _ name: String, key: String) -> some View {
        ToolButton(icon: icon, tooltip: name, shortcut: key, selected: model.tool == tool) { model.tool = tool }
    }
}

private struct ToolButton: View {
    let icon: IconKind
    let tooltip: String
    var shortcut: String? = nil
    var selected = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Icon(kind: icon)
                .foregroundStyle(selected || hovering ? Color.white : Theme.chromeText)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(selected ? 0.16 : hovering ? 0.08 : 0)))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .tooltip(tooltip, shortcut: shortcut, visible: hovering)
    }
}

/// One square showing the current color; click for the palette. Picking a color also recolors the selection.
private struct ColorButton: View {
    @Bindable var model: EditorModel
    @State private var hovering = false
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            RoundedRectangle(cornerRadius: 4)
                .fill(model.color)
                .frame(width: 16, height: 16)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.35), lineWidth: 1))
                .frame(width: 30, height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(hovering || open ? 0.08 : 0)))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .tooltip("Color", shortcut: nil, visible: hovering && !open)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(spacing: 12) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 8), count: 5), spacing: 8) {
                    ForEach(Theme.palette, id: \.self) { color in
                        Swatch(color: color, selected: model.color.hex == color.hex) {
                            model.setColor(color)
                            open = false
                        }
                    }
                }
                Divider()
                RGBPicker(model: model)
            }
            .padding(12)
            .frame(width: 176)
        }
    }
}

private struct Swatch: View {
    let color: Color
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 5)
                .fill(color)
                .frame(width: 24, height: 24)
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(selected ? 0.95 : hovering ? 0.5 : 0.15), lineWidth: selected ? 2 : 1))
                .scaleEffect(hovering ? 1.1 : 1)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// R, G, B sliders + hex field + screen eyedropper. A whole slider drag is one undo step.
private struct RGBPicker: View {
    @Bindable var model: EditorModel
    @State private var rgb: [Double] = [0, 0, 0]
    @State private var hex = ""
    @State private var annotationsBeforeDrag: [Annotation]?

    var body: some View {
        VStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { channel in
                ChannelSlider(label: ["R", "G", "B"][channel], value: $rgb[channel], colors: gradient(for: channel)) { editing in
                    if editing {
                        annotationsBeforeDrag = model.annotations
                    } else if let before = annotationsBeforeDrag {
                        model.recordChange(from: before)
                        annotationsBeforeDrag = nil
                    }
                }
            }
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(rgb: rgb))
                    .frame(width: 20, height: 20)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.3), lineWidth: 1))
                TextField("", text: $hex)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .onSubmit {
                        if let color = Color(hex: hex) { model.setColor(color) } else { hex = model.color.hex }
                    }
                Button {
                    let model = model
                    NSColorSampler().show { picked in // completion isn't main-actor; hop back with plain values
                        guard let picked = picked?.usingColorSpace(.sRGB) else { return }
                        let rgb = [picked.redComponent, picked.greenComponent, picked.blueComponent].map { Double($0) * 255 }
                        Task { @MainActor in model.setColor(Color(rgb: rgb)) }
                    }
                } label: {
                    Icon(kind: .eyedropper, size: 17).frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("Pick a color from the screen")
            }
        }
        .onAppear { load(model.color) }
        .onChange(of: model.color.hex) { load(model.color) }
        .onChange(of: rgb) {
            guard Color(rgb: rgb).hex != model.color.hex else { return }
            model.setColor(Color(rgb: rgb), undoable: annotationsBeforeDrag == nil)
        }
    }

    private func load(_ color: Color) {
        rgb = color.rgb
        hex = color.hex
    }

    /// The track shows what this channel would do from 0 to 255 with the other two fixed.
    private func gradient(for channel: Int) -> [Color] {
        [0.0, 255.0].map { value in
            var stop = rgb
            stop[channel] = value
            return Color(rgb: stop)
        }
    }
}

private struct ChannelSlider: View {
    let label: String
    @Binding var value: Double
    let colors: [Color]
    let onEditingChanged: (Bool) -> Void
    @State private var dragging = false

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 10)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 1))
                        .frame(height: 8)
                    Circle()
                        .fill(.white)
                        .frame(width: 14, height: 14)
                        .shadow(color: .black.opacity(0.4), radius: 1.5, y: 0.5)
                        .offset(x: value / 255 * (geo.size.width - 14))
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    if !dragging {
                        dragging = true
                        onEditingChanged(true)
                    }
                    value = ((drag.location.x - 7) / (geo.size.width - 14) * 255).rounded().clamped(to: 0...255)
                }.onEnded { _ in
                    dragging = false
                    onEditingChanged(false)
                })
            }
            .frame(height: 16)
            Text("\(Int(value))")
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
        }
    }
}

// MARK: - Tool options

/// Floating panel (like Shottr's) for the active drawing tool or the selection: thickness (font size for text),
/// plus the style for arrows and text.
private struct ToolOptionsBar: View {
    @Bindable var model: EditorModel
    @State private var annotationsBeforeDrag: [Annotation]?

    var body: some View {
        HStack(spacing: 12) {
            if model.showsWidthSlider {
                WidthSlider(
                    value: Binding(get: { model.currentWidth }, set: { model.setWidth($0, undoable: false) }),
                    range: model.currentWidthRange,
                    help: sliderHelp
                ) { editing in
                    // One undo step per drag.
                    if editing {
                        annotationsBeforeDrag = model.annotations
                    } else if let before = annotationsBeforeDrag {
                        model.recordChange(from: before)
                        annotationsBeforeDrag = nil
                    }
                }
                .frame(width: 96)
            }

            if model.optionsTool == .blur {
                Segments(items: RedactStyle.allCases, selected: model.redactStyle) { style in
                    Text(style.title).font(.system(size: 11, weight: .medium)).padding(.horizontal, 7)
                } action: { model.setRedactStyle($0) }
            }

            if model.optionsTool == .spotlight || model.optionsTool == .magnifier {
                Segments(items: AreaShape.allCases, selected: model.optionsTool == .spotlight ? model.spotlightShape : model.magnifierShape) { shape in
                    Icon(kind: shape.icon, size: 16).frame(width: 26)
                } action: { model.setAreaShape($0) }
            }

            if model.showsArrowStyles {
                HStack(spacing: 2) {
                    ForEach(ArrowStyle.allCases, id: \.self) { style in
                        ArrowStyleButton(style: style, selected: model.arrowStyle == style) { model.setArrowStyle(style) }
                    }
                }
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 7).fill(.black.opacity(0.25)))
            }

            if model.showsTextStyles {
                HStack(spacing: 2) {
                    ForEach(TextStyle.allCases, id: \.self) { style in
                        TextStyleButton(style: style, selected: model.textStyle == style) { model.setTextStyle(style) }
                    }
                }
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 7).fill(.black.opacity(0.25)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.chrome))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.1)))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }

    private var sliderHelp: String {
        switch model.optionsTool {
        case .text: "Text size"
        case .blur: "Blur strength"
        case .spotlight: "Dim"
        default: "Thickness"
        }
    }
}

/// A row of mutually exclusive choices (Blur / Blur Text / …, rectangle / ellipse).
private struct Segments<Item: Hashable, Label: View>: View {
    let items: [Item]
    let selected: Item
    @ViewBuilder let label: (Item) -> Label
    let action: (Item) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.self) { item in
                SegmentButton(selected: item == selected) { label(item) } action: { action(item) }
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(.black.opacity(0.25)))
    }
}

private struct SegmentButton<Label: View>: View {
    let selected: Bool
    @ViewBuilder let label: () -> Label
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label()
                .frame(height: 22)
                .foregroundStyle(selected || hovering ? Color.white : Theme.chromeText)
                .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(selected ? 0.18 : hovering ? 0.08 : 0)))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Short confirmation at the bottom of the canvas.
private struct Toast: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color(white: 0.08).opacity(0.92)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
            .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
            .transition(.opacity)
    }
}

/// Thickness slider with a wedge track, thin to thick.
private struct WidthSlider: View {
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    var step: CGFloat = 1
    let help: String
    let onEditingChanged: (Bool) -> Void
    @State private var dragging = false

    var body: some View {
        GeometryReader { geo in
            let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            ZStack(alignment: .leading) {
                Wedge().fill(.white.opacity(0.22)).frame(height: 10)
                Capsule()
                    .fill(.white)
                    .frame(width: 6, height: 18)
                    .shadow(color: .black.opacity(0.4), radius: 1.5, y: 0.5)
                    .offset(x: fraction * (geo.size.width - 6))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                if !dragging {
                    dragging = true
                    onEditingChanged(true)
                }
                let fraction = ((drag.location.x - 3) / (geo.size.width - 6)).clamped(to: 0...1)
                value = ((range.lowerBound + fraction * (range.upperBound - range.lowerBound)) / step).rounded() * step
            }.onEnded { _ in
                dragging = false
                onEditingChanged(false)
            })
        }
        .frame(height: 22)
        .help(help)
    }
}

private struct Wedge: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY - 1))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY + 1))
        path.closeSubpath()
        return path
    }
}

/// Style button whose icon is drawn by the same code that draws real arrows.
private struct ArrowStyleButton: View {
    let style: ArrowStyle
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Canvas { context, size in
                let thin = style == .line || style == .double
                let arrow = ArrowShape(start: CGPoint(x: 4, y: size.height / 2), end: CGPoint(x: size.width - 4, y: size.height / 2),
                                       bend: 0, style: style, width: thin ? 1.6 : 2.4)
                if let fill = arrow.fill { context.fill(Path(fill), with: .foreground) }
                if let stroke = arrow.stroke {
                    context.stroke(Path(stroke), with: .foreground,
                                   style: StrokeStyle(lineWidth: thin ? arrow.strokeWidth : 1.3, lineCap: .round, lineJoin: .round))
                }
            }
            .frame(width: 30, height: 22)
            .foregroundStyle(selected || hovering ? Color.white : Theme.chromeText)
            .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(selected ? 0.18 : hovering ? 0.08 : 0)))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(style.title)
    }
}

// MARK: - Insert picture

/// Paste, pick from Finder, or capture a new area into the current picture. (Dropping files on the canvas works too.)
private struct InsertImageButton: View {
    @Bindable var model: EditorModel
    @State private var hovering = false
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            Icon(kind: .insertImage)
                .foregroundStyle(hovering || open ? Color.white : Theme.chromeText)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(hovering || open ? 0.08 : 0)))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .tooltip("Insert picture", shortcut: nil, visible: hovering && !open)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                MenuRow(title: "Paste from Clipboard", shortcut: "⌘V") {
                    open = false
                    if model.insertImages(from: .general) == 0 { model.toast = "No picture on the clipboard" }
                }
                MenuRow(title: "Choose from Finder…", shortcut: nil) {
                    open = false
                    chooseFromFinder()
                }
                MenuRow(title: "Capture New Area…", shortcut: nil) {
                    open = false
                    model.onInsertCapture?()
                }
            }
            .padding(6)
            .frame(width: 220)
        }
    }

    private func chooseFromFinder() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.message = "Choose pictures to add"
        NSApp.activate() // the user just clicked, so macOS allows it; the open panel needs an active app
        panel.begin { response in
            guard response == .OK else { return }
            let pictures = panel.urls.compactMap { CGImage.load(from: $0) }
            for (i, picture) in pictures.enumerated() {
                model.insertImage(picture, centeredAt: CGPoint(x: model.image.bounds.midX + CGFloat(i) * 24, y: model.image.bounds.midY + CGFloat(i) * 24))
            }
        }
    }
}

private struct MenuRow: View {
    let title: String
    let shortcut: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 13))
                Spacer()
                if let shortcut { Text(shortcut).font(.system(size: 12)).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 5).fill(hovering ? Color.white.opacity(0.1) : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Backdrop

/// The screenshot on a gradient card. Off by default; pick a gradient to turn it on.
private struct BackdropButton: View {
    @Bindable var model: EditorModel
    @State private var hovering = false
    @State private var open = false

    var body: some View {
        let active = model.backdrop != nil
        Button { open.toggle() } label: {
            Icon(kind: .backdrop)
                .foregroundStyle(active || hovering || open ? Color.white : Theme.chromeText)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(active ? 0.16 : hovering || open ? 0.08 : 0)))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .tooltip("Backdrop", shortcut: nil, visible: hovering && !open)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            BackdropPicker(model: model).padding(12).frame(width: 236)
        }
    }
}

struct BackdropPicker: View {
    @Bindable var model: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(64), spacing: 8), count: 3), spacing: 8) { // None + 8 gradients = 3×3
                BackdropSwatch(colors: nil, name: "None", selected: model.backdrop == nil) { model.backdrop = nil }
                ForEach(Backdrop.presets.indices, id: \.self) { index in
                    BackdropSwatch(colors: Backdrop.presets[index].colors, name: Backdrop.presets[index].name,
                                   selected: model.backdrop?.preset == index) {
                        var backdrop = model.backdrop ?? Backdrop()
                        backdrop.preset = index
                        model.backdrop = backdrop
                    }
                }
            }
            if model.backdrop != nil {
                setting("Padding", \.padding, Backdrop.paddingRange)
                setting("Corners", \.cornerRadius, Backdrop.cornerRange)
                setting("Shadow", \.shadow, Backdrop.shadowRange)
            }
        }
    }

    private func setting(_ title: String, _ key: WritableKeyPath<Backdrop, CGFloat>, _ range: ClosedRange<CGFloat>) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).frame(width: 56, alignment: .leading)
            WidthSlider(value: Binding(get: { model.backdrop?[keyPath: key] ?? range.lowerBound },
                                       set: { model.backdrop?[keyPath: key] = $0 }),
                        range: range, step: (range.upperBound - range.lowerBound) / 100, help: title) { _ in }
        }
    }
}

private struct BackdropSwatch: View {
    let colors: [Color]?
    let name: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if let colors {
                    RoundedRectangle(cornerRadius: 6).fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    RoundedRectangle(cornerRadius: 2).fill(Color(white: 0.15)).frame(width: 32, height: 20) // the "screenshot"
                } else {
                    RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.2))
                    Text("None").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 64, height: 40)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(selected ? 0.95 : hovering ? 0.5 : 0.12), lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .help(name)
    }
}

/// Text variant preview: a bubble with a pointer, a filled label, or bare letters.
private struct TextStyleButton: View {
    let style: TextStyle
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let ink = selected || hovering ? Color.white : Theme.chromeText
        Button(action: action) {
            Canvas { context, size in
                let box = CGRect(x: 4, y: style == .callout ? 3 : 5, width: size.width - 8, height: size.height - 10)
                if style != .plain {
                    context.fill(Path(roundedRect: box, cornerRadius: 3), with: .color(ink))
                }
                if style == .callout {
                    var pointer = Path()
                    pointer.addLines([CGPoint(x: box.minX + 5, y: box.maxY - 1), CGPoint(x: box.minX + 3, y: box.maxY + 5), CGPoint(x: box.minX + 10, y: box.maxY - 1)])
                    context.fill(pointer, with: .color(ink))
                }
                let letters = Text("Aa").font(.system(size: 10, weight: .bold)).foregroundStyle(style == .plain ? ink : Theme.chrome)
                context.draw(letters, at: CGPoint(x: box.midX, y: box.midY))
            }
            .frame(width: 30, height: 22)
            .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(selected ? 0.18 : hovering ? 0.08 : 0)))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(style.title)
    }
}

private struct Stat: View {
    let value: String
    let label: String
    var tooltip: String? = nil
    var shortcut: String? = nil
    var action: (() -> Void)? = nil
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 12, weight: .semibold)).foregroundStyle(hovering && action != nil ? .white : Theme.chromeText)
            Text(label).font(.system(size: 10)).foregroundStyle(Theme.chromeSubtext)
        }
        .fixedSize()
        .monospacedDigit()
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { action?() }
        .tooltip(tooltip, shortcut: shortcut, visible: hovering && action != nil)
    }
}

// MARK: - Tooltip

extension View {
    /// Shows a small dark label under the view shortly after `visible` turns true.
    func tooltip(_ text: String?, shortcut: String?, visible: Bool) -> some View {
        modifier(TooltipModifier(text: text, shortcut: shortcut, visible: visible))
    }
}

private struct TooltipModifier: ViewModifier {
    let text: String?
    let shortcut: String?
    let visible: Bool
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .task(id: visible) {
                shown = false
                guard visible, text != nil else { return }
                try? await Task.sleep(for: .milliseconds(350))
                if !Task.isCancelled { shown = true }
            }
            .overlay(alignment: .top) {
                if shown, let text {
                    HStack(spacing: 6) {
                        Text(text).font(.system(size: 11, weight: .medium))
                        if let shortcut { Text(shortcut).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)) }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.12)))
                    .fixedSize()
                    .offset(y: 36)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.12), value: shown)
    }
}
