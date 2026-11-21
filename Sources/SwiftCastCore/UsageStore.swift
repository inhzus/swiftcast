import Foundation

/// Persists how often and how recently each app was launched, to boost the apps the user
/// reaches for now (frecency). Old launches fade with a one-week half-life.
@MainActor
public final class UsageStore {
    struct Record: Codable, Equatable {
        var count: Int
        var lastUsed: Date
    }

    /// Highest boost an app can get; below the 100-point gap between match tiers, so usage
    /// reorders apps within a tier but never lifts a weaker kind of match over a stronger one.
    public static let maxBoost = 60
    static let halfLife: TimeInterval = 7 * 24 * 60 * 60

    private let defaults: UserDefaults
    private let key = "launchHistory"
    private var records: [String: Record]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        records = defaults.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([String: Record].self, from: $0) } ?? [:]
    }

    public func count(for id: String) -> Int {
        records[id]?.count ?? 0
    }

    public func increment(_ id: String, at now: Date = Date()) {
        var record = records[id] ?? Record(count: 0, lastUsed: now)
        record.count += 1
        record.lastUsed = max(record.lastUsed, now)
        records[id] = record
        if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: key)
        }
    }

    /// Forgets all launch history.
    public func clear() {
        records = [:]
        defaults.removeObject(forKey: key)
    }

    /// Up to `maxBoost` points: grows logarithmically with launch count and halves for every
    /// week since the last launch. Zero for apps never launched.
    public func boost(for id: String, at now: Date = Date()) -> Int {
        guard let record = records[id] else { return 0 }
        let age = max(now.timeIntervalSince(record.lastUsed), 0)
        let decay = pow(0.5, age / Self.halfLife)
        return min(Int(15 * log2(Double(record.count + 1)) * decay), Self.maxBoost)
    }

    /// Unbounded frecency, for ordering recently used apps when there is no query.
    func frecency(for id: String, at now: Date) -> Double {
        guard let record = records[id] else { return 0 }
        let age = max(now.timeIntervalSince(record.lastUsed), 0)
        return log2(Double(record.count + 1)) * pow(0.5, age / Self.halfLife)
    }
}
