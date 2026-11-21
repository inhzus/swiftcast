import Foundation
import Testing
@testable import SwiftCastCore

@MainActor
struct QueryHistoryTests {
    private let defaults = UserDefaults(suiteName: "SwiftCastTests-\(UUID().uuidString)")!

    @Test func recordsNewestFirstWithoutDuplicates() {
        let history = QueryHistory(defaults: defaults)
        for query in ["saf", "2*3", " saf ", "", "   "] { history.record(query) }
        #expect(history.entries == ["saf", "2*3"])
    }

    @Test func keepsAtMostTheLimit() {
        let history = QueryHistory(defaults: defaults)
        for i in 0..<(QueryHistory.limit + 5) { history.record("q\(i)") }
        #expect(history.entries.count == QueryHistory.limit)
        #expect(history.entries.first == "q\(QueryHistory.limit + 4)")
    }

    @Test func persistsAndClears() {
        QueryHistory(defaults: defaults).record("saf")
        let history = QueryHistory(defaults: defaults)
        #expect(history.entries == ["saf"])
        history.clear()
        #expect(QueryHistory(defaults: defaults).entries.isEmpty)
    }

    @Test func cursorStepsThroughHistoryLikeAShell() {
        let entries = ["newest", "middle", "oldest"]
        var cursor = HistoryCursor()
        #expect(cursor.move(-1, through: entries) == nil)  // ↓ before browsing: not ours
        #expect(cursor.move(1, through: entries) == "newest")
        #expect(cursor.move(1, through: entries) == "middle")
        #expect(cursor.move(1, through: entries) == "oldest")
        #expect(cursor.move(1, through: entries) == "oldest")  // stays at the oldest
        #expect(cursor.move(-1, through: entries) == "middle")
        #expect(cursor.move(-1, through: entries) == "newest")
        #expect(cursor.move(-1, through: entries) == "")  // back to an empty field
        #expect(!cursor.isBrowsing)
    }

    @Test func cursorWithNoHistoryLeavesKeysAlone() {
        var cursor = HistoryCursor()
        #expect(cursor.move(1, through: []) == nil)
        #expect(!cursor.isBrowsing)
    }

    @Test func resetEndsBrowsing() {
        var cursor = HistoryCursor()
        _ = cursor.move(1, through: ["a"])
        cursor.reset()
        #expect(!cursor.isBrowsing)
    }
}
