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

    private init() {
        let stored = UserDefaults.standard
        captureSound = stored.object(forKey: "captureSound") as? Bool ?? true
        lazyDelay = (stored.object(forKey: "lazyDelay") as? Int ?? 3).clamped(to: Self.lazyDelayRange)
        hotkeys = Dictionary(uniqueKeysWithValues: CaptureAction.allCases.map { action in
            (action, stored.string(forKey: action.hotkeyKey).flatMap(Hotkey.init(rawValue:)) ?? action.defaultHotkey)
        })
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
