import Foundation
import SwiftCastPluginKit

/// Clipboard history: keeps the text and images the user copies. Typing "clip" offers a row
/// that opens the history, where ↩ copies an entry again.
///
/// Keeps the history in its own database, `clipboard.db`, with images as PNG files beside it.
@MainActor
public final class ClipboardPlugin: LauncherPlugin {
    public let id = "clipboard"
    public let name = "Clipboard History"
    public let summary = "Keeps the text and images you copy; type “clip” to browse and copy them again."
    public let icon = ResultIcon.symbol("doc.on.clipboard")
    public let sectionTitle = "Clipboard"
    public let viewTitle: String? = "Clipboard History"
    public let resultLimit = 1

    /// Longest row title; the preview shows the rest.
    static let titleLength = 120

    /// Schema of `clipboard.db`; only ever append.
    static let migrations = [
        """
        CREATE TABLE entries (
            id INTEGER PRIMARY KEY, kind TEXT NOT NULL, text TEXT, image_file TEXT,
            width INTEGER, height INTEGER, hash TEXT NOT NULL UNIQUE, copied_at REAL NOT NULL);
        CREATE TABLE settings (key TEXT PRIMARY KEY, value INTEGER NOT NULL);
        """,
    ]

    let store: ClipboardStore
    private let monitor = ClipboardMonitor()
    private var context: PluginContext?
    private let relativeTime = RelativeDateTimeFormatter()

    public convenience init() {
        let url = Database.url(named: "clipboard")
        self.init(
            database: .open("clipboard", migrations: Self.migrations),
            imageDirectory: url.deletingLastPathComponent().appending(path: "clipboard"))
    }

    init(database: Database, imageDirectory: URL) {
        store = ClipboardStore(database: database, imageDirectory: imageDirectory)
        monitor.onCopy = { [weak self] content in self?.record(content) }
    }

    public func activate(_ context: PluginContext) async {
        self.context = context
        monitor.start()
    }

    public func deactivate() {
        monitor.stop()
    }

    // MARK: - Results

    /// The row that opens the history, for a query that starts "clipboard history" or
    /// "history".
    public func results(for query: String) -> [ResultItem] {
        let query = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return [] }
        let title = "Clipboard History"
        let matched: Range<Int>
        let match: MatchQuality
        if title.lowercased().hasPrefix(query) {
            matched = 0..<query.count
            match = query.count == title.count ? .exact : .prefix
        } else if "history".hasPrefix(query) {
            matched = 10..<(10 + query.count)
            match = .wordPrefix
        } else {
            return []
        }
        return [ResultItem(
            id: "history",
            title: title,
            highlightedIndices: Array(matched),
            detail: itemCount,
            icon: icon,
            actions: [ResultAction("Open", .openView)],
            match: match
        )]
    }

    /// Entries newest first; text ones whose text contains `query`, and images for an empty
    /// query or one "image" starts with.
    public func viewResults(for query: String) -> [ResultItem] {
        let query = query.trimmingCharacters(in: .whitespaces)
        let now = Date()
        return store.entries.compactMap { entry in
            switch entry.content {
            case .text(let text):
                guard query.isEmpty || text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                else { return nil }
            case .image:
                guard query.isEmpty || "image".hasPrefix(query.lowercased()) else { return nil }
            }
            return item(for: entry, now: now)
        }
    }

    func item(for entry: ClipboardStore.Entry, now: Date) -> ResultItem {
        let age = relativeTime.localizedString(for: entry.copiedAt, relativeTo: now)
        switch entry.content {
        case .text(let text):
            let count = text.count
            return ResultItem(
                id: String(entry.id),
                title: Self.title(for: text),
                icon: .symbol("doc.text"),
                actions: [ResultAction("Copy", .copy(text))],
                preview: .text(text),
                previewDetail: "\(count) character\(count == 1 ? "" : "s") · Copied \(age)")
        case .image(let file, let width, let height):
            let url = store.imageURL(file)
            return ResultItem(
                id: String(entry.id),
                title: "Image \(width)×\(height)",
                icon: .symbol("photo"),
                actions: [ResultAction("Copy", .copyImage(url))],
                preview: .image(url),
                previewDetail: "\(width)×\(height) · Copied \(age)")
        }
    }

    /// The first line with text, trimmed and cut to `titleLength`.
    static func title(for text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline)
            .lazy.map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        return line.count > titleLength ? String(line.prefix(titleLength)) + "…" : line
    }

    private var itemCount: String {
        let count = store.entries.count
        return "\(count) item\(count == 1 ? "" : "s")"
    }

    // MARK: - Recording

    private func record(_ content: ClipboardMonitor.Content) {
        switch content {
        case .text(let text):
            add(.text(text))
        case .image(let data, let type):
            Task {
                let png = await Task.detached(priority: .utility) {
                    ClipboardMonitor.png(from: data, type: type)
                }.value
                if let png { add(.image(png)) }
            }
        }
    }

    func add(_ clip: Clip) {
        store.add(clip)
        context?.resultsDidChange()
    }

    // MARK: - Settings

    public func settingsSections() -> [SettingsSection] {
        [
            SettingsSection("History", rows: [
                SettingsRow(
                    id: "maxItems",
                    title: "Keep up to",
                    detail: "Items beyond this are deleted, oldest first.",
                    control: .number(store.maxItems, range: ClipboardStore.maxItemsRange)),
                SettingsRow(
                    id: "clearHistory",
                    title: "Clipboard history",
                    detail: itemCount,
                    control: .button("Clear…", enabled: !store.entries.isEmpty, confirmation: SettingsConfirmation(
                        title: "Clear clipboard history?",
                        message: "Every copied text and image kept so far is deleted.",
                        action: "Clear",
                        destructive: true))),
            ]),
        ]
    }

    public func setSetting(_ id: String, to value: SettingsValue) {
        guard id == "maxItems", case .int(let count) = value else { return }
        let range = ClipboardStore.maxItemsRange
        store.maxItems = min(max(count, range.lowerBound), range.upperBound)
        context?.resultsDidChange()
    }

    public func performSettingsAction(_ id: String) {
        guard id == "clearHistory" else { return }
        store.clear()
        context?.resultsDidChange()
    }
}
