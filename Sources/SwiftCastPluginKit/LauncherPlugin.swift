import Foundation
import SwiftUI

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
    /// Heading used instead of `sectionTitle` while the field is empty, e.g. "Recent".
    var emptyQueryTitle: String? { get }
    /// Most rows `results(for:)` returns; the app sizes its row pool from these.
    var resultLimit: Int { get }

    /// Called once, at launch or when the plugin is first enabled. Loads whatever the plugin
    /// needs (an index, say); at launch the app prewarms the panel after every enabled plugin
    /// has activated.
    func activate(_ context: PluginContext) async
    /// Rows for `query`, best first, at most `resultLimit`. Runs on every keystroke, on the
    /// main actor, so it must be fast. Plugins are asked in registry order and their rows
    /// shown in that order.
    func results(for query: String) -> [ResultItem]
    /// Called just after the panel appears.
    func panelDidShow()
    /// Called after the app carried out `action` of `item`, one of this plugin's rows.
    func didPerform(_ action: ResultAction, on item: ResultItem)
    /// File paths of icons the plugin's rows show, rendered ahead of time.
    func iconPaths() -> [String]
    /// The plugin's `Section`s for its page in Settings, shown below the switch that turns it
    /// on and off; `nil` when it has no settings.
    func settingsView() -> AnyView?
}

public extension LauncherPlugin {
    var emptyQueryTitle: String? { nil }
    func activate(_ context: PluginContext) async {}
    func panelDidShow() {}
    func didPerform(_ action: ResultAction, on item: ResultItem) {}
    func iconPaths() -> [String] { [] }
    func settingsView() -> AnyView? { nil }
}

/// What the app offers a plugin.
@MainActor
public struct PluginContext {
    /// Tells the app the plugin's results changed without the query changing (an index was
    /// rebuilt, say), so it searches again.
    public let resultsDidChange: () -> Void

    public init(resultsDidChange: @escaping () -> Void) {
        self.resultsDidChange = resultsDidChange
    }
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
    public var icon: ResultIcon
    /// The first runs on ↩ and the second on ⌘↩; the key hints show their titles.
    public var actions: [ResultAction]

    public init(id: String, title: String, highlightedIndices: [Int] = [], detail: String? = nil,
                icon: ResultIcon, actions: [ResultAction]) {
        self.id = id
        self.title = title
        self.highlightedIndices = highlightedIndices
        self.detail = detail
        self.icon = icon
        self.actions = actions
    }
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

/// Something the app does when an action runs. The panel closes first.
public enum Effect: Hashable, Sendable {
    case openApplication(URL)
    /// Opens a file or URL in its default app.
    case open(URL)
    case revealInFinder(URL)
    case copy(String)
}
