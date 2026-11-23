import Foundation
import SwiftCastPluginKit

/// App search preferences, persisted in the `Database`.
@MainActor
final class AppsSettings {
    private let database: Database

    /// Folders searched for apps on top of `AppIndexer.defaultRoots`.
    var extraFolders: [URL] {
        didSet {
            database.transaction {
                database.execute("DELETE FROM search_folders")
                for (position, folder) in extraFolders.enumerated() {
                    database.execute(
                        "INSERT OR IGNORE INTO search_folders (path, position) VALUES (?, ?)",
                        [.text(folder.path), .int(Int64(position))])
                }
            }
            onFoldersChange()
        }
    }

    var onFoldersChange: () -> Void = {}

    init(database: Database) {
        self.database = database
        extraFolders = database.rows("SELECT path FROM search_folders ORDER BY position")
            .compactMap { $0["path"].text.map { URL(filePath: $0) } }
    }
}
