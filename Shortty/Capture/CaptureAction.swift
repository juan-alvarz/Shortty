import AppKit
import Carbon.HIToolbox

/// Everything the user can trigger from the menu bar or a global shortcut.
enum CaptureAction: String, CaseIterable, Identifiable {
    case region, screen, lazyRegion, lazyScreen, reopen, scrolling, // new cases go last: hotkey ids follow this order
         repeatRegion, window, activeWindow, captureText

    var id: String { rawValue }
    var isLazy: Bool { self == .lazyRegion || self == .lazyScreen }
    var isScreen: Bool { self == .screen || self == .lazyScreen }

    var title: String {
        switch self {
        case .region: "Capture Region"
        case .screen: "Capture Screen"
        case .lazyRegion: "Lazy Region"
        case .lazyScreen: "Lazy Screen"
        case .reopen: "Reopen Last Capture"
        case .scrolling: "Scrolling Capture"
        case .repeatRegion: "Repeat Last Region"
        case .window: "Capture Window"
        case .activeWindow: "Capture Active Window"
        case .captureText: "Capture Text"
        }
    }

    /// Carbon hotkey id (must be non-zero and unique).
    var hotkeyID: UInt32 { UInt32(CaptureAction.allCases.firstIndex(of: self)! + 1) }
    var hotkeyKey: String { "hotkey.\(rawValue)" }
    var defaultHotkey: Hotkey {
        switch self {
        case .region: .defaultRegion
        case .lazyRegion: Hotkey(keyCode: UInt32(kVK_ANSI_8), modifiers: NSEvent.ModifierFlags([.command, .shift]).rawValue, keyLabel: "8")
        case .screen, .lazyScreen, .reopen, .scrolling, .repeatRegion, .window, .activeWindow, .captureText: .none
        }
    }
}
