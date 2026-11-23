import Foundation
import SwiftCastPluginKit

/// Persists how often and how recently the user picked each row, from any plugin, to rank the
/// rows they reach for now first (frecency). Old picks fade with a one-week half-life.
@MainActor
public final class UsageStore {
    /// A row: the plugin it came from and its ID there.
    public struct Key: Hashable, Sendable {
        public var pluginID: String
        public var itemID: String

        public init(pluginID: String, itemID: String) {
            self.pluginID = pluginID
            self.itemID = itemID
        }
    }

    struct Record: Equatable {
        var count: Int
        var lastUsed: Date
    }

    /// Highest boost a row can get.
    public static let maxBoost = 60
    static let halfLife: TimeInterval = 7 * 24 * 60 * 60

    private let database: Database
    /// All of `usage`, read once: `boost` runs for every row on every keystroke.
    private var records: [Key: Record] = [:]

    public init(database: Database) {
        self.database = database
        for row in database.rows("SELECT plugin_id, item_id, count, last_used FROM usage") {
            guard let plugin = row["plugin_id"].text, let item = row["item_id"].text, let count = row["count"].int,
                  let lastUsed = row["last_used"].double else { continue }
            records[Key(pluginID: plugin, itemID: item)] =
                Record(count: Int(count), lastUsed: Date(timeIntervalSince1970: lastUsed))
        }
    }

    public var isEmpty: Bool { records.isEmpty }

    public func count(for key: Key) -> Int {
        records[key]?.count ?? 0
    }

    public func increment(_ key: Key, at now: Date = Date()) {
        add(key, count: 1, lastUsed: now)
    }

    /// Adds usage a plugin kept before the app did, to whatever is recorded already.
    public func `import`(_ usage: [UsageRecord], for pluginID: String) {
        database.transaction {
            for record in usage where record.count > 0 {
                add(Key(pluginID: pluginID, itemID: record.id), count: record.count, lastUsed: record.lastUsed)
            }
        }
    }

    private func add(_ key: Key, count: Int, lastUsed: Date) {
        var record = records[key] ?? Record(count: 0, lastUsed: lastUsed)
        record.count += count
        record.lastUsed = max(record.lastUsed, lastUsed)
        records[key] = record
        database.execute("""
            INSERT INTO usage (plugin_id, item_id, count, last_used) VALUES (?, ?, ?, ?)
            ON CONFLICT (plugin_id, item_id) DO UPDATE SET
                count = count + excluded.count, last_used = max(last_used, excluded.last_used)
            """, [.text(key.pluginID), .text(key.itemID), .int(Int64(count)), .double(lastUsed.timeIntervalSince1970)])
    }

    /// Forgets all usage.
    public func clear() {
        records = [:]
        database.execute("DELETE FROM usage")
    }

    /// Up to `maxBoost` points: grows logarithmically with the pick count and halves for every
    /// week since the last pick. Zero for rows never picked.
    public func boost(for key: Key, at now: Date = Date()) -> Int {
        guard let record = records[key] else { return 0 }
        let age = max(now.timeIntervalSince(record.lastUsed), 0)
        let decay = pow(0.5, age / Self.halfLife)
        return min(Int(15 * log2(Double(record.count + 1)) * decay), Self.maxBoost)
    }
}
