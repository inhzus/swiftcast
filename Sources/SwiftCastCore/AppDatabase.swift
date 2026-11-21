import SwiftCastPluginKit

/// The app's own database, `swiftcast.db`, which `QueryHistory` and `UsageStore` share.
public enum AppDatabase {
    /// Schema; only ever append.
    public static let migrations = [
        "CREATE TABLE query_history (query TEXT PRIMARY KEY, last_used REAL NOT NULL)",
        """
        CREATE TABLE usage (
            plugin_id TEXT NOT NULL, item_id TEXT NOT NULL, count INTEGER NOT NULL,
            last_used REAL NOT NULL, PRIMARY KEY (plugin_id, item_id));
        """,
    ]
}
