import Foundation
import Observation
import SwiftCastCore

/// User preferences, persisted in `UserDefaults`. Launch at login isn't here: it lives in
/// `SMAppService`, which is the source of truth for it.
@MainActor
@Observable
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    /// The global shortcut that toggles the launcher.
    var shortcut: Shortcut {
        didSet { save(shortcut, forKey: "hotKey") }
    }

    /// Folders searched for apps on top of `AppIndexer.defaultRoots`.
    var extraFolders: [URL] {
        didSet {
            defaults.set(extraFolders.map(\.path), forKey: "searchFolders")
            onFoldersChange()
        }
    }

    @ObservationIgnored var onFoldersChange: () -> Void = {}

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        shortcut = defaults.data(forKey: "hotKey")
            .flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) } ?? .default
        extraFolders = (defaults.stringArray(forKey: "searchFolders") ?? []).map { URL(filePath: $0) }
    }

    private func save(_ value: some Encodable, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }
}
