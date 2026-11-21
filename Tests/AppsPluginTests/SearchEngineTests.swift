import Foundation
import SwiftCastPluginKit
import Testing
@testable import AppsPlugin

@MainActor
struct SearchEngineTests {
    private func makeEngine(_ apps: [AppEntry]) -> SearchEngine {
        let engine = SearchEngine(usage: UsageStore(database: .inMemory(migrations: AppsPlugin.migrations)))
        engine.update(apps: apps)
        return engine
    }

    private func makeEngine(_ names: [String]) -> SearchEngine {
        makeEngine(names.map { app($0) })
    }

    private func app(_ name: String, in folder: String = "/Applications", file: String? = nil, alternateNames: [String] = []) -> AppEntry {
        AppEntry(
            name: name,
            bundleID: nil,
            url: URL(filePath: "\(folder)/\(file ?? name).app"),
            alternateNames: alternateNames
        )
    }

    @Test func ranksByMatchQuality() {
        let engine = makeEngine(["iTerm", "Terminal", "Safari"])
        #expect(engine.results(for: "term").map(\.app.name) == ["Terminal", "iTerm"])
    }

    @Test func resultsCarryMatchedIndices() {
        let engine = makeEngine(["System Settings"])
        #expect(engine.results(for: "sys").first?.matchedIndices == [0, 1, 2])
    }

    @Test func usageBoostsAmbiguousMatches() {
        let engine = makeEngine(["Mail", "Maps", "Messages"])
        #expect(engine.results(for: "ma").first?.app.name == "Mail")

        let maps = engine.apps.first { $0.name == "Maps" }!
        for _ in 0..<5 { engine.usage.increment(maps.id) }
        #expect(engine.results(for: "ma").first?.app.name == "Maps")
    }

    @Test func usageNeverBeatsABetterKindOfMatch() {
        let engine = makeEngine(["Notes", "Notes Helper Thing"])
        let helper = engine.apps.first { $0.name != "Notes" }!
        for _ in 0..<1000 { engine.usage.increment(helper.id) }
        #expect(engine.results(for: "notes").first?.app.name == "Notes")
    }

    @Test func emptyQueryShowsRecentlyUsed() {
        let engine = makeEngine(["Mail", "Maps", "Notes"])
        #expect(engine.results(for: "").isEmpty)

        let now = Date()
        let notes = engine.apps.first { $0.name == "Notes" }!
        let mail = engine.apps.first { $0.name == "Mail" }!
        for _ in 0..<3 { engine.usage.increment(mail.id, at: now.addingTimeInterval(-30 * 86_400)) }
        engine.usage.increment(notes.id, at: now)
        #expect(engine.results(for: "", now: now).map(\.app.name) == ["Notes", "Mail"])
    }

    @Test func alternateNamesMatchWithASmallPenalty() {
        let engine = makeEngine([
            app("Visual Studio Code", alternateNames: ["Code"]),
            app("Codex"),
            app("Code", in: "/Users/me/Applications"),
        ])
        // An exact alternate name beats another app's prefix match, but not an exact own name.
        let results = engine.results(for: "code")
        #expect(results.map(\.app.name) == ["Code", "Visual Studio Code", "Codex"])
        #expect(results[1].matchedIndices == [14, 15, 16, 17])

        let alternateOnly = makeEngine([app("Visual Studio Code", alternateNames: ["Electron"])])
        #expect(alternateOnly.results(for: "elec").first?.matchedIndices == [])
    }

    @Test func detailsTellApartAppsSharingAName() {
        let engine = makeEngine([
            app("Siri", in: "/System/Applications"),
            app("Siri", in: "/System/Applications", file: "Siri AI"),
            app("Tool", in: "/Applications"),
            app("Tool", in: "/Applications/Utilities"),
            app("Notes"),
        ])
        let details = engine.apps.map { engine.detail(for: $0) }
        #expect(details == ["Siri.app", "Siri AI.app", "/Applications", "/Applications/Utilities", nil])
    }
}
