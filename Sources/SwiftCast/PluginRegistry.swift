import AppsPlugin
import CalculatorPlugin
import ClipboardPlugin
import SwiftCastPluginKit

/// The launcher's features, in the order their rows are shown. This is the only place the
/// app names a plugin; everything else goes through `LauncherPlugin`.
@MainActor
enum PluginRegistry {
    static func makePlugins() -> [any LauncherPlugin] {
        [
            CalculatorPlugin(),
            AppsPlugin(),
            ClipboardPlugin(),
        ]
    }
}
