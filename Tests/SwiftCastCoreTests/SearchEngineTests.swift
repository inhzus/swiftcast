import Foundation
import Testing
@testable import SwiftCastCore

@MainActor
struct SearchEngineTests {
    private func makeEngine(_ names: [String]) -> SearchEngine {
        let defaults = UserDefaults(suiteName: "SwiftCastTests-\(UUID().uuidString)")!
        let engine = SearchEngine(usage: UsageStore(defaults: defaults))
        engine.update(apps: names.map {
            AppEntry(name: $0, bundleID: nil, url: URL(filePath: "/Applications/\($0).app"))
        })
        return engine
    }

    @Test func ranksByMatchQuality() {
        let engine = makeEngine(["iTerm", "Terminal", "Safari"])
        #expect(engine.results(for: "term").map(\.name) == ["Terminal", "iTerm"])
    }

    @Test func usageBoostsAmbiguousMatches() {
        let engine = makeEngine(["Mail", "Maps", "Messages"])
        #expect(engine.results(for: "ma").first?.name == "Mail")

        let maps = engine.apps.first { $0.name == "Maps" }!
        for _ in 0..<5 { engine.usage.increment(maps.id) }
        #expect(engine.results(for: "ma").first?.name == "Maps")
    }

    @Test func emptyQueryShowsMostUsed() {
        let engine = makeEngine(["Mail", "Maps", "Notes"])
        #expect(engine.results(for: "").isEmpty)

        let notes = engine.apps.first { $0.name == "Notes" }!
        engine.usage.increment(notes.id)
        #expect(engine.results(for: "").map(\.name) == ["Notes"])
    }
}
