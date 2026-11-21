import AppKit
import SwiftCastCore

@MainActor
final class LauncherViewModel {
    /// Most results shown for a query.
    static let resultLimit = 20

    var query = "" {
        didSet {
            results = PerfLog.measure("search") { engine.results(for: query, limit: Self.resultLimit) }
            selection = 0
            PerfLog.measure("view") { onResultsChange() }
        }
    }
    var selection = 0 {
        didSet {
            if selection != oldValue { onSelectionChange() }
        }
    }
    private(set) var results: [SearchResult] = []

    var onResultsChange: () -> Void = {}
    var onSelectionChange: () -> Void = {}
    var onDismiss: () -> Void = {}
    private let engine: SearchEngine

    init(engine: SearchEngine) {
        self.engine = engine
    }

    /// Recomputes results for the same query after the index changes, keeping the selected
    /// app selected when it's still in the list.
    func refresh() {
        let selectedID = results.indices.contains(selection) ? results[selection].id : nil
        results = engine.results(for: query, limit: Self.resultLimit)
        selection = results.firstIndex { $0.id == selectedID } ?? 0
        onResultsChange()
    }

    func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        selection = min(max(selection + delta, 0), results.count - 1)
    }

    func launchSelected() {
        guard let app = selectedApp else { return }
        // Hide first so the panel disappears without waiting on the launch.
        onDismiss()
        NSWorkspace.shared.openApplication(
            at: app.url,
            configuration: NSWorkspace.OpenConfiguration(),
            completionHandler: nil
        )
        engine.usage.increment(app.id)
    }

    func revealSelected() {
        guard let app = selectedApp else { return }
        onDismiss()
        NSWorkspace.shared.activateFileViewerSelecting([app.url])
    }

    /// Text that tells `app` apart from other apps with the same name, if any.
    func detail(for app: AppEntry) -> String? {
        engine.detail(for: app)
    }

    private var selectedApp: AppEntry? {
        results.indices.contains(selection) ? results[selection].app : nil
    }
}
