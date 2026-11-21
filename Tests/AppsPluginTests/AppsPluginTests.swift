import Foundation
import SwiftCastPluginKit
import Testing
@testable import AppsPlugin

@MainActor
struct AppsPluginTests {
    private func makePlugin(_ apps: [AppEntry]) -> AppsPlugin {
        let plugin = AppsPlugin(database: .inMemory(migrations: AppsPlugin.migrations))
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

    @Test func settingsListDefaultAndAddedFolders() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "SwiftCastTests-\(UUID().uuidString)/apps.db")
        let plugin = AppsPlugin(database: try Database(url: url, migrations: AppsPlugin.migrations))
        let extra = URL(filePath: "/tmp/MoreApps")
        // A default root and a repeat are dropped.
        plugin.setSetting("searchFolders", to: .folders([extra, AppIndexer.defaultRoots[0], extra]))
        #expect(plugin.settings.extraFolders == [extra])

        let reopened = AppsPlugin(database: try Database(url: url, migrations: AppsPlugin.migrations))
        #expect(reopened.settingsSections().first?.rows.first?.control == .folders(
            fixed: AppIndexer.defaultRoots, editable: [extra], addPrompt: "Choose folders to search for apps"))
    }

    @Test func clearingLaunchHistoryFromSettings() throws {
        let url = URL(filePath: "/Applications/Safari.app")
        let plugin = makePlugin([AppEntry(name: "Safari", bundleID: "com.apple.Safari", url: url)])
        func clearEnabled() -> Bool? {
            guard case .button(_, let enabled, _) = plugin.settingsSections().last?.rows.first?.control else { return nil }
            return enabled
        }
        #expect(clearEnabled() == false)
        let item = try #require(plugin.results(for: "saf").first)
        plugin.didPerform(item.actions[0], on: item)
        #expect(clearEnabled() == true)
        plugin.performSettingsAction("clearLaunchHistory")
        #expect(plugin.engine.usage.count(for: item.id) == 0)
        #expect(clearEnabled() == false)
    }
}
