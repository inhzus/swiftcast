import Foundation
import SwiftCastPluginKit

/// App search: finds installed apps by fuzzy name, ranked by how often and how recently
/// they were opened. ↩ opens the app, ⌘↩ shows it in Finder.
///
/// Keeps launch history and extra search folders in its own database, `apps.db`.
@MainActor
public final class AppsPlugin: LauncherPlugin {
    public let id = "apps"
    public let name = "Applications"
    public let summary = "Finds and opens installed apps, ranking the ones you use most first."
    public let icon = ResultIcon.symbol("square.grid.2x2")
    public let sectionTitle = "Applications"
    public let emptyQueryTitle: String? = "Recent"
    public let resultLimit = 20

    /// Rescans on panel open only when the last scan is older than this.
    static let rescanInterval: TimeInterval = 60

    let engine: SearchEngine
    let settings: AppsSettings
    private var context: PluginContext?
    private var isIndexing = false
    /// Set when the search folders change mid-scan, so another scan follows.
    private var needsReindex = false
    private var lastIndexed: Date?

    /// Schema of `apps.db`; only ever append.
    static let migrations = [
        """
        CREATE TABLE search_folders (path TEXT PRIMARY KEY, position INTEGER NOT NULL);
        CREATE TABLE launches (app_id TEXT PRIMARY KEY, count INTEGER NOT NULL, last_used REAL NOT NULL);
        """,
    ]

    public convenience init() {
        self.init(database: .open("apps", migrations: Self.migrations))
    }

    init(database: Database) {
        engine = SearchEngine(usage: UsageStore(database: database))
        settings = AppsSettings(database: database)
        settings.onFoldersChange = { [weak self] in
            self?.lastIndexed = nil
            Task { await self?.reindex() }
        }
    }

    public func activate(_ context: PluginContext) async {
        self.context = context
        await reindex()
    }

    public func results(for query: String) -> [ResultItem] {
        engine.results(for: query, limit: resultLimit).map { result in
            Self.item(for: result, detail: engine.detail(for: result.app))
        }
    }

    public func panelDidShow() {
        Task { await reindex() }
    }

    public func didPerform(_ action: ResultAction, on item: ResultItem) {
        if case .openApplication = action.effect {
            engine.usage.increment(item.id)
        }
    }

    /// Forgets which apps were opened, so recent apps and the ranking boost start over.
    func clearLaunchHistory() {
        engine.usage.clear()
        context?.resultsDidChange()
    }

    public func iconPaths() -> [String] {
        engine.apps.map(\.url.path)
    }

    // MARK: - Settings

    public func settingsSections() -> [SettingsSection] {
        [
            SettingsSection("Search Folders", footer: "Apps are found up to three folders deep.", rows: [
                SettingsRow(id: "searchFolders", title: "Search folders", control: .folders(
                    fixed: AppIndexer.defaultRoots,
                    editable: settings.extraFolders,
                    addPrompt: "Choose folders to search for apps")),
            ]),
            SettingsSection("Usage", rows: [
                SettingsRow(
                    id: "clearLaunchHistory",
                    title: "Launch history",
                    detail: "Ranks the apps you open most and lists recent ones.",
                    control: .button("Clear…", enabled: !engine.usage.isEmpty, confirmation: SettingsConfirmation(
                        title: "Clear launch history?",
                        message: "Recent apps and the ranking boost for frequently used apps start over.",
                        action: "Clear",
                        destructive: true))),
            ]),
        ]
    }

    public func setSetting(_ id: String, to value: SettingsValue) {
        guard id == "searchFolders", case .folders(let folders) = value else { return }
        // Skip the default roots and repeats, however the paths are spelled.
        var known = Set(AppIndexer.defaultRoots.map(\.standardizedFileURL))
        settings.extraFolders = folders.filter { known.insert($0.standardizedFileURL).inserted }
    }

    public func performSettingsAction(_ id: String) {
        if id == "clearLaunchHistory" { clearLaunchHistory() }
    }

    static func item(for result: SearchResult, detail: String?) -> ResultItem {
        let app = result.app
        return ResultItem(
            id: app.id,
            title: app.name,
            highlightedIndices: result.matchedIndices,
            detail: detail,
            icon: .file(app.url.path),
            actions: [
                ResultAction("Open", .openApplication(app.url)),
                ResultAction("Show in Finder", .revealInFinder(app.url)),
            ]
        )
    }

    private func reindex() async {
        guard !isIndexing else {
            needsReindex = true
            return
        }
        if let lastIndexed, Date().timeIntervalSince(lastIndexed) < Self.rescanInterval { return }
        isIndexing = true
        needsReindex = false
        let indexer = AppIndexer(roots: AppIndexer.defaultRoots + settings.extraFolders)
        let apps = await Task.detached(priority: .utility) { indexer.scan() }.value
        if apps != engine.apps {
            engine.update(apps: apps)
            context?.resultsDidChange()
        }
        lastIndexed = Date()
        isIndexing = false
        if needsReindex {
            lastIndexed = nil
            await reindex()
        }
    }
}
