import Foundation
import Observation
import SwiftCastPluginKit

/// How many times a day the user ran an action on each plugin's rows, and on each row of the
/// plugins that keep item statistics (`LauncherPlugin.tracksItemStatistics`), for the
/// Statistics page in Settings. Kept in the app's database (see `AppDatabase`), by local day.
/// Observable, so an open Statistics page queries again after each use.
///
/// For display only: ranking uses `UsageStore`, which this never affects. Unlike
/// `UsageStore`, it counts actions run in a plugin's view too, not only in search.
@MainActor
@Observable
public final class UsageStats {
    /// A stretch of days ending today.
    public enum Range: CaseIterable, Hashable, Sendable {
        case today, week, month, quarter, all

        /// Days covered, today included; `nil` for all time.
        public var days: Int? {
            switch self {
            case .today: 1
            case .week: 7
            case .month: 30
            case .quarter: 90
            case .all: nil
            }
        }

        public var label: String {
            switch self {
            case .today: "Today"
            case .week: "7 Days"
            case .month: "30 Days"
            case .quarter: "90 Days"
            case .all: "All Time"
            }
        }
    }

    /// A row that was used: its title and icon as last seen.
    struct Item: Equatable {
        var id: String
        var title: String
        var iconPath: String?
    }

    /// A plugin and how often its rows were used in a range.
    public struct PluginCount: Equatable, Sendable {
        public var id: String
        public var count: Int
    }

    /// A row and how often it was used in a range, with its title and icon as last seen.
    public struct ItemCount: Equatable, Sendable {
        public var id: String
        public var title: String
        public var iconPath: String?
        public var count: Int
    }

    @ObservationIgnored private let database: Database
    @ObservationIgnored private let calendar: Calendar
    /// Bumped by every write; the queries read it, so observers see the counts change.
    private var revision = 0

    public init(database: Database, calendar: Calendar = .current) {
        self.database = database
        self.calendar = calendar
    }

    /// Counts an action run on `result`: always toward `plugin`, and toward `result` itself
    /// when `plugin` keeps item statistics.
    public func record(_ result: ResultItem, from plugin: any LauncherPlugin, at now: Date = Date()) {
        var item: Item?
        if plugin.tracksItemStatistics {
            var iconPath: String?
            if case .file(let path) = result.icon { iconPath = path }
            item = Item(id: result.id, title: result.title, iconPath: iconPath)
        }
        record(pluginID: plugin.id, item: item, at: now)
    }

    /// Counts one use of `pluginID`, and of `item` when given.
    func record(pluginID: String, item: Item? = nil, at now: Date = Date()) {
        let day = Self.dayString(now, calendar: calendar)
        database.transaction {
            database.execute("""
                INSERT INTO daily_plugin_usage (day, plugin_id, count) VALUES (?, ?, 1)
                ON CONFLICT (day, plugin_id) DO UPDATE SET count = count + 1
                """, [.text(day), .text(pluginID)])
            if let item {
                database.execute("""
                    INSERT INTO daily_item_usage (day, plugin_id, item_id, title, icon_path, count)
                    VALUES (?, ?, ?, ?, ?, 1)
                    ON CONFLICT (day, plugin_id, item_id) DO UPDATE SET
                        count = count + 1, title = excluded.title, icon_path = excluded.icon_path
                    """, [.text(day), .text(pluginID), .text(item.id), .text(item.title),
                          item.iconPath.map { .text($0) } ?? .null])
            }
        }
        revision += 1
    }

    /// The most used plugins in `range`, most used first.
    public func topPlugins(in range: Range, limit: Int = 10, now: Date = Date()) -> [PluginCount] {
        _ = revision
        return database.rows("""
            SELECT plugin_id, SUM(count) AS total FROM daily_plugin_usage
            WHERE day >= ? GROUP BY plugin_id
            ORDER BY total DESC, plugin_id LIMIT ?
            """, [.text(cutoff(range, now: now)), .int(Int64(limit))]
        ).compactMap { row in
            guard let id = row["plugin_id"].text, let total = row["total"].int else { return nil }
            return PluginCount(id: id, count: Int(total))
        }
    }

    /// `pluginID`'s most used rows in `range`, most used first, with the title and icon they
    /// had on the latest day they were used.
    public func topItems(pluginID: String, in range: Range, limit: Int = 10, now: Date = Date()) -> [ItemCount] {
        _ = revision
        // SQLite takes the bare columns from the row that holds `MAX(day)`.
        return database.rows("""
            SELECT item_id, title, icon_path, MAX(day), SUM(count) AS total FROM daily_item_usage
            WHERE plugin_id = ? AND day >= ? GROUP BY item_id
            ORDER BY total DESC, title LIMIT ?
            """, [.text(pluginID), .text(cutoff(range, now: now)), .int(Int64(limit))]
        ).compactMap { row in
            guard let id = row["item_id"].text, let title = row["title"].text,
                  let total = row["total"].int else { return nil }
            return ItemCount(id: id, title: title, iconPath: row["icon_path"].text, count: Int(total))
        }
    }

    /// Forgets all statistics.
    public func clear() {
        database.transaction {
            database.execute("DELETE FROM daily_plugin_usage")
            database.execute("DELETE FROM daily_item_usage")
        }
        revision += 1
    }

    /// The first day in `range`, as stored; "" for all time, which every day sorts after.
    private func cutoff(_ range: Range, now: Date) -> String {
        guard let days = range.days,
              let first = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now))
        else { return "" }
        return Self.dayString(first, calendar: calendar)
    }

    /// `yyyy-MM-dd` in `calendar`'s time zone, so days sort as text.
    static func dayString(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
