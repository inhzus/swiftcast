import Foundation
import SwiftCastCore
import SwiftCastPluginKit

/// A row in the launcher, with the plugin it came from.
struct LauncherItem: Hashable {
    let pluginID: String
    let result: ResultItem
}

@MainActor
final class LauncherViewModel {
    /// Every plugin, enabled or not.
    let plugins: [any LauncherPlugin]
    /// Plugins asked for results; the rest are turned off in Settings.
    var enabledIDs: Set<String>
    /// Most rows shown: every plugin's limit added up, so turning plugins on never needs
    /// more rows.
    let itemLimit: Int

    var query = "" {
        didSet {
            items = PerfLog.measure("search") { makeItems() }
            selection = 0
            PerfLog.measure("view") { onResultsChange() }
        }
    }
    var selection = 0 {
        didSet {
            if selection != oldValue { onSelectionChange() }
        }
    }
    private(set) var items: [LauncherItem] = []

    var onResultsChange: () -> Void = {}
    var onSelectionChange: () -> Void = {}
    var onDismiss: () -> Void = {}
    private let pluginsByID: [String: any LauncherPlugin]
    private let history: QueryHistory
    private var historyCursor = HistoryCursor()

    init(plugins: [any LauncherPlugin], history: QueryHistory) {
        self.plugins = plugins
        enabledIDs = Set(plugins.map(\.id))
        self.history = history
        itemLimit = plugins.map(\.resultLimit).reduce(0, +)
        pluginsByID = Dictionary(uniqueKeysWithValues: plugins.map { ($0.id, $0) })
    }

    /// The user typed: any history browsing ends, so ↑/↓ move through results again.
    func userEdited(_ text: String) {
        historyCursor.reset()
        query = text
    }

    /// Clears the search and stops browsing history.
    func reset() {
        historyCursor.reset()
        query = ""
    }

    /// Re-runs the current search for a restored panel, keeping the selected row.
    func restore() {
        historyCursor.reset()
        refresh()
    }

    /// ↑: in an empty field, or while browsing, steps to an older search and returns its text
    /// for the field; otherwise moves the selection up and returns `nil`.
    func moveUp() -> String? {
        if let text = stepHistory(1) { return text }
        moveSelection(by: -1)
        return nil
    }

    /// ↓: while browsing, steps to a newer search (or back to an empty field) and returns its
    /// text; otherwise moves the selection down and returns `nil`.
    func moveDown() -> String? {
        if let text = stepHistory(-1) { return text }
        moveSelection(by: 1)
        return nil
    }

    private func stepHistory(_ delta: Int) -> String? {
        guard query.isEmpty || historyCursor.isBrowsing,
              let text = historyCursor.move(delta, through: history.entries) else { return nil }
        query = text
        return text
    }

    var selectedItem: LauncherItem? {
        items.indices.contains(selection) ? items[selection] : nil
    }

    /// Recomputes results for the same query after the index changes, keeping the selected
    /// row selected when it's still in the list.
    func refresh() {
        let selected = selectedItem
        items = makeItems()
        selection = items.firstIndex { $0 == selected } ?? 0
        onResultsChange()
    }

    func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        selection = min(max(selection + delta, 0), items.count - 1)
    }

    /// The plugin that `item` came from.
    func plugin(for item: LauncherItem) -> (any LauncherPlugin)? {
        pluginsByID[item.pluginID]
    }

    /// ↩: runs the selected row's first action.
    func performPrimary() {
        perform(actionAt: 0)
    }

    /// ⌘↩: runs the selected row's second action, if it has one.
    func performSecondary() {
        perform(actionAt: 1)
    }

    private func perform(actionAt index: Int) {
        guard let item = selectedItem, item.result.actions.indices.contains(index) else { return }
        let action = item.result.actions[index]
        history.record(query)
        // Hide first so the panel disappears without waiting on the effect.
        onDismiss()
        EffectRunner.run(action.effect)
        plugin(for: item)?.didPerform(action, on: item.result)
    }

    private func makeItems() -> [LauncherItem] {
        plugins.filter { enabledIDs.contains($0.id) }.flatMap { plugin in
            plugin.results(for: query).prefix(plugin.resultLimit).map {
                LauncherItem(pluginID: plugin.id, result: $0)
            }
        }
    }
}
