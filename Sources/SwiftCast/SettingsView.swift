import AppKit
import ServiceManagement
import SwiftCastCore
import SwiftCastPluginKit
import SwiftUI

/// What the Settings window asks the app to do; supplied by `AppDelegate`.
@MainActor
struct SettingsActions {
    /// Registers `shortcut` as the global hotkey, or returns why it can't be used.
    var setShortcut: (Shortcut) -> String?
    /// Suspends the global hotkeys while the recorder listens, and restores them afterwards.
    var setRecording: (Bool) -> Void
    /// Sets, or with `nil` turns off, the global hotkey that opens a plugin's view (by
    /// plugin ID), or returns why it can't be used.
    var setViewShortcut: (Shortcut?, String) -> String?
    var clearSearchHistory: () -> Void
    var clearUsage: () -> Void
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
    /// Why a plugin's view shortcut couldn't be set, by plugin ID.
    var viewShortcutErrors: [String: String] = [:]
    var launchAtLogin = SMAppService.mainApp.status == .enabled
    var loginError: String?
    var confirmingClear = false
    var historyCleared = false
    var confirmingClearUsage = false
    var usageCleared = false
}

/// Settings, System Settings–style: General, then a page per plugin where it can be turned
/// on and off and shows its own settings. `SettingsWindowController` hosts `sidebar` and
/// `detail` in the columns of an AppKit split view, which floats the sidebar as glass; a
/// SwiftUI `NavigationSplitView` in a hosting controller doesn't.
@MainActor
struct SettingsView {
    @Bindable var settings: AppSettings
    /// Each gets a page, in registry order.
    let plugins: [any LauncherPlugin]
    let actions: SettingsActions
    @Bindable private var state = SettingsViewState()
    @Bindable private var pluginState = PluginSettingsState()

    var sidebar: some View {
        List(selection: $state.page) {
            Label {
                Text("General")
            } icon: {
                IconTile(icon: .symbol("gearshape.fill"), tint: .gray, size: 22)
            }
            .tag(SettingsPage.general)
            Section("Plugins") {
                ForEach(plugins.indices, id: \.self) { index in
                    let plugin = plugins[index]
                    Label {
                        Text(plugin.name)
                    } icon: {
                        IconTile(icon: plugin.icon, tint: Self.tint(for: plugin.id), size: 22)
                    }
                    .opacity(isEnabled(plugin) ? 1 : 0.5)
                    .tag(SettingsPage.plugin(plugin.id))
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    var detail: some View {
        switch state.page ?? .general {
        case .general:
            generalPage
        case .plugin(let id):
            if let plugin = plugins.first(where: { $0.id == id }) {
                pluginPage(plugin)
            }
        }
    }

    /// The shown page's name, for the window title.
    var title: String {
        switch state.page ?? .general {
        case .general: "General"
        case .plugin(let id): plugins.first { $0.id == id }?.name ?? "Settings"
        }
    }

    private var generalPage: some View {
        Form {
            PageHeader(title: "SwiftCast", subtitle: Self.version) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
            }

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
                    ErrorText(shortcutError)
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
                    ErrorText(loginError)
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
                LabeledContent {
                    Button(state.usageCleared ? "Cleared" : "Clear…") { state.confirmingClearUsage = true }
                        .disabled(state.usageCleared)
                } label: {
                    Text("Usage")
                    Text("Ranks the results you pick most first.")
                }
                .alert("Clear usage?", isPresented: $state.confirmingClearUsage) {
                    Button("Clear", role: .destructive) {
                        actions.clearUsage()
                        state.usageCleared = true
                    }
                } message: {
                    Text("Results go back to being ranked only by how well they match.")
                }
            }

            Section("About") {
                LabeledContent("Source code") {
                    Link("github.com/inhzus/swiftcast", destination: URL(string: "https://github.com/inhzus/swiftcast")!)
                }
            }
        }
        .formStyle(.grouped)
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
            PageHeader(title: plugin.name, subtitle: plugin.summary) {
                IconTile(icon: plugin.icon, tint: Self.tint(for: plugin.id), size: 64)
            }
            Section {
                Toggle("Enabled", isOn: Binding(
                    get: { isEnabled(plugin) },
                    set: { setEnabled($0, plugin.id) }
                ))
            }
            if let viewTitle = plugin.viewTitle {
                Section {
                    LabeledContent("Open \(viewTitle)") {
                        HStack {
                            ShortcutRecorder(
                                shortcut: settings.viewShortcut(for: plugin),
                                onRecord: { setViewShortcut($0, plugin.id) },
                                onRecordingChange: actions.setRecording
                            )
                            .fixedSize()
                            Button("Clear") { setViewShortcut(nil, plugin.id) }
                                .disabled(settings.viewShortcut(for: plugin) == nil)
                            Button("Reset") { setViewShortcut(plugin.defaultViewShortcut, plugin.id) }
                                .disabled(settings.viewShortcut(for: plugin) == plugin.defaultViewShortcut)
                        }
                    }
                    if let error = state.viewShortcutErrors[plugin.id] {
                        ErrorText(error)
                    }
                }
            }
            PluginSettingsSections(plugin: plugin, state: pluginState)
        }
        .formStyle(.grouped)
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

    /// A plugin's tile color, the same on every launch for the same id.
    private static func tint(for id: String) -> Color {
        let palette: [Color] = [.blue, .indigo, .purple, .pink, .orange, .green, .teal]
        let hash = id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[hash % palette.count]
    }

    private func setShortcut(_ shortcut: Shortcut) {
        state.shortcutError = actions.setShortcut(shortcut)
    }

    private func setViewShortcut(_ shortcut: Shortcut?, _ pluginID: String) {
        state.viewShortcutErrors[pluginID] = actions.setViewShortcut(shortcut, pluginID)
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

/// A System Settings–style icon: a white symbol on a colored rounded square, or an app's own
/// icon, which already has its shape.
struct IconTile: View {
    let icon: ResultIcon
    let tint: Color
    let size: CGFloat

    var body: some View {
        switch icon {
        case .file(let path):
            Image(nsImage: IconCache.shared.icon(for: path))
                .resizable()
                .frame(width: size, height: size)
        case .symbol(let name):
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(tint.gradient)
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: name)
                        .font(.system(size: size * 0.55, weight: .medium))
                        .foregroundStyle(.white)
                }
                // App icons are drawn inset in their canvas; match their visual size.
                .padding(size * 0.08)
                .frame(width: size, height: size)
        }
    }
}

/// The card at the top of a page with its large icon, title and subtitle.
private struct PageHeader<Icon: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let icon: Icon

    var body: some View {
        Section {
            VStack(spacing: 6) {
                icon
                Text(title).font(.title2.bold())
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }
}

/// An inline error under the control it's about.
private struct ErrorText: View {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.red)
    }
}
