import AppKit
import ServiceManagement
import SwiftCastCore
import SwiftUI

/// What the Settings window asks the app to do; supplied by `AppDelegate`.
@MainActor
struct SettingsActions {
    /// Registers `shortcut` as the global hotkey; false if another app already holds it.
    var setShortcut: (Shortcut) -> Bool
    /// Suspends the global hotkey while the recorder listens, and restores it afterwards.
    var setRecording: (Bool) -> Void
    var clearHistory: () -> Void
}

/// The window's own UI state. An observable object rather than `@State`, which is a macro
/// whose plugin ships only with Xcode, not the Command Line Tools this project builds with.
@MainActor
@Observable
private final class SettingsViewState {
    var shortcutError: String?
    var launchAtLogin = SMAppService.mainApp.status == .enabled
    var loginError: String?
    var confirmingClear = false
    var historyCleared = false
}

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let actions: SettingsActions
    @Bindable private var state = SettingsViewState()

    var body: some View {
        Form {
            Section("General") {
                LabeledContent("Open SwiftCast") {
                    HStack {
                        ShortcutRecorder(
                            shortcut: settings.shortcut,
                            onRecord: setShortcut,
                            onRecordingChange: actions.setRecording
                        )
                        .fixedSize()
                        Button("Reset") { setShortcut(.default) }
                            .disabled(settings.shortcut == .default)
                    }
                }
                if let shortcutError = state.shortcutError {
                    Text(shortcutError).font(.callout).foregroundStyle(.red)
                }
                Picker("Keep last search for", selection: $settings.restoreInterval) {
                    ForEach(Self.restoreChoices, id: \.seconds) { choice in
                        Text(choice.label).tag(choice.seconds)
                    }
                }
                // A closure, not `set: setLaunchAtLogin`: Swift 6.3 crashes emitting the
                // reabstraction thunk for a method reference here.
                Toggle("Launch at login", isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                if let loginError = state.loginError {
                    Text(loginError).font(.callout).foregroundStyle(.red)
                }
            }

            Section {
                ForEach(AppIndexer.defaultRoots, id: \.self) { folder in
                    Label(Self.displayPath(folder), systemImage: "folder")
                        .foregroundStyle(.secondary)
                }
                ForEach(settings.extraFolders, id: \.self) { folder in
                    HStack {
                        Label(Self.displayPath(folder), systemImage: "folder")
                        Spacer()
                        Button {
                            settings.extraFolders.removeAll { $0 == folder }
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Stop searching this folder")
                    }
                }
                Button("Add Folder…", action: addFolders)
            } header: {
                Text("Search")
            } footer: {
                Text("Apps are found up to three folders deep.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section("Usage") {
                LabeledContent {
                    Button(state.historyCleared ? "Cleared" : "Clear…") { state.confirmingClear = true }
                        .disabled(state.historyCleared)
                } label: {
                    Text("Usage history")
                    Text("Ranks the apps you open most, lists recent ones, and remembers your searches.")
                }
            }

            Section("About") {
                LabeledContent("Version", value: Self.version)
                LabeledContent("Source") {
                    Link("github.com/inhzus/swiftcast", destination: URL(string: "https://github.com/inhzus/swiftcast")!)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 680)
        .alert("Clear usage history?", isPresented: $state.confirmingClear) {
            Button("Clear", role: .destructive) {
                actions.clearHistory()
                state.historyCleared = true
            }
        } message: {
            Text("Recent apps and the ranking boost for frequently used apps start over.")
        }
    }

    private func setShortcut(_ shortcut: Shortcut) {
        state.shortcutError = actions.setShortcut(shortcut)
            ? nil
            : "\(shortcut.displayString) is already used by another app."
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled { try service.register() } else { try service.unregister() }
            state.loginError = nil
        } catch {
            state.loginError = error.localizedDescription
        }
        state.launchAtLogin = service.status == .enabled
    }

    private func addFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose folders to search for apps"
        guard panel.runModal() == .OK else { return }
        let known = Set((AppIndexer.defaultRoots + settings.extraFolders).map(\.standardizedFileURL))
        settings.extraFolders += panel.urls.filter { !known.contains($0.standardizedFileURL) }
    }

    /// Choices for how long a closed panel keeps its search.
    private static let restoreChoices: [(label: String, seconds: TimeInterval)] = [
        ("Never", 0), ("15 seconds", 15), ("30 seconds", 30), ("1 minute", 60),
        ("2 minutes", 120), ("5 minutes", 300), ("10 minutes", 600),
    ]

    private static func displayPath(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        guard let short = info?["CFBundleShortVersionString"] as? String else { return "Development build" }
        return "\(short) (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }
}
