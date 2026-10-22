import Foundation
import Observation

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

    /// What appears right after a capture: the editor, or a small card in the screen corner.
    var afterCapture: AfterCapture {
        didSet { defaults.set(afterCapture.rawValue, forKey: "afterCapture") }
    }

    /// The strip of recent captures along the bottom of the editor.
    var showsHistory: Bool {
        didSet { defaults.set(showsHistory, forKey: "showsHistory") }
    }

    private init() {
        let stored = UserDefaults.standard
        editorLayout = stored.string(forKey: "editorLayout").flatMap(EditorLayout.init(rawValue:)) ?? .classic
        afterCapture = stored.string(forKey: "afterCapture").flatMap(AfterCapture.init(rawValue:)) ?? .editor
        showsHistory = stored.object(forKey: "showsHistory") as? Bool ?? true
        captureSound = stored.object(forKey: "captureSound") as? Bool ?? true
        saveFolder = stored.string(forKey: "saveFolder").map { URL(fileURLWithPath: $0, isDirectory: true) } ?? Self.downloadsFolder
        lazyDelay = (stored.object(forKey: "lazyDelay") as? Int ?? 3).clamped(to: Self.lazyDelayRange)
        hotkeys = Dictionary(uniqueKeysWithValues: CaptureAction.allCases.map { action in
            (action, stored.string(forKey: action.hotkeyKey).flatMap(Hotkey.init(rawValue:)) ?? action.defaultHotkey)
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
    case editor, card

    var title: String {
        switch self {
        case .editor: "Open the editor"
        case .card: "Show a quick card"
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
