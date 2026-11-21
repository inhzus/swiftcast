import Foundation
import SwiftCastPluginKit
import Testing
@testable import AppsPlugin

@MainActor
struct UsageStoreTests {
    private let url = FileManager.default.temporaryDirectory
        .appending(path: "SwiftCastTests-\(UUID().uuidString)/apps.db")

    /// A fresh connection to the same file each call, so reads after reopening come from disk.
    private func database() -> Database { try! Database(url: url, migrations: AppsPlugin.migrations) }
    private let now = Date()

    @Test func boostFadesWithAge() {
        let store = UsageStore(database: database())
        for _ in 0..<3 { store.increment("app", at: now) }
        let fresh = store.boost(for: "app", at: now)
        let weekOld = store.boost(for: "app", at: now.addingTimeInterval(7 * 86_400))
        #expect(fresh == 30)
        #expect(weekOld == 15)
        #expect(store.boost(for: "never", at: now) == 0)
    }

    @Test func boostIsCapped() {
        let store = UsageStore(database: database())
        for _ in 0..<10_000 { store.increment("app", at: now) }
        #expect(store.boost(for: "app", at: now) == UsageStore.maxBoost)
    }

    @Test func recentUseBeatsOldFrequentUse() {
        let store = UsageStore(database: database())
        for _ in 0..<10 { store.increment("old", at: now.addingTimeInterval(-60 * 86_400)) }
        store.increment("new", at: now)
        #expect(store.boost(for: "new", at: now) > store.boost(for: "old", at: now))
    }

    @Test func persistsAcrossInstances() {
        UsageStore(database: database()).increment("app", at: now)
        #expect(UsageStore(database: database()).count(for: "app") == 1)
    }

    @Test func clearForgetsEverything() {
        let store = UsageStore(database: database())
        store.increment("app", at: now)
        store.clear()
        #expect(store.count(for: "app") == 0)
        #expect(store.boost(for: "app", at: now) == 0)
        #expect(UsageStore(database: database()).count(for: "app") == 0)
    }
}
