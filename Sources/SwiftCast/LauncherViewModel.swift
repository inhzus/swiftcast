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

    init(engine: SearchEngine) {
        self.engine = engine
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
