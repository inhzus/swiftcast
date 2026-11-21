import Foundation

/// Persists how often each app has been launched, to boost frequently used apps in results.
@MainActor
public final class UsageStore {
    private let defaults: UserDefaults
    private let key = "launchCounts"
    private var counts: [String: Int]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.counts = defaults.dictionary(forKey: key) as? [String: Int] ?? [:]
    }

    public func count(for id: String) -> Int {
        counts[id, default: 0]
    }

    public func increment(_ id: String) {
        counts[id, default: 0] += 1
        defaults.set(counts, forKey: key)
    }
}
