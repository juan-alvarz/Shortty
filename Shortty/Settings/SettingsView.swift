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
            Section { AboutRow() }
            Section {
                LaunchAtLoginToggle()
                Toggle("Play sound when capturing", isOn: $settings.captureSound)
            }
            Section("Capturing") {
                SelectionColorRow(hex: $settings.selectionColorHex)
            }
            Section("Saving") {
                SaveFolderRow(folder: $settings.saveFolder)
            }
            Section("Editor") {
                Picker("Layout", selection: $settings.editorLayout) {
                    ForEach(EditorLayout.allCases, id: \.self) { Text($0.title) }
                }
                LabeledContent("After a capture") {
                    HStack(spacing: 12) {
                        Picker("Show", selection: $settings.afterCapture) {
                            ForEach(AfterCapture.allCases, id: \.self) { Text($0.title) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        Toggle("Copy", isOn: $settings.copyAfterCapture)
                        Toggle("Save", isOn: $settings.saveAfterCapture)
                    }
                    .toggleStyle(.checkbox)
                }
                RecentCapturesRow(isOn: $settings.showsHistory)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The app icon, name and version; the version opens its release notes.
struct AboutRow: View {
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    /// Releases are tagged `v<version>` (see the publish routine).
    static let releaseNotes = URL(string: "https://github.com/juan-alvarz/Shortty/releases/tag/v\(version)")!

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text("Shortty").font(.headline)
                Link("Version \(Self.version)", destination: Self.releaseNotes)
                    .help("Release notes for this version")
            }
        }
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

/// The selection overlay's color: the Mac's accent color until another is picked.
private struct SelectionColorRow: View {
    @Binding var hex: String?

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                if hex != nil {
                    Button("Use Accent Color") { hex = nil }
                }
                ColorPicker("", selection: Binding(get: { Color(nsColor: AppSettings.shared.selectionColor) }, set: { hex = $0.hex }),
                            supportsOpacity: false)
                    .labelsHidden()
            }
        } label: {
            Text("Selection color")
            Text(hex == nil ? "Follows the accent color in System Settings → Appearance." : "The outline while selecting an area or counting down.")
        }
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
                ForEach([CaptureAction.region, .repeatRegion, .screen, .window, .activeWindow, .scrolling, .captureText, .reopen], id: \.self, content: shortcutRow)
            }
            Section("Lazy shots") {
                ForEach([CaptureAction.lazyRegion, .lazyScreen], id: \.self, content: shortcutRow)
                LabeledContent("Delay") { delayField }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The action, what it does, and its shortcut (none until you record one).
    private func shortcutRow(_ action: CaptureAction) -> some View {
        LabeledContent {
            HotkeyRecorder(hotkey: Binding(get: { settings.hotkeys[action] ?? .none }, set: { settings.hotkeys[action] = $0 }))
        } label: {
            Text(action.title)
            Text(action.summary)
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
