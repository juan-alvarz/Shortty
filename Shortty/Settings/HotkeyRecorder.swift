import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Click, press a combo (needs ⌘, ⌥ or ⌃). Esc cancels, ⌫ clears.
struct HotkeyRecorder: View {
    @Binding var hotkey: Hotkey
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording.toggle()
        } label: {
            Text(recording ? "Press shortcut…" : hotkey.isNone ? "Record Shortcut" : hotkey.display)
                .frame(minWidth: 110)
                .foregroundStyle(recording || hotkey.isNone ? .secondary : .primary)
        }
        .help("Click, then press a key combination. ⌫ clears, Esc cancels.")
        .onChange(of: recording) { _, isRecording in isRecording ? startRecording() : stopRecording() }
        .onDisappear { recording = false }
    }

    private func startRecording() {
        HotkeyManager.shared.unregisterAll() // so existing combos don't fire while re-binding
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch Int(event.keyCode) {
            case kVK_Escape:
                recording = false
            case kVK_Delete, kVK_ForwardDelete:
                hotkey = .none
                recording = false
            default:
                if let newHotkey = Hotkey(event: event) {
                    hotkey = newHotkey
                    recording = false
                }
            }
            return nil // swallow keystrokes while recording
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        HotkeyManager.shared.register(AppSettings.shared.hotkeys)
    }
}
