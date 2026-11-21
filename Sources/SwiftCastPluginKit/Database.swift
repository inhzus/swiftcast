import Foundation
import SQLite3

/// A SQLite database file with its own schema. Each plugin opens its own, named after its
/// `id`, and owns its tables and migrations; the app keeps its search history in another.
/// App-wide settings stay in `UserDefaults`.
public final class Database {
    public enum Value: Equatable, Sendable {
        case int(Int64)
        case double(Double)
        case text(String)
        case null

        public var int: Int64? { if case .int(let value) = self { value } else { nil } }
        public var double: Double? {
            switch self {
            case .double(let value): value
            case .int(let value): Double(value)
            default: nil
            }
        }
        public var text: String? { if case .text(let value) = self { value } else { nil } }
    }

    public struct Error: Swift.Error, CustomStringConvertible {
        public let description: String
    }

    /// `~/Library/Application Support/<bundle ID>/<name>.db`.
    public static func url(named name: String) -> URL {
        URL.applicationSupportDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? "dev.swiftcast.app")
            .appending(path: "\(name).db")
    }

    /// Opens `<name>.db` under Application Support. Falls back to an in-memory database, so
    /// its owner still works without saving.
    public static func open(_ name: String, migrations: [String]) -> Database {
        do {
            return try Database(url: url(named: name), migrations: migrations)
        } catch {
            NSLog("SwiftCast: can't open \(name).db (\(error)); changes won't be saved")
            return inMemory(migrations: migrations)
        }
    }

    /// Schema changes, applied in order. `PRAGMA user_version` records how many have run, so
    /// owners only ever append to their list.
    private let migrations: [String]
    private let db: OpaquePointer

    public convenience init(url: URL, migrations: [String]) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try self.init(path: url.path, migrations: migrations)
    }

    /// A database that lives only as long as this object: for tests, and as a fallback when
    /// the file can't be opened.
    public static func inMemory(migrations: [String]) -> Database {
        // Opening an in-memory database only fails when SQLite can't allocate memory.
        try! Database(path: ":memory:", migrations: migrations)
    }

    private init(path: String, migrations: [String]) throws {
        self.migrations = migrations
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "out of memory"
            sqlite3_close(handle)
            throw Error(description: "open \(path): \(message)")
        }
        db = handle
        execute("PRAGMA journal_mode = WAL")
        try migrate()
    }

    deinit {
        sqlite3_close(db)
    }

    var userVersion: Int {
        Int(rows("PRAGMA user_version").first?.first?.int ?? 0)
    }

    private func migrate() throws {
        for (index, sql) in migrations.enumerated() where index >= userVersion {
            try exec("BEGIN")
            do {
                try exec(sql)
                try exec("PRAGMA user_version = \(index + 1)")
                try exec("COMMIT")
            } catch {
                try? exec("ROLLBACK")
                throw error
            }
        }
    }

    /// Runs one or more statements with no bindings, throwing on the first failure.
    private func exec(_ sql: String) throws {
        var message: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &message) == SQLITE_OK else {
            let text = message.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(message)
            throw Error(description: text)
        }
    }

    /// Runs a statement that returns no rows. Failures are logged: callers keep their
    /// in-memory state, so a failed write costs persistence, not the feature.
    public func execute(_ sql: String, _ bindings: [Value] = []) {
        _ = rows(sql, bindings)
    }

    /// Runs a statement and returns every row it produces.
    @discardableResult
    public func rows(_ sql: String, _ bindings: [Value] = []) -> [[Value]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            log(sql)
            return []
        }
        defer { sqlite3_finalize(statement) }

        for (index, value) in bindings.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case .int(let int): sqlite3_bind_int64(statement, position, int)
            case .double(let double): sqlite3_bind_double(statement, position, double)
            case .text(let text): sqlite3_bind_text(statement, position, text, -1, Self.transient)
            case .null: sqlite3_bind_null(statement, position)
            }
        }

        var result: [[Value]] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                result.append((0..<sqlite3_column_count(statement)).map { column in
                    switch sqlite3_column_type(statement, column) {
                    case SQLITE_INTEGER: .int(sqlite3_column_int64(statement, column))
                    case SQLITE_FLOAT: .double(sqlite3_column_double(statement, column))
                    case SQLITE_TEXT: .text(String(cString: sqlite3_column_text(statement, column)))
                    default: .null
                    }
                })
            case SQLITE_DONE:
                return result
            default:
                log(sql)
                return result
            }
        }
    }

    /// Runs `body` in one transaction, so its writes land together and cost one sync.
    public func transaction(_ body: () -> Void) {
        execute("BEGIN")
        body()
        execute("COMMIT")
    }

    private func log(_ sql: String) {
        NSLog("SwiftCast: SQLite error \(String(cString: sqlite3_errmsg(db))) in: \(sql)")
    }

    /// Tells SQLite to copy bound text, since Swift's temporary C string doesn't outlive the call.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
