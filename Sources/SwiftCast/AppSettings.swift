import Foundation
import Observation
import SwiftCastCore

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

    @ObservationIgnored var onPluginsChange: () -> Void = {}

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        shortcut = defaults.data(forKey: "hotKey")
            .flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) } ?? .default
        restoreInterval = defaults.object(forKey: "restoreInterval") as? TimeInterval ?? 60
        disabledPlugins = Set(defaults.stringArray(forKey: "disabledPlugins") ?? [])
    }

    private func save(_ value: some Encodable, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }
}
