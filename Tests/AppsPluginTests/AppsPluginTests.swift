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

    @Test func showsTheOriginalNameBelowATranslatedOne() {
        let url = URL(filePath: "/Applications/Calculator.app")
        let app = AppEntry(name: "计算器", bundleID: nil, url: url, alternateNames: ["Calculator"], originalName: "Calculator")
        let item = AppsPlugin.item(for: SearchResult(app: app), detail: "~/Apps")
        #expect(item.subtitle == "Calculator")
        #expect(item.detail == "~/Apps")
        let plain = AppEntry(name: "Safari", bundleID: nil, url: url)
        #expect(AppsPlugin.item(for: SearchResult(app: plain), detail: nil).subtitle == nil)
    }

    @Test func rowsUseTheAppsUsage() throws {
        let plugin = makePlugin(["Mail", "Maps"].map {
            AppEntry(name: $0, bundleID: nil, url: URL(filePath: "/Applications/\($0).app"))
        })
        let maps = try #require(plugin.engine.apps.first { $0.name == "Maps" })
        plugin.engine.usageBoost = { $0 == maps.id ? 30 : 0 }
        #expect(plugin.results(for: "ma").map(\.title) == ["Maps", "Mail"])
        #expect(plugin.results(for: "ma").map(\.match) == [.prefix, .prefix])
    }

    @Test func handsOverOldLaunchesOnce() {
        let database = Database.inMemory(migrations: AppsPlugin.migrations)
        let lastUsed = Date(timeIntervalSince1970: 1_000_000)
        database.execute("INSERT INTO launches (app_id, count, last_used) VALUES ('com.apple.Safari', 3, ?)",
                         [.double(lastUsed.timeIntervalSince1970)])
        let plugin = AppsPlugin(database: database)
        var imported: [[UsageRecord]] = []
        let context = PluginContext(importUsage: { imported.append($0) })
        plugin.handOverLaunches(to: context)
        plugin.handOverLaunches(to: context)
        #expect(imported == [[UsageRecord(id: "com.apple.Safari", count: 3, lastUsed: lastUsed)]])
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
}
