import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

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
            Section("Editor") {
                Picker("Layout", selection: $settings.editorLayout) {
                    ForEach(EditorLayout.allCases, id: \.self) { Text($0.title) }
                }
                Picker("After a capture", selection: $settings.afterCapture) {
                    ForEach(AfterCapture.allCases, id: \.self) { Text($0.title) }
                }
                RecentCapturesRow(isOn: $settings.showsHistory)
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
    @State private var choosing = false

    var body: some View {
        LabeledContent("Save to") {
            HStack(spacing: 8) {
                Text((folder.path as NSString).abbreviatingWithTildeInPath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .help(folder.path)
                Button("Choose…") { choosing = true }
            }
        }
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { folder = url }
        }
        .fileDialogDefaultDirectory(folder)
        .fileDialogConfirmationLabel("Use Folder")
        .fileDialogMessage("Where should Shortty save screenshots?")
        if folder.standardizedFileURL != AppSettings.downloadsFolder.standardizedFileURL {
            HStack {
                Spacer()
                Button("Use Downloads") { folder = AppSettings.downloadsFolder }
            }
        }
    }
}

/// The history strip, and a way to delete what it keeps.
private struct RecentCapturesRow: View {
    @Binding var isOn: Bool
    private let history = CaptureHistory.shared

    var body: some View {
        Toggle(isOn: $isOn) {
            Text("Show recent captures")
            Text("Keeps your last \(CaptureHistory.limit) captures for reopening and dragging out.")
        }
        LabeledContent("\(history.items.count) kept") {
            Button("Delete All", role: .destructive) { history.removeAll() }
                .disabled(history.items.isEmpty)
        }
    }
}

struct ShortcutsSettingsView: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("Capture") {
                shortcutRow("Region", .region)
                shortcutRow("Repeat last region", .repeatRegion)
                shortcutRow("Screen", .screen)
                shortcutRow("Window (click to pick)", .window)
                shortcutRow("Active window", .activeWindow)
                shortcutRow("Scrolling", .scrolling)
                shortcutRow("Text or QR code", .captureText)
                shortcutRow("Reopen last capture", .reopen)
            }
            Section {
                shortcutRow("Region", .lazyRegion)
                shortcutRow("Screen", .lazyScreen)
                LabeledContent("Delay") { delayField }
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

    /// Saves on Return or when you leave the field, clamped to 1–30; anything that isn't a number snaps back.
    private var delayField: some View {
        let range = AppSettings.lazyDelayRange
        return HStack(spacing: 6) {
            TextField("", value: Binding(get: { settings.lazyDelay }, set: { settings.lazyDelay = $0.clamped(to: range) }), format: .number)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 44)
            Text("seconds").foregroundStyle(.secondary)
        }
        .help("Between \(range.lowerBound) and \(range.upperBound) seconds")
    }
}
