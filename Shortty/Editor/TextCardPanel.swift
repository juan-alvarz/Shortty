import AppKit
import Observation
import SwiftUI

/// Where a text card is tuned before it becomes a capture, as a sheet on the editor: the card as it will look,
/// editable in place, with its background, text color (or the selected text's color), font size and title bar.
enum TextCardPanel {
    /// The finished card, or nil when cancelled.
    static func edit(_ styled: StyledText, over window: NSWindow) async -> CGImage? {
        let model = TextCardModel(styled)
        let sheet = NSPanel(contentRect: .zero, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        sheet.appearance = NSAppearance(named: .darkAqua)
        sheet.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: TextCardView(model: model))
        sheet.contentView = host
        sheet.setContentSize(host.fittingSize)
        return await withCheckedContinuation { continuation in
            model.onFinish = { image in
                window.endSheet(sheet)
                continuation.resume(returning: image)
            }
            window.beginSheet(sheet)
            sheet.makeFirstResponder(model.textView)
        }
    }
}

/// Internal for the self-check, which drives it without a sheet.
@Observable
final class TextCardModel {
    var background: NSColor
    var textColor: NSColor { didSet { textView.map { TextCard.setTextColor(textColor, in: $0.textStorage!) }; refreshTyping() } }
    var fontSize: Double {
        didSet {
            AppSettings.shared.textCardFontSize = fontSize
            textView.map { TextCard.setFontSize(fontSize, in: $0.textStorage!) }
            refreshTyping()
            measure()
        }
    }
    var windowBar: Bool { didSet { AppSettings.shared.textCardWindowBar = windowBar } }
    var title = ""
    /// Some text is selected: the color picker recolors it instead of the card's text color.
    private(set) var hasSelection = false
    /// The text's size in points, for the preview's frame.
    private(set) var textSize: CGSize = .zero
    @ObservationIgnored var onFinish: ((CGImage?) -> Void)?

    @ObservationIgnored private(set) var textView: NSTextView?
    @ObservationIgnored private let initialText: NSAttributedString

    init(_ styled: StyledText) {
        let settings = AppSettings.shared
        let prepared = TextCard.prepare(styled, fontSize: settings.textCardFontSize)
        initialText = prepared.text
        background = prepared.background
        textColor = prepared.textColor
        fontSize = settings.textCardFontSize
        windowBar = settings.textCardWindowBar
        textSize = TextCard.textSize(prepared.text)
    }

    var text: NSAttributedString { textView?.attributedString() ?? initialText }

    var style: TextCard.Style { TextCard.Style(background: background, windowBar: windowBar, title: title) }

    func attach(_ textView: NSTextView) {
        self.textView = textView
        textView.textStorage?.setAttributedString(initialText)
        refreshTyping()
    }

    /// The picker's color: the selection's (its first letter's) while there is one, else the card's text color.
    var pickedColor: NSColor {
        guard hasSelection, let textView, let storage = textView.textStorage else { return textColor }
        return storage.attribute(.foregroundColor, at: textView.selectedRange().location, effectiveRange: nil) as? NSColor ?? textColor
    }

    func pick(_ color: NSColor) {
        guard hasSelection, let textView, let storage = textView.textStorage else { return textColor = color }
        TextCard.setColor(color, range: textView.selectedRange(), in: storage)
        textView.didChangeText()
    }

    func selectionChanged() { hasSelection = (textView?.selectedRange().length ?? 0) > 0 }

    func measure() { textSize = TextCard.textSize(text) }

    func finish(_ keep: Bool) {
        let image = keep ? TextCard.render(text, style: style) : nil
        let finish = onFinish
        onFinish = nil
        finish?(image)
    }

    private func refreshTyping() {
        textView?.typingAttributes = TextCard.typingAttributes(fontSize: fontSize, textColor: textColor)
    }
}

struct TextCardView: View {
    @Bindable var model: TextCardModel
    private static let maxPreview = CGSize(width: 960, height: 560)

    var body: some View {
        VStack(spacing: 0) {
            preview
                .padding(28)
            Divider().overlay(Color.white.opacity(0.06))
            controls
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .fixedSize()
        .background(Theme.chrome)
        .environment(\.colorScheme, .dark)
    }

    /// The card at 1:1, as the picture will be.
    private var preview: some View {
        let minimum = TextCard.size(of: NSAttributedString(), style: model.style) // the empty card: padding, bar, minimum width
        let width = min(max(model.textSize.width + TextCard.padding.width * 2, minimum.width), Self.maxPreview.width)
        let height = min(model.textSize.height + 2, Self.maxPreview.height)
        return VStack(spacing: 0) {
            if model.windowBar {
                ZStack {
                    HStack(spacing: 8) {
                        ForEach(0..<3, id: \.self) { Circle().fill(Color(nsColor: TextCard.windowButtonColors[$0])).frame(width: 12, height: 12) }
                        Spacer()
                    }
                    .padding(.leading, 18)
                    TextField("Title", text: $model.title)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(nsColor: model.background.luminance > 0.5 ? .black : .white).opacity(0.55))
                        .frame(maxWidth: max(width - 180, 60))
                }
                .frame(height: TextCard.barHeight)
            }
            CardTextView(model: model)
                .frame(width: width - TextCard.padding.width * 2, height: height)
                .padding(.top, model.windowBar ? TextCard.padding.height - 8 : TextCard.padding.height)
                .padding(.bottom, TextCard.padding.height)
        }
        .frame(width: width)
        .background(RoundedRectangle(cornerRadius: TextCard.cornerRadius).fill(Color(nsColor: model.background)))
        .overlay(RoundedRectangle(cornerRadius: TextCard.cornerRadius).strokeBorder(.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }

    private var controls: some View {
        HStack(spacing: 14) {
            ColorPicker("Background", selection: Binding(get: { Color(nsColor: model.background) }, set: { model.background = NSColor($0) }),
                        supportsOpacity: false)
            ColorPicker(model.hasSelection ? "Selection" : "Text", selection: Binding(get: { Color(nsColor: model.pickedColor) }, set: { model.pick(NSColor($0)) }),
                        supportsOpacity: false)
                .help(model.hasSelection ? "Recolor the selected text" : "The color of text that has none of its own. Select text to recolor just that.")
            HStack(spacing: 4) {
                Text("Size")
                Stepper(value: $model.fontSize, in: TextCard.fontSizes, step: 1) {
                    Text("\(Int(model.fontSize))").monospacedDigit().frame(minWidth: 18)
                }
            }
            Toggle("Title bar", isOn: $model.windowBar).toggleStyle(.checkbox)
            Spacer(minLength: 12)
            PanelButton(title: "Cancel") { model.finish(false) }
                .keyboardShortcut(.cancelAction)
            PanelButton(title: "Create Card", prominent: true) { model.finish(true) }
                .keyboardShortcut(.return, modifiers: .command)
                .help("Opens the card in the editor as a new capture (⌘Return)")
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.chromeText)
        .lineLimit(1)
        .fixedSize()
        .frame(minWidth: 640)
    }
}

/// The card's text, editable: fix what recognition got wrong, or select some and give it another color.
private struct CardTextView: NSViewRepresentable {
    let model: TextCardModel

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        let textView = CardNSTextView()
        textView.onCancel = { model.finish(false) }
        textView.isRichText = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.usesFontPanel = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true // lines never wrap, as on the card
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.delegate = context.coordinator
        scroll.documentView = textView
        model.attach(textView)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        (scroll.documentView as? NSTextView)?.insertionPointColor = model.background.luminance > 0.5 ? .black : .white
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let model: TextCardModel
        init(model: TextCardModel) { self.model = model }
        func textDidChange(_ notification: Notification) { model.measure() }
        func textViewDidChangeSelection(_ notification: Notification) { model.selectionChanged() }
    }
}

/// Esc cancels the card instead of offering completions.
private final class CardNSTextView: NSTextView {
    var onCancel: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}
