import SwiftUI

/// The editor: the same parts in one of four arrangements (Settings → Layout), with recent captures along the bottom.
struct EditorView: View {
    @Bindable var model: EditorModel
    var history = CaptureHistory.shared
    private let settings = AppSettings.shared

    var body: some View {
        let layout = settings.editorLayout
        VStack(spacing: 0) {
            switch layout {
            case .classic:
                EditorToolbar(model: model)
                    .zIndex(1) // tooltips hang below the bar, over the canvas
                canvas(layout)
                    .overlay(alignment: .topTrailing) {
                        if model.showsOptions { ToolOptions(model: model).floating().padding(12) }
                    }
            case .twoRows:
                EditorToolbar(model: model, compact: true).zIndex(2)
                OptionsStrip(model: model).zIndex(1)
                canvas(layout)
            case .sidebars:
                SlimBar(model: model).zIndex(2)
                HStack(spacing: 0) {
                    ToolRail(model: model).zIndex(1)
                    canvas(layout)
                    Inspector(model: model)
                }
            case .canvasFirst:
                canvas(layout).overlay { FloatingChrome(model: model) }
            }
            if settings.showsHistory, !history.items.isEmpty {
                HistoryStrip(model: model, history: history)
            }
        }
        .frame(minWidth: layout.minWidth, minHeight: 320)
        .background(Theme.chrome) // also behind the title bar, which Canvas first leaves bare
    }

    private func canvas(_ layout: EditorLayout) -> some View {
        EditorCanvas(model: model)
            .background(Image(nsImage: Theme.checkerboard).resizable(resizingMode: .tile))
            .overlay { SelectionBarOverlay(model: model) }
            .overlay(alignment: .bottom) {
                if let toast = model.toast {
                    Toast(text: toast).padding(.bottom, layout == .canvasFirst ? 116 : 18) // clear of the dock
                }
            }
            .task(id: model.toast) {
                guard let shown = model.toast else { return }
                try? await Task.sleep(for: .seconds(2.5))
                if model.toast == shown { model.toast = nil }
            }
    }
}

extension EditorLayout {
    /// The narrowest window that still fits the layout's bars.
    var minWidth: CGFloat {
        switch self {
        case .classic, .twoRows: 920
        case .sidebars: 760
        case .canvasFirst: 680
        }
    }

    /// Room the bars take around the picture, for sizing the window to a new capture.
    var chrome: CGSize {
        switch self {
        case .classic: CGSize(width: 0, height: 52)
        case .twoRows: CGSize(width: 0, height: 92)
        case .sidebars: CGSize(width: 54 + 250, height: 44)
        case .canvasFirst: .zero
        }
    }
}

// MARK: - Tools

/// Every tool in toolbar order, with its key (EditorWindowController maps the same keys).
private let drawingTools: [(tool: EditorModel.Tool, icon: IconKind, name: String, key: String)] = [
    (.select, .cursor, "Select", "V"), (.pencil, .pencil, "Pencil", "P"), (.arrow, .arrow, "Arrow", "A"), (.text, .text, "Text", "T"),
    (.rectangle, .rectangle, "Rectangle", "R"), (.ellipse, .ellipse, "Ellipse", "O"), (.step, .step, "Numbered steps", "N"),
]
private let effectTools: [(tool: EditorModel.Tool, icon: IconKind, name: String, key: String)] = [
    (.magnifier, .magnifier, "Magnifier", "M"), (.blur, .blur, "Blur", "B"), (.spotlight, .spotlight, "Spotlight", "S"),
    (.recognizeText, .recognizeText, "Recognize Text", "X"), (.textCard, .textCard, "Text Card", "K"), (.crop, .crop, "Crop", "C"),
    (.ruler, .ruler, "Ruler", "U"),
]

extension EditorModel.Tool {
    var name: String { (drawingTools + effectTools).first { $0.tool == self }?.name ?? "" }
}

/// The tool buttons in two groups, laid out by the enclosing stack (a row, the sidebar rail, or the dock).
private struct ToolButtons: View {
    @Bindable var model: EditorModel
    var axis = Axis.horizontal

    var body: some View {
        group(drawingTools)
        ChromeDivider(axis: axis)
        group(effectTools)
    }

    private func group(_ tools: [(tool: EditorModel.Tool, icon: IconKind, name: String, key: String)]) -> some View {
        ForEach(tools, id: \.key) { item in
            ToolButton(icon: item.icon, tooltip: item.name, shortcut: item.key, selected: model.tool == item.tool,
                       badge: model.showsShortcutHints ? item.key : nil) { model.tool = item.tool }
        }
    }
}

/// Copy, Save, Drag, Pin and Insert: what you do with the finished picture.
private struct OutputButtons: View {
    @Bindable var model: EditorModel

    var body: some View {
        ToolButton(icon: .copy, tooltip: "Copy", shortcut: "⌘C", badge: model.showsShortcutHints ? "⌘C" : nil) { model.copy() }
        ToolButton(icon: .save, tooltip: "Save to \(AppSettings.shared.saveFolder.lastPathComponent)", shortcut: "⌘S",
                   badge: model.showsShortcutHints ? "⌘S" : nil) { model.save() }
        DragHandle(model: model)
        ToolButton(icon: .pin, tooltip: "Pin to screen", shortcut: nil) { model.pin() }
        InsertImageButton(model: model)
    }
}

private struct AppMark: View {
    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: 30, height: 30)
            .help("Shortty")
    }
}

/// A hairline between groups: vertical in a row, horizontal in a column.
private struct ChromeDivider: View {
    var axis = Axis.horizontal

    var body: some View {
        Rectangle().fill(.white.opacity(0.12)).frame(width: axis == .horizontal ? 1 : 24, height: axis == .horizontal ? 24 : 1)
    }
}

private struct Stats: View {
    @Bindable var model: EditorModel

    var body: some View {
        Stat(value: model.pixelSize, label: "Image size")
        ChromeDivider()
        Stat(value: "\(Int((model.displayedZoom * 100).rounded()))%", label: "Zoom", tooltip: "Fit to window", shortcut: "⌘0") {
            model.zoomToFit()
        }
    }
}

// MARK: - Layouts

/// Classic and Two rows: everything in one bar. Two rows moves the color and the stats to the options strip.
private struct EditorToolbar: View {
    @Bindable var model: EditorModel
    var compact = false

    var body: some View {
        HStack(spacing: 6) {
            AppMark()
            ChromeDivider()
            OutputButtons(model: model)
            ChromeDivider()
            ToolButtons(model: model)
            ChromeDivider()
            if !compact { ColorButton(model: model) }
            BackdropButton(model: model)
            Spacer()
            if !compact { Stats(model: model) }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(Theme.chrome)
    }
}

/// Two rows: the current tool's options always in the same place, colors one click away.
private struct OptionsStrip: View {
    @Bindable var model: EditorModel

    var body: some View {
        HStack(spacing: 12) {
            Text(model.optionsTool.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.chromeText)
                .frame(width: 92, alignment: .leading)
            if model.showsOptions {
                ToolOptions(model: model)
            } else {
                Text("Pick a tool, or select something to change it").font(.system(size: 12)).foregroundStyle(.white.opacity(0.45))
            }
            Spacer(minLength: 8)
            ChromeDivider()
            HStack(spacing: 5) {
                ForEach(Theme.palette, id: \.self) { color in
                    Swatch(color: color, selected: model.color.hex == color.hex, size: 16) { model.setColor(color) }
                }
            }
            ChromeDivider()
            Stats(model: model)
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background(Theme.chrome)
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.07)).frame(height: 1) }
    }
}

/// Sidebars: output actions in a slim top bar, with Copy as the main button.
private struct SlimBar: View {
    @Bindable var model: EditorModel

    var body: some View {
        HStack(spacing: 8) {
            AppMark()
            Text(model.pixelSize).font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.chromeText)
            Spacer()
            Stat(value: "\(Int((model.displayedZoom * 100).rounded()))%", label: "Zoom", tooltip: "Fit to window", shortcut: "⌘0") {
                model.zoomToFit()
            }
            ChromeDivider()
            DragHandle(model: model)
            ToolButton(icon: .pin, tooltip: "Pin to screen", shortcut: nil) { model.pin() }
            InsertImageButton(model: model)
            ChromeDivider()
            PanelButton(title: "Save") { model.save() }
                .help("Save to \(AppSettings.shared.saveFolder.lastPathComponent)  ⌘S")
            PanelButton(title: "Copy", prominent: true) { model.copy() }
                .help("Copy  ⌘C")
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(Theme.chrome)
    }
}

/// Sidebars: the tools in a column on the left.
private struct ToolRail: View {
    @Bindable var model: EditorModel

    var body: some View {
        VStack(spacing: 6) {
            ToolButtons(model: model, axis: .vertical)
            Spacer()
        }
        .padding(.vertical, 12)
        .frame(width: 54)
        .background(Theme.chrome)
        .overlay(alignment: .trailing) { Rectangle().fill(.white.opacity(0.07)).frame(width: 1) }
        .environment(\.tooltipEdge, .trailing)
    }
}

/// Sidebars: everything about the current tool or selection on the right, with room to grow.
private struct Inspector: View {
    @Bindable var model: EditorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                section(model.optionsTool.name) {
                    if model.showsOptions {
                        ToolOptions(model: model, vertical: true)
                    } else {
                        Text("Pick a tool, or select something to change it").font(.system(size: 12)).foregroundStyle(.white.opacity(0.45))
                    }
                }
                section("Color") {
                    PaletteGrid(model: model)
                    RGBPicker(model: model)
                }
                section("Backdrop") { BackdropOptions(model: model) }
            }
            .padding(14)
        }
        .frame(width: 250)
        .background(Theme.chrome)
        .overlay(alignment: .leading) { Rectangle().fill(.white.opacity(0.07)).frame(width: 1) }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).kerning(0.6).foregroundStyle(.white.opacity(0.45))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Canvas first: the picture fills the window; stats and output actions float at the top, tools in a dock at the bottom.
private struct FloatingChrome: View {
    @Bindable var model: EditorModel

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top) {
                HStack(spacing: 8) { Stats(model: model) }
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .floatingPanel()
                Spacer()
                HStack(spacing: 6) { OutputButtons(model: model) }
                    .padding(6)
                    .floatingPanel()
            }
            Spacer()
            if model.showsOptions { ToolOptions(model: model).floating() }
            HStack(spacing: 6) {
                ToolButtons(model: model)
                ChromeDivider()
                ColorButton(model: model)
                BackdropButton(model: model)
            }
            .padding(6)
            .floatingPanel(cornerRadius: 14)
            .environment(\.tooltipEdge, .top)
        }
        .padding(14)
    }
}

extension View {
    /// The dark card behind floating bars and panels.
    func floatingPanel(cornerRadius: CGFloat = 10) -> some View {
        background(RoundedRectangle(cornerRadius: cornerRadius).fill(Theme.chrome))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(.white.opacity(0.1)))
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }
}

// MARK: - Selection bar

/// Floats just above the selection (below it near the top edge), clear of the canvas sides.
private struct SelectionBarOverlay: View {
    @Bindable var model: EditorModel

    var body: some View {
        GeometryReader { geo in
            if let frame = model.selectionFrame {
                let half: CGFloat = 116
                SelectionBar(model: model)
                    .position(x: frame.midX.clamped(to: half...max(half, geo.size.width - half)),
                              y: frame.minY > 60 ? frame.minY - 28 : min(frame.maxY + 28, geo.size.height - 28))
            }
        }
    }
}

/// Color, duplicate, bring to front, send to back and delete for the selected shape or picture.
private struct SelectionBar: View {
    @Bindable var model: EditorModel

    var body: some View {
        HStack(spacing: 4) {
            if model.selectedAnnotation?.isImage == false {
                ColorButton(model: model)
                ChromeDivider()
            }
            ToolButton(icon: .duplicate, tooltip: "Duplicate", shortcut: "⌘D") { model.duplicateSelection() }
            ToolButton(icon: .bringToFront, tooltip: "Bring to front", shortcut: "⌘]") { model.bringSelectionToFront() }
            ToolButton(icon: .sendToBack, tooltip: "Send to back", shortcut: "⌘[") { model.sendSelectionToBack() }
            ToolButton(icon: .trash, tooltip: "Delete", shortcut: "⌫") { model.deleteSelection() }
        }
        .padding(4)
        .floatingPanel(cornerRadius: 9)
    }
}

// MARK: - History strip

/// Recent captures. Folded into a slim bar with an arrow and the count until you open it; then click one to open it,
/// ⌘-click to pick several, drag one (or the picked ones) into any app, × deletes one, the trash deletes them all.
/// Remembers whether it's open.
struct HistoryStrip: View {
    static let expandedKey = "historyExpanded"
    static let foldedHeight: CGFloat = 26
    static let expandedHeight: CGFloat = 78

    @Bindable var model: EditorModel
    let history: CaptureHistory
    @AppStorage(expandedKey) private var expanded = false
    @State private var confirmingClear = false
    @State private var picked: Set<URL> = []

    /// What a drag from `url` carries: every picked capture (in strip order) when it's one of them, else just it.
    static func dragged(_ url: URL, picked: Set<URL>, in items: [URL]) -> [URL] {
        picked.contains(url) ? items.filter(picked.contains) : [url]
    }

    var body: some View {
        Group {
            if expanded { strip } else { folded }
        }
        .background(Theme.chrome)
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.07)).frame(height: 1) }
        .environment(\.tooltipEdge, .top)
    }

    private var folded: some View {
        HoverButton { expanded = true } label: { hovering in
            HStack(spacing: 6) {
                Icon(kind: .chevronUp, size: 12)
                Text("\(history.items.count) recent capture\(history.items.count == 1 ? "" : "s")").font(.system(size: 11, weight: .medium))
                Spacer()
            }
            .foregroundStyle(hovering ? Color.white : Theme.chromeText)
            .padding(.horizontal, 16)
            .frame(height: Self.foldedHeight)
            .contentShape(Rectangle())
        }
        .help("Show recent captures")
    }

    private var strip: some View {
        HStack(spacing: 10) {
            HoverButton { expanded = false } label: { hovering in
                Icon(kind: .chevronUp, size: 12)
                    .rotationEffect(.degrees(180))
                    .foregroundStyle(hovering ? Color.white : Theme.chromeText)
                    .frame(width: 24, height: 50)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(hovering ? 0.08 : 0)))
            }
            .help("Hide recent captures")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(history.items, id: \.self) { url in
                        HistoryThumb(url: url, current: url == model.sourceFile, picked: picked.contains(url),
                                     revision: url == model.sourceFile ? model.savedRevision : 0) { modifiers in
                            if modifiers.contains(.command) { return picked.formSymmetricDifference([url]) }
                            picked = []
                            guard let image = CGImage.load(from: url) else { return history.remove(url) }
                            model.load(image, from: url)
                        } dragged: {
                            Self.dragged(url, picked: picked, in: history.items)
                        } remove: {
                            history.remove(url)
                        }
                    }
                }
                .padding(.trailing, 16)
            }
            ChromeDivider()
            if confirmingClear {
                PanelButton(title: "Delete all \(history.items.count)", prominent: true) {
                    history.removeAll()
                    confirmingClear = false
                }
                .task {
                    try? await Task.sleep(for: .seconds(3))
                    confirmingClear = false
                }
            } else {
                ToolButton(icon: .trash, tooltip: "Delete all recent captures", shortcut: nil) { confirmingClear = true }
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 16)
        .frame(height: Self.expandedHeight)
    }

    /// What the strip adds to the window's height right now.
    static func height(for history: CaptureHistory) -> CGFloat {
        guard AppSettings.shared.showsHistory, !history.items.isEmpty else { return 0 }
        return UserDefaults.standard.bool(forKey: expandedKey) ? expandedHeight : foldedHeight
    }
}

/// Shows the capture with its edits (its saved preview) when there are any; `revision` reloads it after a save.
private struct HistoryThumb: View {
    let url: URL
    let current: Bool
    let picked: Bool
    let revision: Int
    let click: (NSEvent.ModifierFlags) -> Void
    let dragged: () -> [URL]
    let remove: () -> Void
    @State private var thumbnail: CGImage?
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let thumbnail {
                        Image(decorative: thumbnail, scale: 1).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Color.white.opacity(0.06)
                    }
                }
                .frame(width: 84, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(current ? Theme.accent : .white.opacity(picked ? 1 : hovering ? 0.45 : 0.12), lineWidth: current || picked ? 2 : 1))
                .overlay(DragSource(onClick: click, onHover: { hovering = $0 }, files: dragged))
                if hovering {
                    Button(action: remove) {
                        Icon(kind: .close, size: 10)
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(.black.opacity(0.75)))
                    }
                    .buttonStyle(.plain)
                    .padding(3)
                    .help("Delete this capture")
                }
            }
            Text(age).font(.system(size: 9.5).monospacedDigit()).foregroundStyle(.white.opacity(0.45))
        }
        .help("Click to open, ⌘-click to pick several, drag into any app")
        .task(id: "\(url.path)#\(revision)") {
            let preview = CaptureHistory.previewURL(for: url)
            thumbnail = await Task.detached(priority: .utility) {
                CaptureHistory.thumbnail(of: FileManager.default.fileExists(atPath: preview.path) ? preview : url, maxPixels: 200)
            }.value
        }
    }

    private var age: String {
        guard let date = CaptureHistory.date(of: url) else { return "" }
        let seconds = Date.now.timeIntervalSince(date)
        if seconds < 60 { return "Now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// A plain button that knows whether the pointer is over it; every chrome button draws its own hover look.
struct HoverButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: (_ hovering: Bool) -> Label
    @State private var hovering = false

    var body: some View {
        Button(action: action) { label(hovering) }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Toolbar icon button. A nil tooltip hides it (e.g. while the button's popover is open).
/// `badge` shows the button's key while ⌘ is held.
struct ToolButton: View {
    let icon: IconKind
    let tooltip: String?
    var shortcut: String? = nil
    var selected = false
    var badge: String? = nil
    let action: () -> Void

    var body: some View {
        HoverButton(action: action) { hovering in
            Icon(kind: icon)
                .foregroundStyle(selected || hovering ? Color.white : Theme.chromeText)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(selected ? 0.16 : hovering ? 0.08 : 0)))
                .overlay(alignment: .bottomTrailing) {
                    if let badge {
                        Text(badge)
                            .font(.system(size: 9, weight: .bold).monospaced())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3)
                            .frame(minWidth: 14, minHeight: 14)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Theme.accent))
                            .fixedSize()
                            .offset(x: 5, y: 5)
                    }
                }
                .tooltip(tooltip, shortcut: shortcut, visible: hovering)
        }
    }
}

/// One square showing the current color; click for the palette. Picking a color also recolors the selection.
private struct ColorButton: View {
    @Bindable var model: EditorModel
    @State private var open = false

    var body: some View {
        HoverButton { open.toggle() } label: { hovering in
            RoundedRectangle(cornerRadius: 4)
                .fill(model.color)
                .frame(width: 16, height: 16)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.35), lineWidth: 1))
                .frame(width: 30, height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(hovering || open ? 0.08 : 0)))
                .tooltip("Color", shortcut: nil, visible: hovering && !open)
        }
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(spacing: 12) {
                PaletteGrid(model: model) { open = false }
                Divider()
                RGBPicker(model: model)
            }
            .padding(12)
            .frame(width: 176)
        }
    }
}

/// The ten preset colors, five to a row.
private struct PaletteGrid: View {
    @Bindable var model: EditorModel
    var onPick: () -> Void = {}

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 8), count: 5), spacing: 8) {
            ForEach(Theme.palette, id: \.self) { color in
                Swatch(color: color, selected: model.color.hex == color.hex) {
                    model.setColor(color)
                    onPick()
                }
            }
        }
        .fixedSize() // left-aligned in the inspector instead of centered
    }
}

private struct Swatch: View {
    let color: Color
    let selected: Bool
    var size: CGFloat = 24
    let action: () -> Void

    var body: some View {
        HoverButton(action: action) { hovering in
            RoundedRectangle(cornerRadius: size / 5)
                .fill(color)
                .frame(width: size, height: size)
                .overlay(RoundedRectangle(cornerRadius: size / 5).strokeBorder(.white.opacity(selected ? 0.95 : hovering ? 0.5 : 0.15), lineWidth: selected ? 2 : 1))
                .scaleEffect(hovering ? 1.1 : 1)
        }
    }
}

/// R, G, B sliders + hex field + screen eyedropper. A whole slider drag is one undo step.
private struct RGBPicker: View {
    @Bindable var model: EditorModel
    @State private var rgb: [Double] = [0, 0, 0]
    @State private var hex = ""

    var body: some View {
        VStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { channel in
                ChannelSlider(label: ["R", "G", "B"][channel], value: $rgb[channel], colors: gradient(for: channel)) { model.liveChange($0) }
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
        .onChange(of: model.color.hex, initial: true) {
            rgb = model.color.rgb
            hex = model.color.hex
        }
        .onChange(of: rgb) {
            guard Color(rgb: rgb).hex != model.color.hex else { return }
            model.setColor(Color(rgb: rgb), undoable: !model.isLiveChanging)
        }
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

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 10)
            TrackSlider(value: Binding(get: { CGFloat(value) }, set: { value = Double($0) }), range: 0...255, thumb: CGSize(width: 14, height: 14),
                        track: Capsule()
                            .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                            .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 1))
                            .frame(height: 8),
                        onEditingChanged: onEditingChanged)
                .frame(height: 16)
            Text("\(Int(value))")
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
        }
    }
}

// MARK: - Tool options

/// Options for the active drawing tool or the selection: thickness (font size for text), plus the tool's style,
/// shape or buttons. A floating panel (Classic, Canvas first), a strip (Two rows), or a column (Sidebars).
private struct ToolOptions: View {
    @Bindable var model: EditorModel
    var vertical = false

    var body: some View {
        let stack = vertical ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 12))
        stack {
            if model.showsWidthSlider {
                TrackSlider(value: Binding(get: { model.currentWidth }, set: { model.setWidth($0, undoable: false) }),
                            range: model.currentWidthRange, track: Wedge().fill(.white.opacity(0.22)).frame(height: 10)) {
                    model.liveChange($0) // one undo step per drag
                }
                .frame(width: 96, height: 22)
                .help(sliderHelp)
            }

            switch model.optionsTool {
            case .blur:
                Segments(items: RedactStyle.allCases, selected: model.redactStyle) { style in
                    Text(style.title).font(.system(size: 11, weight: .medium)).padding(.horizontal, 7)
                } action: { model.setRedactStyle($0) }
            case .spotlight, .magnifier:
                Segments(items: AreaShape.allCases, selected: model.optionsTool == .spotlight ? model.spotlightShape : model.magnifierShape) { shape in
                    Icon(kind: shape.icon, size: 16).frame(width: 26)
                } action: { model.setAreaShape($0) }
            case .arrow:
                Segments(items: ArrowStyle.allCases, selected: model.arrowStyle) { ArrowGlyph(style: $0).help($0.title) } action: { model.setArrowStyle($0) }
            case .text:
                Segments(items: TextStyle.allCases, selected: model.textStyle) { TextGlyph(style: $0).help($0.title) } action: { model.setTextStyle($0) }
            case .crop:
                // A hint until there's a box, then Crop (or Return); Reset once a crop is applied.
                HStack(spacing: 8) {
                    if model.cropBox == nil { hint(model.crop == nil ? "Drag to choose the area" : "Drag a new area, or reset") }
                    if model.crop != nil { PanelButton(title: "Reset") { model.resetCrop() } }
                    if model.cropBox != nil { PanelButton(title: "Crop", prominent: true) { model.applyCrop() } }
                }
            case .textCard:
                hint("Drag over text to turn it into a card")
            case .ruler:
                hint("Point at something to measure it · hold 1 or 2 for one direction")
            case .recognizeText:
                // Status while Live Text looks, then Copy (for a selection) and Copy All.
                HStack(spacing: 8) {
                    switch model.recognizedText {
                    case nil:
                        hint("Finding text…")
                    case let text? where text.isEmpty:
                        hint("No text found")
                    default:
                        if model.hasTextSelection {
                            PanelButton(title: "Copy", prominent: true) { model.copySelectedText?() }
                        } else {
                            hint("Drag over text to select it")
                        }
                        PanelButton(title: "Copy All") { model.copyAllText() }
                    }
                }
            default:
                EmptyView()
            }
        }
    }

    /// As a floating panel (like Shottr's).
    func floating() -> some View {
        padding(.horizontal, 12).padding(.vertical, 8).floatingPanel()
    }

    private var sliderHelp: String {
        switch model.optionsTool {
        case .text: "Text size"
        case .blur: "Blur strength"
        case .spotlight: "Dim"
        case .step: "Size"
        default: "Thickness"
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(Theme.chromeText)
    }
}

struct PanelButton: View {
    let title: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        HoverButton(action: action) { hovering in
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(prominent ? Theme.accent.opacity(hovering ? 0.85 : 1) : .white.opacity(hovering ? 0.16 : 0.1)))
        }
    }
}

/// A row of mutually exclusive choices (Blur / Blur Text / …, rectangle / ellipse, arrow and text styles).
private struct Segments<Item: Hashable, Label: View>: View {
    let items: [Item]
    let selected: Item
    @ViewBuilder let label: (Item) -> Label
    let action: (Item) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.self) { item in
                HoverButton { action(item) } label: { hovering in
                    label(item)
                        .frame(height: 22)
                        .foregroundStyle(item == selected || hovering ? Color.white : Theme.chromeText)
                        .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(item == selected ? 0.18 : hovering ? 0.08 : 0)))
                }
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(.black.opacity(0.25)))
    }
}

/// Short confirmation: at the bottom of the canvas, or floating (FloatingToast) when there's no editor.
struct Toast: View {
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

/// Drag-anywhere slider over a custom track: a wedge for sizes, a gradient for color channels.
/// Reports when a drag starts and ends; the caller sets the height.
private struct TrackSlider<Track: View>: View {
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    var step: CGFloat = 1
    var thumb = CGSize(width: 6, height: 18)
    let track: Track
    let onEditingChanged: (Bool) -> Void
    @State private var dragging = false

    var body: some View {
        GeometryReader { geo in
            let span = range.upperBound - range.lowerBound
            ZStack(alignment: .leading) {
                track
                Capsule()
                    .fill(.white)
                    .frame(width: thumb.width, height: thumb.height)
                    .shadow(color: .black.opacity(0.4), radius: 1.5, y: 0.5)
                    .offset(x: (value - range.lowerBound) / span * (geo.size.width - thumb.width))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                if !dragging {
                    dragging = true
                    onEditingChanged(true)
                }
                let fraction = ((drag.location.x - thumb.width / 2) / (geo.size.width - thumb.width)).clamped(to: 0...1)
                value = ((range.lowerBound + fraction * span) / step).rounded() * step
            }.onEnded { _ in
                dragging = false
                onEditingChanged(false)
            })
        }
    }
}

private struct Wedge: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addLines([CGPoint(x: rect.minX, y: rect.midY - 1), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.midY + 1)])
        path.closeSubpath()
        return path
    }
}

/// Arrow style preview, drawn by the same code that draws real arrows.
private struct ArrowGlyph: View {
    let style: ArrowStyle

    var body: some View {
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
        .frame(width: 30)
    }
}

/// Text style preview: a bubble with a pointer, a filled label, or bare letters.
private struct TextGlyph: View {
    let style: TextStyle

    var body: some View {
        Canvas { context, size in
            let box = CGRect(x: 4, y: style == .callout ? 3 : 5, width: size.width - 8, height: size.height - 10)
            if style != .plain {
                context.fill(Path(roundedRect: box, cornerRadius: 3), with: .foreground)
            }
            if style == .callout {
                var pointer = Path()
                pointer.addLines([CGPoint(x: box.minX + 5, y: box.maxY - 1), CGPoint(x: box.minX + 3, y: box.maxY + 5), CGPoint(x: box.minX + 10, y: box.maxY - 1)])
                context.fill(pointer, with: .foreground)
            }
            let letters = Text("Aa").font(.system(size: 10, weight: .bold)) // unstyled text draws in the foreground style
            context.draw(style == .plain ? letters : letters.foregroundStyle(Theme.chrome), at: CGPoint(x: box.midX, y: box.midY))
        }
        .frame(width: 30)
    }
}

// MARK: - Insert picture

/// Paste, pick from Finder, or capture a new area into the current picture. (Dropping files on the canvas works too.)
private struct InsertImageButton: View {
    @Bindable var model: EditorModel
    @State private var open = false

    var body: some View {
        ToolButton(icon: .insertImage, tooltip: open ? nil : "Insert picture", selected: open) { open.toggle() }
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

    var body: some View {
        HoverButton(action: action) { hovering in
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
    }
}

// MARK: - Backdrop

/// The screenshot on a gradient card. Off by default; pick a gradient to turn it on.
private struct BackdropButton: View {
    @Bindable var model: EditorModel
    @State private var open = false

    var body: some View {
        ToolButton(icon: .backdrop, tooltip: open ? nil : "Backdrop", selected: model.backdrop != nil || open) { open.toggle() }
            .popover(isPresented: $open, arrowEdge: .bottom) {
                BackdropOptions(model: model)
                    .padding(12)
                    .frame(width: 236)
            }
    }
}

/// Pick a gradient (or None), then its padding, corners and shadow.
private struct BackdropOptions: View {
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
            TrackSlider(value: Binding(get: { model.backdrop?[keyPath: key] ?? range.lowerBound },
                                       set: { model.backdrop?[keyPath: key] = $0 }),
                        range: range, step: (range.upperBound - range.lowerBound) / 100, track: Wedge().fill(.white.opacity(0.22)).frame(height: 10)) { _ in }
                .frame(height: 22)
                .help(title)
        }
    }
}

private struct BackdropSwatch: View {
    let colors: [Color]?
    let name: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        HoverButton(action: action) { hovering in
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
        .help(name)
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
            Text(label).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
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
    /// Shows a small dark label under the view shortly after `visible` turns true (and there's text).
    func tooltip(_ text: String?, shortcut: String?, visible: Bool) -> some View {
        modifier(TooltipModifier(text: text, shortcut: shortcut, visible: visible))
    }
}

extension EnvironmentValues {
    /// Which side of a button its tooltip appears on: below in toolbars, beside the sidebar rail, above the dock.
    @Entry var tooltipEdge: Edge = .bottom
}

private struct TooltipModifier: ViewModifier {
    let text: String?
    let shortcut: String?
    let visible: Bool
    @Environment(\.tooltipEdge) private var edge
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .task(id: visible && text != nil) {
                shown = false
                guard visible, text != nil else { return }
                try? await Task.sleep(for: .milliseconds(350))
                if !Task.isCancelled { shown = true }
            }
            .overlay(alignment: edge == .top ? .bottom : edge == .trailing ? .leading : .top) {
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
                    .offset(x: edge == .trailing ? 36 : 0, y: edge == .top ? -36 : edge == .trailing ? 0 : 36)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.12), value: shown)
    }
}
