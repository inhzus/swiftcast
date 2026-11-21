import AppKit
import SwiftCastCore

/// A row in the launcher: a quick-math result or an app.
enum LauncherItem: Hashable {
    case calculation(Calculation)
    case app(SearchResult)
}

@MainActor
final class LauncherViewModel {
    /// Most apps shown for a query.
    static let resultLimit = 20
    /// Most rows shown: the apps, plus a calculation above them.
    static let itemLimit = resultLimit + 1

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
    private let engine: SearchEngine
    private let history: QueryHistory
    private var historyCursor = HistoryCursor()

    init(engine: SearchEngine, history: QueryHistory) {
        self.engine = engine
        self.history = history
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

    /// Opens the selected app, or copies the selected calculation's result.
    func launchSelected() {
        if selectedItem != nil { history.record(query) }
        switch selectedItem {
        case .calculation(let calculation):
            onDismiss()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(calculation.copyText, forType: .string)
        case .app(let result):
            // Hide first so the panel disappears without waiting on the launch.
            onDismiss()
            NSWorkspace.shared.openApplication(
                at: result.app.url,
                configuration: NSWorkspace.OpenConfiguration(),
                completionHandler: nil
            )
            engine.usage.increment(result.app.id)
        case nil:
            break
        }
    }

    func revealSelected() {
        guard case .app(let result) = selectedItem else { return }
        history.record(query)
        onDismiss()
        NSWorkspace.shared.activateFileViewerSelecting([result.app.url])
    }

    /// Text that tells `app` apart from other apps with the same name, if any.
    func detail(for app: AppEntry) -> String? {
        engine.detail(for: app)
    }

    private func makeItems() -> [LauncherItem] {
        let apps = engine.results(for: query, limit: Self.resultLimit).map(LauncherItem.app)
        guard let calculation = Calculator.evaluate(query) else { return apps }
        return [.calculation(calculation)] + apps
    }
}
