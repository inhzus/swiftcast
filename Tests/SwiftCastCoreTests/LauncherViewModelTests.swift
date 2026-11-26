import Foundation
import SwiftCastPluginKit
import Testing
@testable import SwiftCastCore

@MainActor
struct LauncherViewModelTests {
    let first = FakePlugin(id: "first", resultLimit: 2)
    let second = FakePlugin(id: "second", viewTitle: "Second View")
    let database = Database.inMemory(migrations: AppDatabase.migrations)
    let effects = RecordingEffects()
    let history: QueryHistory
    let usage: UsageStore
    let stats: UsageStats
    let host: PluginHost
    let model: LauncherViewModel

    init() {
        history = QueryHistory(database: database)
        usage = UsageStore(database: database)
        host = PluginHost(plugins: [first, second], usage: usage)
        stats = UsageStats(database: database)
        model = LauncherViewModel(host: host, history: history, usage: usage, stats: stats, effects: effects)
    }

    private var shownIDs: [String] { model.items.map(\.result.id) }

    @Test func capsEachPluginAndSkipsDisabledOnes() {
        first.results = [row("a"), row("b"), row("c")]
        second.results = [row("x")]
        model.query = "q"
        #expect(shownIDs == ["a", "b", "x"])

        host.setDisabled(["first"])
        model.refresh()
        #expect(shownIDs == ["x"])
    }

    @Test func ranksByMatchOnlyWithAQuery() {
        first.resultsByQuery = ["": [row("weak", match: .fuzzy)], "q": [row("weak", match: .fuzzy)]]
        second.resultsByQuery = ["": [row("strong", match: .exact)], "q": [row("strong", match: .exact)]]
        model.query = "q"
        #expect(shownIDs == ["strong", "weak"])
        model.query = ""
        #expect(shownIDs == ["weak", "strong"])
    }

    @Test func refreshKeepsTheSelectedRow() {
        first.results = [row("a"), row("b")]
        model.query = "q"
        model.moveSelection(by: 1)
        #expect(model.selectedItem?.result.id == "b")
        first.results = [row("b"), row("a")]
        model.refresh()
        #expect(model.selectedItem?.result.id == "b")
        #expect(model.selection == 0)
    }

    @Test func historyStepsOnlyFromAnEmptyFieldOrWhileBrowsing() {
        history.record("older")
        history.record("newer")
        first.results = [row("a"), row("b")]

        model.userEdited("typed")
        #expect(model.moveUp() == nil)  // moves the selection instead

        model.userEdited("")
        #expect(model.moveUp() == "newer")
        #expect(model.moveUp() == "older")
        #expect(model.moveDown() == "newer")
        #expect(model.moveDown() == "")
        #expect(model.moveDown() == nil)
    }

    @Test func performHidesThenRunsTheEffectThenTellsThePlugin() {
        var events: [String] = []
        model.onDismiss = { events.append("dismiss") }
        effects.onPerform = { events.append("effect \($0)") }
        first.results = [row("a")]
        model.userEdited("a")

        model.performSecondary()
        #expect(events == ["dismiss", "effect \(Effect.copy("aa"))"])
        #expect(first.log == ["didPerform Copy Twice a"])
        #expect(usage.count(for: UsageStore.Key(pluginID: "first", itemID: "a")) == 1)
        #expect(history.entries == ["a"])
    }

    @Test func openViewShowsTheViewAndRecordsHistoryWithoutAnEffect() {
        var dismissed = false
        model.onDismiss = { dismissed = true }
        second.results = [row("open", actions: [ResultAction("Open", .openView)])]
        second.viewRows = [row("entry")]
        model.userEdited("op")

        model.performPrimary()
        #expect(model.openView === second)
        #expect(model.query == "")
        #expect(shownIDs == ["entry"])
        #expect(!dismissed)
        #expect(effects.performed.isEmpty)
        #expect(history.entries == ["op"])
        #expect(usage.count(for: UsageStore.Key(pluginID: "second", itemID: "open")) == 1)
    }

    @Test func actionsInAViewRecordNoUsageOrHistory() {
        second.viewRows = [row("entry")]
        model.open(second)
        model.performPrimary()
        #expect(effects.performed == [.copy("entry")])
        #expect(second.log == ["didPerform Copy entry"])
        #expect(usage.isEmpty)
        #expect(history.entries.isEmpty)
    }

    @Test func actionsCountTowardStatisticsInSearchAndInViews() {
        first.results = [row("a")]
        second.viewRows = [row("entry")]
        model.userEdited("a")
        model.performPrimary()
        model.open(second)
        model.performSecondary()
        #expect(stats.topPlugins(in: .today).map(\.id) == ["first", "second"])
        // Neither fake keeps item statistics.
        #expect(stats.topItems(pluginID: "first", in: .all).isEmpty)
        #expect(stats.topItems(pluginID: "second", in: .all).isEmpty)
    }

    @Test func itemStatisticsOnlyForPluginsThatKeepThem() {
        first.tracksItemStatistics = true
        first.results = [ResultItem(id: "app", title: "App", icon: .file("/Applications/App.app"),
                                    actions: [ResultAction("Open", .copy("app"))], match: .prefix)]
        model.userEdited("a")
        model.performPrimary()
        #expect(stats.topItems(pluginID: "first", in: .today)
            == [UsageStats.ItemCount(id: "app", title: "App", iconPath: "/Applications/App.app", count: 1)])
    }

    @Test func openingAViewIsNotCounted() {
        second.results = [row("open", actions: [ResultAction("Open", .openView)])]
        model.userEdited("op")
        model.performPrimary()
        #expect(stats.topPlugins(in: .all).isEmpty)
    }

    @Test func viewShortcutLabelsOnlyTheRowThatOpensTheView() {
        model.viewShortcuts = ["second": "⌘C"]
        let opener = LauncherItem(pluginID: "second", result: row("open", actions: [ResultAction("Open", .openView)]))
        let other = LauncherItem(pluginID: "second", result: row("other"))
        #expect(model.shortcut(for: opener) == "⌘C")
        #expect(model.shortcut(for: other) == nil)
        model.open(second)
        #expect(model.shortcut(for: opener) == nil)
    }
}
