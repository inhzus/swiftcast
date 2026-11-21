import Foundation
import Testing
@testable import SwiftCastCore

@MainActor
struct UsageStoreTests {
    private let defaults = UserDefaults(suiteName: "SwiftCastTests-\(UUID().uuidString)")!
    private let now = Date()

    @Test func boostFadesWithAge() {
        let store = UsageStore(defaults: defaults)
        for _ in 0..<3 { store.increment("app", at: now) }
        let fresh = store.boost(for: "app", at: now)
        let weekOld = store.boost(for: "app", at: now.addingTimeInterval(7 * 86_400))
        #expect(fresh == 30)
        #expect(weekOld == 15)
        #expect(store.boost(for: "never", at: now) == 0)
    }

    @Test func boostIsCapped() {
        let store = UsageStore(defaults: defaults)
        for _ in 0..<10_000 { store.increment("app", at: now) }
        #expect(store.boost(for: "app", at: now) == UsageStore.maxBoost)
    }

    @Test func recentUseBeatsOldFrequentUse() {
        let store = UsageStore(defaults: defaults)
        for _ in 0..<10 { store.increment("old", at: now.addingTimeInterval(-60 * 86_400)) }
        store.increment("new", at: now)
        #expect(store.boost(for: "new", at: now) > store.boost(for: "old", at: now))
    }

    @Test func persistsAcrossInstances() {
        UsageStore(defaults: defaults).increment("app", at: now)
        #expect(UsageStore(defaults: defaults).count(for: "app") == 1)
    }

    @Test func clearForgetsEverything() {
        let store = UsageStore(defaults: defaults)
        store.increment("app", at: now)
        store.clear()
        #expect(store.count(for: "app") == 0)
        #expect(store.boost(for: "app", at: now) == 0)
        #expect(UsageStore(defaults: defaults).count(for: "app") == 0)
    }
}
