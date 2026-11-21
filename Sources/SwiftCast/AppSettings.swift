import Foundation
import Observation
import SwiftCastPluginKit

/// App-wide preferences (plugins keep their own), persisted in `UserDefaults`. Launch at
/// login isn't here: it lives in `SMAppService`, which is the source of truth for it.
@MainActor
@Observable
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    /// The global shortcut that toggles the launcher.
    var shortcut: Shortcut {
        didSet { save(shortcut, forKey: "hotKey") }
    }

    /// Global shortcuts that open plugins' views, by plugin ID, where the user changed them:
    /// a missing ID uses the plugin's `defaultViewShortcut`, `nil` means turned off.
    var viewShortcuts: [String: Shortcut?] {
        didSet { save(viewShortcuts, forKey: "viewShortcuts") }
    }

    /// How long after closing the panel a reopen brings back the last search; 0 never does.
    var restoreInterval: TimeInterval {
        didSet { defaults.set(restoreInterval, forKey: "restoreInterval") }
    }

    /// IDs of plugins the user turned off. Stored as the ones turned off so that a newly
    /// added plugin starts on.
    var disabledPlugins: Set<String> {
        didSet {
            defaults.set(disabledPlugins.sorted(), forKey: "disabledPlugins")
            onPluginsChange()
        }
    }

    /// Where the launcher opens, as moved by dragging its search capsule.
    var launcherPlacement: LauncherPlacement {
        didSet { save(launcherPlacement, forKey: "launcherPlacement") }
    }

    @ObservationIgnored var onPluginsChange: () -> Void = {}

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        shortcut = defaults.data(forKey: "hotKey")
            .flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) } ?? .default
        viewShortcuts = defaults.data(forKey: "viewShortcuts")
            .flatMap { try? JSONDecoder().decode([String: Shortcut?].self, from: $0) } ?? [:]
        restoreInterval = defaults.object(forKey: "restoreInterval") as? TimeInterval ?? 60
        disabledPlugins = Set(defaults.stringArray(forKey: "disabledPlugins") ?? [])
        launcherPlacement = defaults.data(forKey: "launcherPlacement")
            .flatMap { try? JSONDecoder().decode(LauncherPlacement.self, from: $0) } ?? .default
        // Plugin data used to live in UserDefaults; it isn't migrated.
        for key in ["searchFolders", "launchHistory", "queryHistory"] {
            defaults.removeObject(forKey: key)
        }
    }

    /// The shortcut that opens `plugin`'s view, if it has a view and one is set.
    func viewShortcut(for plugin: any LauncherPlugin) -> Shortcut? {
        guard plugin.viewTitle != nil else { return nil }
        if let chosen = viewShortcuts[plugin.id] { return chosen }
        return plugin.defaultViewShortcut
    }

    private func save(_ value: some Encodable, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }
}
