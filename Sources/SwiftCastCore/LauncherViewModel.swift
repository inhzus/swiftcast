import Foundation
import SwiftCastPluginKit

/// A row in the launcher, with the plugin it came from.
public struct LauncherItem: Hashable, Sendable {
    public let pluginID: String
    public let result: ResultItem

    public init(pluginID: String, result: ResultItem) {
        self.pluginID = pluginID
        self.result = result
    }
}

/// Carries out the effects plugins ask for (see `Effect`); the app supplies it.
@MainActor
public protocol EffectPerforming {
    func perform(_ effect: Effect)
}

@MainActor
public final class LauncherViewModel {
    /// The plugins; only enabled ones are asked for results.
    public let host: PluginHost
    /// Most rows shown: every plugin's limit added up, so turning plugins on never needs
    /// more rows.
    public let itemLimit: Int

    public var query = "" {
        didSet {
            measure("search") { items = makeItems() }
            selection = 0
            measure("view") { onResultsChange() }
        }
    }
    public var selection = 0 {
        didSet {
            if selection != oldValue { onSelectionChange() }
        }
    }
    public private(set) var items: [LauncherItem] = []
    /// The plugin whose own view is showing (see `Effect.openView`), if any. Searches go
    /// only to it while it's open.
    public private(set) var openView: (any LauncherPlugin)?

    /// The shortcuts that open plugins' views, as shown, by plugin ID.
    public var viewShortcuts: [String: String] = [:]

    public var onResultsChange: () -> Void = {}
    public var onSelectionChange: () -> Void = {}
    public var onDismiss: () -> Void = {}
    /// Times a named phase of a search, for the app's latency log.
    public var measure: (String, () -> Void) -> Void = { $1() }

    private let history: QueryHistory
    private let usage: UsageStore
    private let effects: any EffectPerforming
    private var historyCursor = HistoryCursor()

    public init(host: PluginHost, history: QueryHistory, usage: UsageStore, effects: any EffectPerforming) {
        self.host = host
        self.history = history
        self.usage = usage
        self.effects = effects
        itemLimit = host.plugins.map(\.resultLimit).reduce(0, +)
    }

    /// The user typed: any history browsing ends, so ↑/↓ move through results again.
    public func userEdited(_ text: String) {
        historyCursor.reset()
        query = text
    }

    /// Clears the search, closes any plugin view and stops browsing history.
    public func reset() {
        historyCursor.reset()
        openView = nil
        query = ""
    }

    /// Shows `plugin`'s own view, with an empty search.
    public func open(_ plugin: any LauncherPlugin) {
        historyCursor.reset()
        openView = plugin
        query = ""
    }

    /// Goes back from a plugin's view to the search, empty.
    public func closeView() {
        guard openView != nil else { return }
        openView = nil
        historyCursor.reset()
        query = ""
    }

    /// Re-runs the current search for a restored panel, keeping the selected row.
    public func restore() {
        historyCursor.reset()
        refresh()
    }

    /// ↑: in an empty field, or while browsing, steps to an older search and returns its text
    /// for the field; otherwise moves the selection up and returns `nil`.
    public func moveUp() -> String? {
        if let text = stepHistory(1) { return text }
        moveSelection(by: -1)
        return nil
    }

    /// ↓: while browsing, steps to a newer search (or back to an empty field) and returns its
    /// text; otherwise moves the selection down and returns `nil`.
    public func moveDown() -> String? {
        if let text = stepHistory(-1) { return text }
        moveSelection(by: 1)
        return nil
    }

    private func stepHistory(_ delta: Int) -> String? {
        guard openView == nil, query.isEmpty || historyCursor.isBrowsing,
              let text = historyCursor.move(delta, through: history.entries) else { return nil }
        query = text
        return text
    }

    public var selectedItem: LauncherItem? {
        items.indices.contains(selection) ? items[selection] : nil
    }

    /// Recomputes results for the same query after the index changes, keeping the selected
    /// row selected when it's still in the list.
    public func refresh() {
        let selected = selectedItem
        items = makeItems()
        selection = items.firstIndex {
            $0.pluginID == selected?.pluginID && $0.result.id == selected?.result.id
        } ?? 0
        onResultsChange()
    }

    public func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        selection = min(max(selection + delta, 0), items.count - 1)
    }

    /// The global shortcut that does what ↩ does on `item`, as shown: its plugin's view
    /// shortcut, on the row that opens the view.
    public func shortcut(for item: LauncherItem) -> String? {
        guard openView == nil, item.result.actions.first?.effect == .openView else { return nil }
        return viewShortcuts[item.pluginID]
    }

    /// The plugin that `item` came from.
    public func plugin(for item: LauncherItem) -> (any LauncherPlugin)? {
        host.plugin(id: item.pluginID)
    }

    /// ↩: runs the selected row's first action.
    public func performPrimary() {
        perform(actionAt: 0)
    }

    /// ⌘↩: runs the selected row's second action, if it has one.
    public func performSecondary() {
        perform(actionAt: 1)
    }

    private func perform(actionAt index: Int) {
        guard let item = selectedItem, item.result.actions.indices.contains(index) else { return }
        let action = item.result.actions[index]
        // Taken before anything changes the query or the open view.
        let inSearch = openView == nil
        let query = query
        if action.effect == .openView, let plugin = plugin(for: item) {
            open(plugin)
        } else {
            // Hide first so the panel disappears without waiting on the effect or on saving.
            onDismiss()
            effects.perform(action.effect)
            self.plugin(for: item)?.didPerform(action, on: item.result)
        }
        guard inSearch else { return }
        usage.increment(UsageStore.Key(pluginID: item.pluginID, itemID: item.result.id))
        history.record(query)
    }

    private func makeItems() -> [LauncherItem] {
        if let openView {
            return openView.viewResults(for: query).map { LauncherItem(pluginID: openView.id, result: $0) }
        }
        let items = host.enabledPlugins.flatMap { plugin in
            plugin.results(for: query).prefix(plugin.resultLimit).map {
                LauncherItem(pluginID: plugin.id, result: $0)
            }
        }
        // With no query there's nothing to rank.
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return items }
        let now = Date()
        return ResultRanker.rank(items, match: \.result.match) {
            usage.boost(for: UsageStore.Key(pluginID: $0.pluginID, itemID: $0.result.id), at: now)
        }
    }
}
