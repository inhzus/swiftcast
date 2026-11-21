import Foundation
import SwiftCastPluginKit

/// Searches the user acted on (opened an app, revealed one, copied a result), newest first.
/// Keeps them in the app's database (see `AppDatabase`).
@MainActor
public final class QueryHistory {
    public static let limit = 100

    private let database: Database
    public private(set) var entries: [String]

    public init(database: Database) {
        self.database = database
        // `INSERT OR REPLACE` gives a re-recorded query a new, higher rowid, which breaks ties
        // between queries recorded within the clock's resolution.
        entries = database.rows(
            "SELECT query FROM query_history ORDER BY last_used DESC, rowid DESC LIMIT ?",
            [.int(Int64(Self.limit))]
        ).compactMap { $0[0].text }
    }

    /// Moves `query` to the front, dropping an earlier copy. Blank queries are ignored.
    public func record(_ query: String) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        entries.removeAll { $0 == query }
        entries.insert(query, at: 0)
        if entries.count > Self.limit {
            entries.removeLast(entries.count - Self.limit)
        }
        database.transaction {
            database.execute(
                "INSERT OR REPLACE INTO query_history (query, last_used) VALUES (?, ?)",
                [.text(query), .double(Date().timeIntervalSince1970)])
            database.execute("""
                DELETE FROM query_history WHERE rowid NOT IN
                    (SELECT rowid FROM query_history ORDER BY last_used DESC, rowid DESC LIMIT ?)
                """, [.int(Int64(Self.limit))])
        }
    }

    public func clear() {
        entries = []
        database.execute("DELETE FROM query_history")
    }
}

/// Where the user is while stepping through history with ↑/↓, shell-style.
public struct HistoryCursor: Sendable {
    /// The entry being shown; `nil` when not browsing.
    public private(set) var index: Int?

    public init() {}

    public var isBrowsing: Bool { index != nil }

    /// Steps older (`delta` +1) or newer (−1) and returns the text to show, or `nil` when the
    /// key isn't a history step and should do its usual job. Stepping newer than the newest
    /// entry ends browsing and returns "".
    public mutating func move(_ delta: Int, through entries: [String]) -> String? {
        guard let index else {
            guard delta > 0, !entries.isEmpty else { return nil }
            self.index = 0
            return entries[0]
        }
        let next = index + delta
        if next < 0 {
            self.index = nil
            return ""
        }
        let clamped = min(next, entries.count - 1)
        self.index = clamped
        return entries[clamped]
    }

    public mutating func reset() {
        index = nil
    }
}
