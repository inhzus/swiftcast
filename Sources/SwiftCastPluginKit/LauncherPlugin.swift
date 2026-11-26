import Foundation

/// A feature of the launcher, such as app search or quick math.
///
/// This is the whole contract between the app and a feature. A plugin is a module that
/// depends only on this one; the app lists plugins in `PluginRegistry` and knows nothing else
/// about them. Plugins describe their rows and what ↩/⌘↩ do as values (`ResultItem`,
/// `Effect`); the app draws the rows and carries out the effects.
///
/// The user can turn a plugin off in Settings. A disabled plugin isn't asked for results and
/// isn't told about the panel; one that starts disabled is activated when first enabled.
@MainActor
public protocol LauncherPlugin: AnyObject {
    /// Stable and unique among plugins, e.g. "apps".
    var id: String { get }
    /// Shown in Settings, e.g. "Applications".
    var name: String { get }
    /// One line saying what the plugin does, shown in Settings.
    var summary: String { get }
    /// Shown next to `name` in Settings.
    var icon: ResultIcon { get }
    /// Heading above the selected row, e.g. "Applications".
    var sectionTitle: String { get }
    /// Most rows `results(for:)` returns; the app sizes its row pool from these.
    var resultLimit: Int { get }
    /// Heading and search placeholder of the plugin's own view (see `Effect.openView`), e.g.
    /// "Clipboard History". `nil` when it has no view.
    var viewTitle: String? { get }
    /// Global shortcut that opens the plugin's view, until the user changes it in Settings.
    /// `nil` for none.
    var defaultViewShortcut: Shortcut? { get }
    /// Whether the app counts each row's daily use, with its title and icon, for the
    /// Statistics page; every plugin's total use is counted either way. Leave it off when
    /// rows hold what the user typed or copied, since their titles would be stored.
    var tracksItemStatistics: Bool { get }

    /// Called once, at launch or when the plugin is first enabled. Loads whatever the plugin
    /// needs (an index, say); at launch the app prewarms the panel after every enabled plugin
    /// has activated.
    func activate(_ context: PluginContext) async
    /// Rows for `query`, best first, at most `resultLimit`. Runs on every keystroke, on the
    /// main actor, so it must be fast. The app ranks every plugin's rows together: by `match`,
    /// then by how much the user picks each row, then registry order and the plugin's own.
    func results(for query: String) -> [ResultItem]
    /// Rows of the plugin's own view for `query`, best first, drawn as a list with the selected
    /// row's `preview` beside it. Like `results(for:)`, runs on every keystroke.
    func viewResults(for query: String) -> [ResultItem]
    /// Called when the user turns the plugin off; it should stop any background work. It's
    /// activated again if turned back on.
    func deactivate()
    /// Called just after the panel appears.
    func panelDidShow()
    /// Called after the app carried out `action` of `item`, one of this plugin's rows.
    func didPerform(_ action: ResultAction, on item: ResultItem)
    /// File paths of icons the plugin's rows show, rendered ahead of time.
    func iconPaths() -> [String]
    /// The plugin's page in Settings, below the switch that turns it on and off, which the
    /// app draws (see `SettingsSection`). Empty when it has no settings.
    func settingsSections() -> [SettingsSection]
    /// The user changed the row `id` to `value`. The app then asks for the sections again.
    func setSetting(_ id: String, to value: SettingsValue)
    /// The user pressed the button row `id`. The app then asks for the sections again.
    func performSettingsAction(_ id: String)
}

public extension LauncherPlugin {
    var viewTitle: String? { nil }
    var defaultViewShortcut: Shortcut? { nil }
    var tracksItemStatistics: Bool { false }
    func activate(_ context: PluginContext) async {}
    func viewResults(for query: String) -> [ResultItem] { [] }
    func deactivate() {}
    func panelDidShow() {}
    func didPerform(_ action: ResultAction, on item: ResultItem) {}
    func iconPaths() -> [String] { [] }
    func settingsSections() -> [SettingsSection] { [] }
    func setSetting(_ id: String, to value: SettingsValue) {}
    func performSettingsAction(_ id: String) {}
}

/// What the app offers a plugin.
@MainActor
public struct PluginContext {
    /// Tells the app the plugin's results changed without the query changing (an index was
    /// rebuilt, say), so it searches again.
    public let resultsDidChange: () -> Void
    /// Up to 60 points for a row the user picks often and lately, by the row's `id`; zero for
    /// one never picked. For a plugin that ranks many rows itself, so the rows it keeps
    /// within `resultLimit` include the ones the user reaches for.
    public let usageBoost: (String) -> Int
    /// Hands the app usage the plugin recorded itself before the app kept it.
    public let importUsage: ([UsageRecord]) -> Void

    public init(resultsDidChange: @escaping () -> Void = {},
                usageBoost: @escaping (String) -> Int = { _ in 0 },
                importUsage: @escaping ([UsageRecord]) -> Void = { _ in }) {
        self.resultsDidChange = resultsDidChange
        self.usageBoost = usageBoost
        self.importUsage = importUsage
    }
}

/// How often and how recently the user picked one of a plugin's rows.
public struct UsageRecord: Equatable, Sendable {
    public var id: String
    public var count: Int
    public var lastUsed: Date

    public init(id: String, count: Int, lastUsed: Date) {
        self.id = id
        self.count = count
        self.lastUsed = lastUsed
    }
}

/// How well a row matched the query, compared across plugins. Strongest last.
public enum MatchQuality: Int, Comparable, Sendable {
    /// The query's letters appear in order, with gaps.
    case fuzzy
    case substring
    /// A word inside the title starts with the query.
    case wordPrefix
    /// The query spells the title's word initials.
    case initials
    case prefix
    case exact

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One row in the launcher.
public struct ResultItem: Hashable, Sendable {
    /// Unique among the plugin's rows, and stable across queries so a selection can survive
    /// a refresh.
    public var id: String
    public var title: String
    /// Character offsets into `title` drawn in bold, such as the letters a query matched.
    public var highlightedIndices: [Int]
    /// Grey text after the title.
    public var detail: String?
    /// Grey text on a second line below the title.
    public var subtitle: String?
    public var icon: ResultIcon
    /// The first runs on ↩ and the second on ⌘↩; the key hints show their titles.
    public var actions: [ResultAction]
    /// How well the row matched; the app ranks rows from every plugin by it. Unused in a
    /// plugin's view.
    public var match: MatchQuality
    /// Shown beside the list while the row is selected in a plugin's view.
    public var preview: ResultPreview?
    /// Grey text below the preview, e.g. "142 characters · 3 min ago".
    public var previewDetail: String?

    public init(id: String, title: String, highlightedIndices: [Int] = [], detail: String? = nil,
                subtitle: String? = nil, icon: ResultIcon, actions: [ResultAction], match: MatchQuality = .prefix,
                preview: ResultPreview? = nil, previewDetail: String? = nil) {
        self.id = id
        self.title = title
        self.highlightedIndices = highlightedIndices
        self.detail = detail
        self.subtitle = subtitle
        self.icon = icon
        self.actions = actions
        self.match = match
        self.preview = preview
        self.previewDetail = previewDetail
    }
}

public enum ResultPreview: Hashable, Sendable {
    case text(String)
    /// The image file at this URL.
    case image(URL)
}

public enum ResultIcon: Hashable, Sendable {
    /// The Finder icon of the file at this path.
    case file(String)
    /// An SF Symbol.
    case symbol(String)
}

public struct ResultAction: Hashable, Sendable {
    /// Shown in the key hints, e.g. "Open".
    public var title: String
    public var effect: Effect

    public init(_ title: String, _ effect: Effect) {
        self.title = title
        self.effect = effect
    }
}

/// Something the app does when an action runs. The panel closes first, except for `openView`.
public enum Effect: Hashable, Sendable {
    case openApplication(URL)
    /// Opens a file or URL in its default app.
    case open(URL)
    case revealInFinder(URL)
    case copy(String)
    /// Copies the PNG image file at this URL.
    case copyImage(URL)
    /// Copies `text`, then pastes it into the app in front (⌘V). Needs Accessibility access;
    /// without it, only copies.
    case paste(String)
    /// Copies the PNG image file at this URL, then pastes it like `paste`.
    case pasteImage(URL)
    /// Shows the plugin's own view (`viewResults(for:)`) in the panel, with an empty search.
    /// Esc goes back.
    case openView
}
