import ServiceManagement
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
            Section {
                LaunchAtLoginToggle()
                Toggle("Play sound when capturing", isOn: $settings.captureSound)
            }
            Section("Saving") {
                SaveFolderRow(folder: $settings.saveFolder)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Start at login through macOS login items. The system is the source of truth, so this reads its status
/// instead of keeping a preference that could drift.
private struct LaunchAtLoginToggle: View {
    @State private var status = SMAppService.mainApp.status

    var body: some View {
        // Closure literal, not `set: setEnabled`: passing the method directly crashes the Swift 6.2 compiler (IRGen thunk).
        Toggle("Start Shortty at login", isOn: Binding(get: { status == .enabled }, set: { setEnabled($0) }))
            .onAppear { status = SMAppService.mainApp.status }
        if status == .requiresApproval {
            HStack {
                Text("macOS needs your OK in Login Items.").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
            }
        }
    }

    private func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSAlert(error: error).runModal()
        }
        status = SMAppService.mainApp.status
    }
}

/// Where Save writes: shows the folder, lets you pick another, or go back to Downloads.
private struct SaveFolderRow: View {
    @Binding var folder: URL

    var body: some View {
        LabeledContent("Save to") {
            HStack(spacing: 8) {
                Text((folder.path as NSString).abbreviatingWithTildeInPath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .help(folder.path)
                Button("Choose…") { choose() }
            }
        }
        if folder.standardizedFileURL != AppSettings.downloadsFolder.standardizedFileURL {
            HStack {
                Spacer()
                Button("Use Downloads") { folder = AppSettings.downloadsFolder }
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = folder
        panel.prompt = "Use Folder"
        panel.message = "Where should Shortty save screenshots?"
        panel.begin { response in
            if response == .OK, let url = panel.url { folder = url }
        }
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
