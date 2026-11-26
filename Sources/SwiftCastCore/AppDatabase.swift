import SwiftCastPluginKit

/// The app's own database, `swiftcast.db`, which `QueryHistory`, `UsageStore` and `UsageStats` share.
public enum AppDatabase {
    /// Schema; only ever append.
    public static let migrations = [
        "CREATE TABLE query_history (query TEXT PRIMARY KEY, last_used REAL NOT NULL)",
        """
        CREATE TABLE usage (
            plugin_id TEXT NOT NULL, item_id TEXT NOT NULL, count INTEGER NOT NULL,
            last_used REAL NOT NULL, PRIMARY KEY (plugin_id, item_id));
        """,
        // `UsageStats`.
        """
        CREATE TABLE daily_plugin_usage (
            day TEXT NOT NULL, plugin_id TEXT NOT NULL, count INTEGER NOT NULL,
            PRIMARY KEY (day, plugin_id));
        CREATE TABLE daily_item_usage (
            day TEXT NOT NULL, plugin_id TEXT NOT NULL, item_id TEXT NOT NULL,
            title TEXT NOT NULL, icon_path TEXT, count INTEGER NOT NULL,
            PRIMARY KEY (day, plugin_id, item_id));
        """,
    ]
}
