import Foundation
import SwiftCastPluginKit
import Testing
@testable import SwiftCastCore

@MainActor
struct PluginHostTests {
    let on = FakePlugin(id: "on")
    let off = FakePlugin(id: "off")
    let usage = UsageStore(database: .inMemory(migrations: AppDatabase.migrations))
    let host: PluginHost

    init() {
        host = PluginHost(plugins: [on, off], disabledIDs: ["off"], usage: usage)
    }

    @Test func startActivatesOnlyEnabledPluginsOnce() async {
        #expect(!host.hasStarted)
        await host.start()
        await host.activateEnabled()
        #expect(host.hasStarted)
        #expect(on.log == ["activate"])
        #expect(off.log.isEmpty)
        #expect(host.enabledPlugins.map(\.id) == ["on"])
    }

    @Test func turningOffDeactivatesAndTurningOnActivatesAgain() async {
        await host.start()
        host.setDisabled(["on", "off"])
        #expect(on.log == ["activate", "deactivate"])
        #expect(host.enabledPlugins.isEmpty)

        host.setDisabled([])
        await host.activateEnabled()
        #expect(on.log == ["activate", "deactivate", "activate"])
        #expect(off.log == ["activate"])
    }

    @Test func pluginsNeverActivatedAreNotDeactivated() {
        host.setDisabled(["on", "off"])
        #expect(on.log.isEmpty)
    }

    @Test func contextReadsAndImportsUsageUnderThePluginsID() async throws {
        var changes = 0
        host.onResultsChange = { changes += 1 }
        await host.start()
        let context = try #require(on.context)

        context.importUsage([UsageRecord(id: "row", count: 3, lastUsed: Date())])
        #expect(usage.count(for: UsageStore.Key(pluginID: "on", itemID: "row")) == 3)
        #expect(context.usageBoost("row") > 0)
        #expect(context.usageBoost("other") == 0)

        context.resultsDidChange()
        #expect(changes == 1)
    }
}

struct ShortcutRulesTests {
    let launcher = Shortcut.default
    let clip = Shortcut(keyCode: 8, modifiers: Shortcut.command | Shortcut.option)
    let notes = Shortcut(keyCode: 45, modifiers: Shortcut.command | Shortcut.option)

    private func conflict(_ shortcut: Shortcut, for target: ShortcutTarget) -> ShortcutTarget? {
        ShortcutRules.conflict(of: shortcut, for: target, launcher: launcher,
                               views: ["clipboard": clip, "notes": notes])
    }

    @Test func launcherCantTakeAViewsShortcut() {
        #expect(conflict(clip, for: .launcher) == .view(pluginID: "clipboard"))
        #expect(conflict(launcher, for: .launcher) == nil)
    }

    @Test func viewCantTakeTheLaunchersOrAnotherViewsShortcut() {
        #expect(conflict(launcher, for: .view(pluginID: "clipboard")) == .launcher)
        #expect(conflict(notes, for: .view(pluginID: "clipboard")) == .view(pluginID: "notes"))
    }

    @Test func aViewKeepingItsOwnShortcutIsFine() {
        #expect(conflict(clip, for: .view(pluginID: "clipboard")) == nil)
        #expect(conflict(Shortcut(keyCode: 0, modifiers: Shortcut.control), for: .view(pluginID: "clipboard")) == nil)
    }
}
