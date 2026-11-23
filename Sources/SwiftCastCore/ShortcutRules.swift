import SwiftCastPluginKit

/// What a global shortcut is for.
public enum ShortcutTarget: Equatable, Sendable {
    /// Toggling the launcher.
    case launcher
    /// Opening a plugin's view.
    case view(pluginID: String)
}

/// Which rules say whether a shortcut can be given to a target: each global shortcut does
/// one thing.
public enum ShortcutRules {
    /// What already uses `shortcut`, other than `target` itself, or `nil` when it's free.
    /// - Parameters:
    ///   - launcher: The shortcut that toggles the launcher.
    ///   - views: The shortcut that opens each plugin's view, by plugin ID.
    public static func conflict(
        of shortcut: Shortcut, for target: ShortcutTarget, launcher: Shortcut, views: [String: Shortcut]
    ) -> ShortcutTarget? {
        if target != .launcher, shortcut == launcher { return .launcher }
        // Sorted, so the answer doesn't depend on dictionary order.
        for (pluginID, viewShortcut) in views.sorted(by: { $0.key < $1.key })
        where viewShortcut == shortcut && target != .view(pluginID: pluginID) {
            return .view(pluginID: pluginID)
        }
        return nil
    }
}
