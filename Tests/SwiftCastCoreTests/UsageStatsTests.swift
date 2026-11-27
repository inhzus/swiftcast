import Foundation
import SwiftCastPluginKit
import Testing
@testable import SwiftCastCore

@MainActor
struct UsageStatsTests {
    private let url = FileManager.default.temporaryDirectory
        .appending(path: "SwiftCastTests-\(UUID().uuidString)/swiftcast.db")
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }
    /// Noon on 2026-03-15 in `calendar`'s time zone.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 12))!
    }

    /// A fresh connection to the same file each call, so reads after reopening come from disk.
    private func stats() -> UsageStats {
        UsageStats(database: try! Database(url: url, schema: AppDatabase.schema), calendar: calendar)
    }

    private func daysAgo(_ days: Int) -> Date {
        calendar.date(byAdding: .day, value: -days, to: now)!
    }

    private func counts(_ entries: [UsageStats.PluginCount]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.count) })
    }

    @Test func countsAddUpAcrossDays() {
        let stats = stats()
        stats.record(pluginID: "apps", at: now)
        stats.record(pluginID: "apps", at: now)
        stats.record(pluginID: "apps", at: daysAgo(1))
        #expect(counts(stats.topPlugins(in: .today, now: now)) == ["apps": 2])
        #expect(counts(stats.topPlugins(in: .week, now: now)) == ["apps": 3])
    }

    @Test func rangesCoverTheirDays() {
        let stats = stats()
        stats.record(pluginID: "today", at: now)
        stats.record(pluginID: "six", at: daysAgo(6))
        stats.record(pluginID: "seven", at: daysAgo(7))
        stats.record(pluginID: "twenty", at: daysAgo(20))
        stats.record(pluginID: "old", at: daysAgo(400))
        func ids(_ range: UsageStats.Range) -> Set<String> {
            Set(stats.topPlugins(in: range, now: now).map(\.id))
        }
        #expect(ids(.today) == ["today"])
        #expect(ids(.week) == ["today", "six"])
        #expect(ids(.month) == ["today", "six", "seven", "twenty"])
        #expect(ids(.all) == ["today", "six", "seven", "twenty", "old"])
    }

    @Test func daysFollowTheLocalCalendar() {
        let stats = stats()
        // 00:30 local is still the previous day in UTC.
        let justAfterMidnight = calendar.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 0, minute: 30))!
        stats.record(pluginID: "apps", at: justAfterMidnight)
        #expect(stats.topPlugins(in: .today, now: now).map(\.id) == ["apps"])
    }

    @Test func mostUsedFirstAndLimited() {
        let stats = stats()
        for (id, uses) in [("a", 1), ("b", 3), ("c", 2)] {
            for _ in 0..<uses { stats.record(pluginID: id, at: now) }
        }
        #expect(stats.topPlugins(in: .all, limit: 2, now: now).map(\.id) == ["b", "c"])
    }

    @Test func itemsKeepTheirLatestTitleAndStaySeparateFromPlugins() {
        let stats = stats()
        stats.record(pluginID: "apps", item: .init(id: "x", title: "Old", iconPath: "/old"), at: daysAgo(2))
        stats.record(pluginID: "apps", item: .init(id: "x", title: "New", iconPath: "/new"), at: now)
        stats.record(pluginID: "apps", item: .init(id: "y", title: "Y", iconPath: nil), at: now)
        stats.record(pluginID: "clipboard", at: now)
        #expect(stats.topItems(pluginID: "apps", in: .all, now: now) == [
            .init(id: "x", title: "New", iconPath: "/new", count: 2),
            .init(id: "y", title: "Y", iconPath: nil, count: 1),
        ])
        #expect(stats.topItems(pluginID: "clipboard", in: .all, now: now).isEmpty)
        #expect(counts(stats.topPlugins(in: .all, now: now)) == ["apps": 3, "clipboard": 1])
    }

    @Test func recordsRowsOnlyForPluginsThatKeepItemStatistics() {
        let stats = stats()
        let plugin = FakePlugin(id: "apps")
        let result = ResultItem(id: "x", title: "X", icon: .file("/X.app"),
                                actions: [ResultAction("Open", .copy("x"))], match: .prefix)
        stats.record(result, from: plugin, at: now)
        #expect(stats.topItems(pluginID: "apps", in: .all, now: now).isEmpty)
        plugin.tracksItemStatistics = true
        stats.record(result, from: plugin, at: now)
        #expect(counts(stats.topPlugins(in: .all, now: now)) == ["apps": 2])
        #expect(stats.topItems(pluginID: "apps", in: .all, now: now)
            == [.init(id: "x", title: "X", iconPath: "/X.app", count: 1)])
    }

    @Test func persistsAndClears() {
        stats().record(pluginID: "apps", at: now)
        #expect(counts(stats().topPlugins(in: .all, now: now)) == ["apps": 1])
        stats().clear()
        #expect(stats().topPlugins(in: .all, now: now).isEmpty)
    }
}
