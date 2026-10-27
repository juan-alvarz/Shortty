import Observation
import SwiftUI

/// Persisted preferences. Views bind to `AppSettings.shared`; writes land in UserDefaults immediately.
@Observable
final class AppSettings {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    static let lazyDelayRange = 1...30

    /// Seconds to wait before a lazy shot.
    var lazyDelay: Int {
        didSet { defaults.set(lazyDelay, forKey: "lazyDelay") }
    }

    static let downloadsFolder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]

    /// Where Save (⌘S) writes. Defaults to Downloads.
    var saveFolder: URL {
        didSet { defaults.set(saveFolder.path, forKey: "saveFolder") }
    }

    /// Shutter sound when a screenshot is taken.
    var captureSound: Bool {
        didSet { defaults.set(captureSound, forKey: "captureSound") }
    }

    var hotkeys: [CaptureAction: Hotkey] {
        didSet {
            for (action, hotkey) in hotkeys { defaults.set(hotkey.rawValue, forKey: action.hotkeyKey) }
            HotkeyManager.shared.register(hotkeys)
        }
    }

    /// How the editor arranges its tools around the picture.
    var editorLayout: EditorLayout {
        didSet { defaults.set(editorLayout.rawValue, forKey: "editorLayout") }
    }

    /// What appears right after a capture: the editor, a small card in the screen corner, or only a notice.
    var afterCapture: AfterCapture {
        didSet { defaults.set(afterCapture.rawValue, forKey: "afterCapture") }
    }

    /// Right after a capture, also put it on the clipboard.
    var copyAfterCapture: Bool {
        didSet { defaults.set(copyAfterCapture, forKey: "copyAfterCapture") }
    }

    /// Right after a capture, also save it to `saveFolder`.
    var saveAfterCapture: Bool {
        didSet { defaults.set(saveAfterCapture, forKey: "saveAfterCapture") }
    }

    /// The strip of recent captures along the bottom of the editor.
    var showsHistory: Bool {
        didSet { defaults.set(showsHistory, forKey: "showsHistory") }
    }

    /// The outline and badge while picking an area or counting down, as "#RRGGBB". Nil follows the Mac's accent color.
    var selectionColorHex: String? {
        didSet { defaults.set(selectionColorHex, forKey: "selectionColor") }
    }

    /// What the selection overlays draw with: the picked color, else the accent from System Settings → Appearance.
    var selectionColor: NSColor {
        selectionColorHex.flatMap { Color(hex: $0) }.map { NSColor($0) } ?? .controlAccentColor
    }

    /// Text Card's font size (points) and whether the card has a window title bar; its colors come from the screenshot.
    var textCardFontSize: Double {
        didSet { defaults.set(textCardFontSize, forKey: "textCardFontSize") }
    }

    var textCardWindowBar: Bool {
        didSet { defaults.set(textCardWindowBar, forKey: "textCardWindowBar") }
    }

    private init() {
        let stored = UserDefaults.standard
        editorLayout = stored.string(forKey: "editorLayout").flatMap(EditorLayout.init(rawValue:)) ?? .classic
        afterCapture = stored.string(forKey: "afterCapture").flatMap(AfterCapture.init(rawValue:)) ?? .editor
        copyAfterCapture = stored.object(forKey: "copyAfterCapture") as? Bool ?? true
        saveAfterCapture = stored.object(forKey: "saveAfterCapture") as? Bool ?? false
        showsHistory = stored.object(forKey: "showsHistory") as? Bool ?? true
        selectionColorHex = stored.string(forKey: "selectionColor")
        textCardFontSize = (stored.object(forKey: "textCardFontSize") as? Double ?? 14).clamped(to: TextCard.fontSizes)
        textCardWindowBar = stored.object(forKey: "textCardWindowBar") as? Bool ?? true
        captureSound = stored.object(forKey: "captureSound") as? Bool ?? true
        saveFolder = stored.string(forKey: "saveFolder").map { URL(fileURLWithPath: $0, isDirectory: true) } ?? Self.downloadsFolder
        lazyDelay = (stored.object(forKey: "lazyDelay") as? Int ?? 3).clamped(to: Self.lazyDelayRange)
        hotkeys = Dictionary(uniqueKeysWithValues: CaptureAction.allCases.map { action in
            (action, stored.string(forKey: action.hotkeyKey).flatMap(Hotkey.init(rawValue:)) ?? .none)
        })
    }
}

enum EditorLayout: String, CaseIterable {
    case classic, twoRows, sidebars, canvasFirst

    var title: String {
        switch self {
        case .classic: "Classic: one toolbar"
        case .twoRows: "Two rows: options under the toolbar"
        case .sidebars: "Sidebars: tools left, settings right"
        case .canvasFirst: "Canvas first: floating dock"
        }
    }
}

enum AfterCapture: String, CaseIterable {
    case editor, card, nothing

    var title: String {
        switch self {
        case .editor: "Show editor"
        case .card: "Show card"
        case .nothing: "Nothing"
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
