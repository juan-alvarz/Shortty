import Foundation

/// Everything the user can trigger from the menu bar or a global shortcut. No shortcuts are set out of the box.
enum CaptureAction: String, CaseIterable {
    case region, screen, lazyRegion, lazyScreen, reopen, scrolling, // new cases go last: hotkey ids follow this order
         repeatRegion, window, activeWindow, captureText

    var isLazy: Bool { self == .lazyRegion || self == .lazyScreen }

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

    /// What it does, under its name in Settings → Shortcuts.
    var summary: String {
        switch self {
        case .region: "Drag over an area. Space switches to clicking a window, Esc cancels."
        case .repeatRegion: "The same area as last time, without selecting."
        case .screen: "The display under the pointer."
        case .window: "Click a window to capture it, without its shadow."
        case .activeWindow: "The front window of the app you're in, instantly."
        case .scrolling: "Drag over an area, then scroll: the frames become one tall image."
        case .captureText: "Drag over an area: its text or QR code goes to the clipboard."
        case .reopen: "Brings back the editor with the latest capture and its edits."
        case .lazyRegion: "Pick the area first, then a countdown runs and that area is captured."
        case .lazyScreen: "A countdown, then the display under the pointer."
        }
    }

    /// Carbon hotkey id (must be non-zero and unique).
    var hotkeyID: UInt32 { UInt32(CaptureAction.allCases.firstIndex(of: self)! + 1) }
    var hotkeyKey: String { "hotkey.\(rawValue)" }
}
