import Foundation
import SwiftCastPluginKit

/// The plugins, which of them are on, and their lifecycle: what each is offered
/// (`PluginContext`) and when it's activated and deactivated.
///
/// A plugin that starts disabled is activated when first enabled, and one turned off is
/// deactivated and activated again when turned back on.
@MainActor
public final class PluginHost {
    /// Every plugin, enabled or not, in registry order.
    public let plugins: [any LauncherPlugin]
    /// Called when a plugin says its results changed without the query changing.
    public var onResultsChange: () -> Void = {}
    /// The enabled plugins have been activated once, at launch.
    public private(set) var hasStarted = false

    private let usage: UsageStore
    private let pluginsByID: [String: any LauncherPlugin]
    private var disabledIDs: Set<String>
    private var activatedIDs: Set<String> = []

    public init(plugins: [any LauncherPlugin], disabledIDs: Set<String> = [], usage: UsageStore) {
        self.plugins = plugins
        self.disabledIDs = disabledIDs
        self.usage = usage
        pluginsByID = Dictionary(uniqueKeysWithValues: plugins.map { ($0.id, $0) })
    }

    public var enabledPlugins: [any LauncherPlugin] {
        plugins.filter { !disabledIDs.contains($0.id) }
    }

    public func isEnabled(_ plugin: any LauncherPlugin) -> Bool {
        !disabledIDs.contains(plugin.id)
    }

    public func plugin(id: String) -> (any LauncherPlugin)? {
        pluginsByID[id]
    }

    /// Activates the enabled plugins at launch.
    public func start() async {
        await activateEnabled()
        hasStarted = true
    }

    /// Activates the enabled plugins that aren't active yet.
    public func activateEnabled() async {
        for plugin in enabledPlugins where activatedIDs.insert(plugin.id).inserted {
            await plugin.activate(context(for: plugin))
        }
    }

    /// Turns plugins on and off. Ones turned off are deactivated now; ones turned on are
    /// activated by the next `activateEnabled()`.
    public func setDisabled(_ ids: Set<String>) {
        disabledIDs = ids
        for plugin in plugins where ids.contains(plugin.id) && activatedIDs.contains(plugin.id) {
            plugin.deactivate()
            activatedIDs.remove(plugin.id)
        }
    }

    /// What `plugin` is offered: its rows' usage, by their IDs.
    private func context(for plugin: any LauncherPlugin) -> PluginContext {
        let pluginID = plugin.id
        return PluginContext(
            resultsDidChange: { [weak self] in self?.onResultsChange() },
            usageBoost: { [usage] in usage.boost(for: UsageStore.Key(pluginID: pluginID, itemID: $0)) },
            importUsage: { [usage] in usage.import($0, for: pluginID) })
    }
}
