import CryptoKit
import Foundation
import ImageIO
import SwiftCastPluginKit

/// Something copied, ready to store.
enum Clip: Equatable, Sendable {
    case text(String)
    /// PNG data.
    case image(Data)
}

/// The clipboard history, newest first, persisted in the `Database` with images as PNG
/// files in `imageDirectory`. Holds every entry in memory, since the view searches them on
/// every keystroke.
@MainActor
final class ClipboardStore {
    struct Entry: Equatable {
        enum Content: Equatable, Sendable {
            case text(String)
            case image(file: String, width: Int, height: Int)
        }

        var id: Int64
        var content: Content
        var hash: String
        var copiedAt: Date
    }

    static let defaultMaxItems = 100
    static let maxItemsRange = 1...1000

    private let database: Database
    let imageDirectory: URL
    private(set) var entries: [Entry] = []
    /// IDs for entries the database failed to save, which stay in memory only.
    private var nextUnsavedID: Int64 = -1

    /// Most entries kept; older ones are deleted, now and as new ones arrive.
    var maxItems: Int {
        didSet {
            database.execute(
                "INSERT OR REPLACE INTO settings (key, value) VALUES ('max_items', ?)", [.int(Int64(maxItems))])
            prune()
        }
    }

    init(database: Database, imageDirectory: URL) {
        self.database = database
        self.imageDirectory = imageDirectory
        maxItems = database.rows("SELECT value FROM settings WHERE key = 'max_items'")
            .first?["value"].int.map(Int.init) ?? Self.defaultMaxItems
        entries = database.rows("""
            SELECT id, kind, text, image_file, width, height, hash, copied_at FROM entries
            ORDER BY copied_at DESC, id DESC
            """).compactMap(Self.entry)
    }

    func imageURL(_ file: String) -> URL {
        imageDirectory.appending(path: file)
    }

    /// A clip ready to add: hashed, and an image saved to its file and measured. Making one
    /// reads and writes whole images, so do it off the main actor (see `prepare`).
    struct Prepared: Equatable, Sendable {
        var hash: String
        var content: Entry.Content
    }

    /// Hashes `clip` and, for an image, saves it as `<hash>.png` in `imageDirectory` (unless
    /// it's there already) and reads its size. `nil` when the image can't be saved.
    nonisolated static func prepare(_ clip: Clip, imageDirectory: URL) -> Prepared? {
        let hash = hash(clip)
        switch clip {
        case .text(let text):
            return Prepared(hash: hash, content: .text(text))
        case .image(let png):
            let file = "\(hash).png"
            let url = imageDirectory.appending(path: file)
            do {
                if !FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
                    try png.write(to: url, options: .atomic)
                }
            } catch {
                NSLog("SwiftCast: can't save copied image (\(error))")
                return nil
            }
            let (width, height) = size(of: png)
            return Prepared(hash: hash, content: .image(file: file, width: width, height: height))
        }
    }

    /// Records `clip` as the newest entry, preparing it here; for text, which is cheap.
    func add(_ clip: Clip, at now: Date = Date()) {
        guard let prepared = Self.prepare(clip, imageDirectory: imageDirectory) else { return }
        add(prepared, at: now)
    }

    /// Records a prepared clip as the newest entry. One already in the history moves to the
    /// top instead of being added again.
    func add(_ prepared: Prepared, at now: Date = Date()) {
        let hash = prepared.hash
        if let index = entries.firstIndex(where: { $0.hash == hash }) {
            var entry = entries.remove(at: index)
            entry.copiedAt = now
            entries.insert(entry, at: 0)
            database.execute("UPDATE entries SET copied_at = ? WHERE id = ?",
                             [.double(now.timeIntervalSince1970), .int(entry.id)])
            return
        }

        let saved: Bool
        switch prepared.content {
        case .text(let text):
            saved = database.execute(
                "INSERT INTO entries (kind, text, hash, copied_at) VALUES ('text', ?, ?, ?)",
                [.text(text), .text(hash), .double(now.timeIntervalSince1970)])
        case .image(let file, let width, let height):
            // The history may have been cleared, deleting the file, while the image was prepared.
            guard FileManager.default.fileExists(atPath: imageURL(file).path) else { return }
            saved = database.execute("""
                INSERT INTO entries (kind, image_file, width, height, hash, copied_at)
                VALUES ('image', ?, ?, ?, ?, ?)
                """, [.text(file), .int(Int64(width)), .int(Int64(height)), .text(hash),
                      .double(now.timeIntervalSince1970)])
        }
        let id: Int64
        if saved {
            id = database.lastInsertRowID
        } else {
            id = nextUnsavedID
            nextUnsavedID -= 1
        }
        entries.insert(Entry(id: id, content: prepared.content, hash: hash, copiedAt: now), at: 0)
        prune()
    }

    /// Deletes every entry and its image.
    func clear() {
        remove(entries)
    }

    /// Deletes entries beyond `maxItems`, oldest first.
    private func prune() {
        guard entries.count > maxItems else { return }
        remove(Array(entries[maxItems...]))
    }

    private func remove(_ removed: [Entry]) {
        guard !removed.isEmpty else { return }
        let ids = Set(removed.map(\.id))
        entries.removeAll { ids.contains($0.id) }
        database.transaction {
            for entry in removed {
                database.execute("DELETE FROM entries WHERE id = ?", [.int(entry.id)])
            }
        }
        for case .image(let file, _, _) in removed.map(\.content) {
            try? FileManager.default.removeItem(at: imageURL(file))
        }
    }

    private static func entry(from row: Database.Row) -> Entry? {
        guard let id = row["id"].int, let kind = row["kind"].text, let hash = row["hash"].text,
              let copiedAt = row["copied_at"].double else { return nil }
        let content: Entry.Content
        switch kind {
        case "text":
            guard let text = row["text"].text else { return nil }
            content = .text(text)
        case "image":
            guard let file = row["image_file"].text else { return nil }
            content = .image(file: file, width: Int(row["width"].int ?? 0), height: Int(row["height"].int ?? 0))
        default:
            return nil
        }
        return Entry(id: id, content: content, hash: hash, copiedAt: Date(timeIntervalSince1970: copiedAt))
    }

    nonisolated private static func hash(_ clip: Clip) -> String {
        let digest = switch clip {
        case .text(let text): SHA256.hash(data: Data(("text:" + text).utf8))
        case .image(let png): SHA256.hash(data: png)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Pixel size of an image, read from its header.
    nonisolated private static func size(of data: Data) -> (Int, Int) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return (0, 0) }
        return (properties[kCGImagePropertyPixelWidth] as? Int ?? 0,
                properties[kCGImagePropertyPixelHeight] as? Int ?? 0)
    }
}
