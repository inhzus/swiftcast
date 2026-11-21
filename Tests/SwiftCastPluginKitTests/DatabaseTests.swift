import Foundation
import Testing
@testable import SwiftCastPluginKit

struct DatabaseTests {
    private let url = FileManager.default.temporaryDirectory
        .appending(path: "SwiftCastTests-\(UUID().uuidString)/test.db")
    private let migrations = ["CREATE TABLE items (name TEXT PRIMARY KEY, count INTEGER, score REAL)"]

    @Test func migratesToTheLatestVersion() throws {
        let database = try Database(url: url, migrations: migrations)
        #expect(database.userVersion == migrations.count)
        // Reopening doesn't rerun migrations, which would fail on existing tables.
        #expect(try Database(url: url, migrations: migrations).userVersion == migrations.count)
    }

    @Test func runsOnlyAppendedMigrations() throws {
        try Database(url: url, migrations: migrations).execute("INSERT INTO items (name) VALUES ('a')")
        let later = migrations + ["ALTER TABLE items ADD COLUMN note TEXT"]
        let database = try Database(url: url, migrations: later)
        #expect(database.userVersion == later.count)
        #expect(database.rows("SELECT name, note FROM items") == [[.text("a"), .null]])
    }

    @Test func valuesRoundTripThroughTheFile() throws {
        try Database(url: url, migrations: migrations).execute(
            "INSERT INTO items (name, count, score) VALUES (?, ?, ?)",
            [.text("com.apple.Safari"), .int(3), .double(1.5)])
        let rows = try Database(url: url, migrations: migrations).rows("SELECT name, count, score FROM items")
        #expect(rows == [[.text("com.apple.Safari"), .int(3), .double(1.5)]])
    }

    @Test func badStatementsReturnNoRows() {
        #expect(Database.inMemory(migrations: []).rows("SELECT * FROM missing").isEmpty)
    }
}
