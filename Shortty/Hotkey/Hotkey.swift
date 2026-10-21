import AppKit
import Carbon.HIToolbox

/// A global keyboard shortcut. Stored in UserDefaults as "keyCode|modifiers|label".
struct Hotkey: Equatable {
    var keyCode: UInt32
    var modifiers: NSEvent.ModifierFlags.RawValue
    var keyLabel: String

    static let defaultRegion = Hotkey(
        keyCode: UInt32(kVK_ANSI_9),
        modifiers: NSEvent.ModifierFlags([.command, .shift]).rawValue,
        keyLabel: "9"
    )
    /// "No shortcut assigned".
    static let none = Hotkey(keyCode: .max, modifiers: 0, keyLabel: "")
    var isNone: Bool { keyCode == .max }

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var carbonModifiers: UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        return mods
    }

    /// e.g. "⌘⇧9"
    var display: String {
        if isNone { return "None" }
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text + (Self.keyName(for: keyCode) ?? keyLabel)
    }

    /// Builds a hotkey from a key-down event. Requires ⌘, ⌥ or ⌃ so plain typing can't become a global shortcut.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard !flags.intersection([.command, .option, .control]).isEmpty else { return nil }
        guard let label = Hotkey.label(for: event) else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: flags.rawValue, keyLabel: label)
    }

    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags.RawValue, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    private static let specialKeyLabels: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    private static func label(for event: NSEvent) -> String? {
        if let name = keyName(for: UInt32(event.keyCode)) { return name }
        guard let first = event.charactersIgnoringModifiers?.uppercased().first,
              first.isLetter || first.isNumber || first.isPunctuation || first.isSymbol
        else { return nil }
        return String(first)
    }

    /// What's printed on the key in the current keyboard layout, without Shift ("0", not ")"),
    /// or a symbol for special keys. Computed from the key code, so it also fixes labels saved before.
    static func keyName(for keyCode: UInt32) -> String? {
        if let special = specialKeyLabels[Int(keyCode)] { return special }
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layout = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layout.withUnsafeBytes { bytes in
            UCKeyTranslate(bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress, UInt16(keyCode), UInt16(kUCKeyActionDisplay),
                           0, UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState, 4, &length, &characters)
        }
        guard status == noErr, length > 0 else { return nil }
        let name = String(utf16CodeUnits: characters, count: length).uppercased()
        return name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : name
    }
}

extension Hotkey: RawRepresentable {
    init?(rawValue: String) {
        let parts = rawValue.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, let code = UInt32(parts[0]), let mods = UInt(parts[1]) else { return nil }
        self.init(keyCode: code, modifiers: mods, keyLabel: String(parts[2]))
    }

    var rawValue: String { "\(keyCode)|\(modifiers)|\(keyLabel)" }
}
