import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            ShortcutsSettingsView()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .frame(width: 460)
    }
}

struct GeneralSettingsView: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Form {
            Toggle("Play sound when capturing", isOn: $settings.captureSound)
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct ShortcutsSettingsView: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("Capture") {
                shortcutRow("Region", .region)
                shortcutRow("Screen", .screen)
                shortcutRow("Reopen last capture", .reopen)
            }
            Section {
                shortcutRow("Region", .lazyRegion)
                shortcutRow("Screen", .lazyScreen)
                LabeledContent("Delay") { DelayField(seconds: $settings.lazyDelay) }
            } header: {
                Text("Lazy shots")
            } footer: {
                Text("Region: select the area first, then Shortty counts down and captures it.\nScreen: counts down, then captures the screen under the pointer.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func shortcutRow(_ title: String, _ action: CaptureAction) -> some View {
        LabeledContent(title) {
            HotkeyRecorder(hotkey: Binding(
                get: { settings.hotkeys[action] ?? action.defaultHotkey },
                set: { settings.hotkeys[action] = $0 }))
        }
    }
}

/// Digits only, 1–30. Valid values save as you type; anything else snaps back when you leave the field.
private struct DelayField: View {
    @Binding var seconds: Int
    @State private var text = ""
    @FocusState private var focused: Bool
    private let range = AppSettings.lazyDelayRange

    var body: some View {
        HStack(spacing: 6) {
            TextField("", text: $text)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 44)
                .focused($focused)
                .onSubmit(normalize)
                .onChange(of: text) { _, newValue in
                    let digits = String(newValue.filter(\.isNumber).prefix(2))
                    if digits != newValue { text = digits; return }
                    guard let value = Int(digits) else { return }
                    if value > range.upperBound { text = "\(range.upperBound)"; return }
                    if range.contains(value) { seconds = value }
                }
                .onChange(of: focused) { _, isFocused in if !isFocused { normalize() } }
            Text("seconds").foregroundStyle(.secondary)
        }
        .help("Between \(range.lowerBound) and \(range.upperBound) seconds")
        .onAppear { text = "\(seconds)" }
    }

    private func normalize() { text = "\(seconds)" }
}
