import AppKit
import ServiceManagement
import SwiftCastCore
import SwiftCastPluginKit
import SwiftUI

/// What the Settings window asks the app to do; supplied by `AppDelegate`.
@MainActor
struct SettingsActions {
    /// Registers `shortcut` as the global hotkey; false if another app already holds it.
    var setShortcut: (Shortcut) -> Bool
    /// Suspends the global hotkey while the recorder listens, and restores it afterwards.
    var setRecording: (Bool) -> Void
    var clearSearchHistory: () -> Void
}

/// A page in the Settings sidebar.
enum SettingsPage: Hashable {
    case general
    case plugin(String)
}

/// The window's own UI state. An observable object rather than `@State`, which is a macro
/// whose plugin ships only with Xcode, not the Command Line Tools this project builds with.
@MainActor
@Observable
private final class SettingsViewState {
    var page: SettingsPage? = .general
    var shortcutError: String?
    var launchAtLogin = SMAppService.mainApp.status == .enabled
    var loginError: String?
    var confirmingClear = false
    var historyCleared = false
}

/// Settings, System Settings–style: General, then a page per plugin where it can be turned
/// on and off and shows its own settings.
struct SettingsView: View {
    @Bindable var settings: AppSettings
    /// Each gets a page, in registry order.
    let plugins: [any LauncherPlugin]
    let actions: SettingsActions
    @Bindable private var state = SettingsViewState()

    var body: some View {
        NavigationSplitView {
            List(selection: $state.page) {
                Label("General", systemImage: "gearshape")
                    .tag(SettingsPage.general)
                Section("Plugins") {
                    ForEach(plugins.indices, id: \.self) { index in
                        let plugin = plugins[index]
                        Label {
                            Text(plugin.name)
                        } icon: {
                            Self.image(for: plugin.icon)
                        }
                        .opacity(isEnabled(plugin) ? 1 : 0.5)
                        .tag(SettingsPage.plugin(plugin.id))
                    }
                }
            }
            .navigationSplitViewColumnWidth(190)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            switch state.page ?? .general {
            case .general:
                generalPage
            case .plugin(let id):
                if let plugin = plugins.first(where: { $0.id == id }) {
                    pluginPage(plugin)
                }
            }
        }
        .frame(width: 700, height: 560)
    }

    private var generalPage: some View {
        Form {
            Section {
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

            Section("History") {
                LabeledContent {
                    Button(state.historyCleared ? "Cleared" : "Clear…") { state.confirmingClear = true }
                        .disabled(state.historyCleared)
                } label: {
                    Text("Search history")
                    Text("Searches you acted on, which ↑ and ↓ step through in an empty field.")
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
        .navigationTitle("General")
        .alert("Clear search history?", isPresented: $state.confirmingClear) {
            Button("Clear", role: .destructive) {
                actions.clearSearchHistory()
                state.historyCleared = true
            }
        } message: {
            Text("↑ and ↓ will have no past searches to step through.")
        }
    }

    private func pluginPage(_ plugin: any LauncherPlugin) -> some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { isEnabled(plugin) },
                    set: { setEnabled($0, plugin.id) }
                )) {
                    Text("Enabled")
                    Text(plugin.summary)
                }
            }
            plugin.settingsView()
        }
        .formStyle(.grouped)
        .navigationTitle(plugin.name)
    }

    private func isEnabled(_ plugin: any LauncherPlugin) -> Bool {
        !settings.disabledPlugins.contains(plugin.id)
    }

    private func setEnabled(_ enabled: Bool, _ id: String) {
        if enabled {
            settings.disabledPlugins.remove(id)
        } else {
            settings.disabledPlugins.insert(id)
        }
    }

    @ViewBuilder
    private static func image(for icon: ResultIcon) -> some View {
        switch icon {
        case .file(let path): Image(nsImage: IconCache.shared.icon(for: path)).resizable().frame(width: 20, height: 20)
        case .symbol(let name): Image(systemName: name)
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

    /// Choices for how long a closed panel keeps its search.
    private static let restoreChoices: [(label: String, seconds: TimeInterval)] = [
        ("Never", 0), ("15 seconds", 15), ("30 seconds", 30), ("1 minute", 60),
        ("2 minutes", 120), ("5 minutes", 300), ("10 minutes", 600),
    ]

    private static var version: String {
        let info = Bundle.main.infoDictionary
        guard let short = info?["CFBundleShortVersionString"] as? String else { return "Development build" }
        return "\(short) (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }
}
