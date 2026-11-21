import Foundation
import SwiftCastPluginKit
import Testing
@testable import AppsPlugin

@MainActor
struct AppsPluginTests {
    private func makePlugin(_ apps: [AppEntry]) -> AppsPlugin {
        let plugin = AppsPlugin(defaults: UserDefaults(suiteName: "SwiftCastTests-\(UUID().uuidString)")!)
        plugin.engine.update(apps: apps)
        return plugin
    }

    @Test func mapsMatchesToRows() {
        let url = URL(filePath: "/Applications/Safari.app")
        let plugin = makePlugin([AppEntry(name: "Safari", bundleID: "com.apple.Safari", url: url)])
        #expect(plugin.results(for: "saf") == [ResultItem(
            id: "com.apple.Safari",
            title: "Safari",
            highlightedIndices: [0, 1, 2],
            icon: .file(url.path),
            actions: [ResultAction("Open", .openApplication(url)), ResultAction("Show in Finder", .revealInFinder(url))]
        )])
    }

    @Test func openingCountsAsUsage() throws {
        let url = URL(filePath: "/Applications/Safari.app")
        let plugin = makePlugin([AppEntry(name: "Safari", bundleID: "com.apple.Safari", url: url)])
        let item = try #require(plugin.results(for: "saf").first)
        plugin.didPerform(item.actions[1], on: item)
        #expect(plugin.engine.usage.count(for: item.id) == 0)
        plugin.didPerform(item.actions[0], on: item)
        #expect(plugin.engine.usage.count(for: item.id) == 1)
        plugin.clearLaunchHistory()
        #expect(plugin.engine.usage.count(for: item.id) == 0)
    }
}
