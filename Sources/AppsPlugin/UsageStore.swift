import Foundation
import SwiftCastPluginKit

/// Persists how often and how recently each app was launched, to boost the apps the user
/// reaches for now (frecency). Old launches fade with a one-week half-life.
@MainActor
final class UsageStore {
    struct Record: Equatable {
        var count: Int
        var lastUsed: Date
    }

    /// Highest boost an app can get; below the 100-point gap between match tiers, so usage
    /// reorders apps within a tier but never lifts a weaker kind of match over a stronger one.
    static let maxBoost = 60
    static let halfLife: TimeInterval = 7 * 24 * 60 * 60

    private let database: Database
    /// All of `launches`, read once: `boost` runs for every app on every keystroke.
    private var records: [String: Record] = [:]

    init(database: Database) {
        self.database = database
        for row in database.rows("SELECT app_id, count, last_used FROM launches") {
            guard let id = row[0].text, let count = row[1].int, let lastUsed = row[2].double else { continue }
            records[id] = Record(count: Int(count), lastUsed: Date(timeIntervalSince1970: lastUsed))
        }
    }

    func count(for id: String) -> Int {
        records[id]?.count ?? 0
    }

    func increment(_ id: String, at now: Date = Date()) {
        var record = records[id] ?? Record(count: 0, lastUsed: now)
        record.count += 1
        record.lastUsed = max(record.lastUsed, now)
        records[id] = record
        database.execute("""
            INSERT INTO launches (app_id, count, last_used) VALUES (?, 1, ?)
            ON CONFLICT (app_id) DO UPDATE SET
                count = count + 1, last_used = max(last_used, excluded.last_used)
            """, [.text(id), .double(now.timeIntervalSince1970)])
    }

    /// Forgets all launch history.
    func clear() {
        records = [:]
        database.execute("DELETE FROM launches")
    }

    /// Up to `maxBoost` points: grows logarithmically with launch count and halves for every
    /// week since the last launch. Zero for apps never launched.
    func boost(for id: String, at now: Date = Date()) -> Int {
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
