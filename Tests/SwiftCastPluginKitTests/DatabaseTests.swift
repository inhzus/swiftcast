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
        #expect(database.rows("SELECT name, note FROM items").map(\.values) == [[.text("a"), .null]])
    }

    @Test func valuesRoundTripThroughTheFile() throws {
        try Database(url: url, migrations: migrations).execute(
            "INSERT INTO items (name, count, score) VALUES (?, ?, ?)",
            [.text("com.apple.Safari"), .int(3), .double(1.5)])
        let rows = try Database(url: url, migrations: migrations).rows("SELECT name, count, score FROM items").map(\.values)
        #expect(rows == [[.text("com.apple.Safari"), .int(3), .double(1.5)]])
    }

    @Test func badStatementsReturnNoRows() {
        #expect(Database.inMemory(migrations: []).rows("SELECT * FROM missing").isEmpty)
    }

    @Test func readsColumnsByName() {
        let database = Database.inMemory(migrations: migrations)
        database.execute("INSERT INTO items (name, count) VALUES ('a', 2)")
        let row = database.rows("SELECT name, count FROM items")[0]
        #expect(row["name"] == .text("a"))
        #expect(row["count"] == .int(2))
        #expect(row["missing"] == .null)
        #expect(row[1] == .int(2))
        #expect(row[5] == .null)
    }

    @Test func reportsTheInsertedRowID() {
        let database = Database.inMemory(migrations: ["CREATE TABLE things (id INTEGER PRIMARY KEY, name TEXT)"])
        #expect(database.execute("INSERT INTO things (name) VALUES ('a')"))
        #expect(database.lastInsertRowID == 1)
        database.execute("INSERT INTO things (name) VALUES ('b')")
        #expect(database.lastInsertRowID == 2)
        #expect(!database.execute("INSERT INTO missing (name) VALUES ('c')"))
    }

    @Test func transactionRollsBackWhenAStatementFails() {
        let database = Database.inMemory(migrations: migrations)
        let committed = database.transaction {
            database.execute("INSERT INTO items (name) VALUES ('a')")
            database.execute("INSERT INTO items (name) VALUES ('a')")  // duplicate key
        }
        #expect(!committed)
        #expect(database.rows("SELECT name FROM items").isEmpty)
        #expect(database.transaction { database.execute("INSERT INTO items (name) VALUES ('b')") })
        #expect(database.rows("SELECT name FROM items").map(\.values) == [[.text("b")]])
    }

    @Test func transactionRollsBackWhenTheBodyThrows() {
        struct Stop: Error {}
        let database = Database.inMemory(migrations: migrations)
        #expect(throws: Stop.self) {
            try database.transaction {
                database.execute("INSERT INTO items (name) VALUES ('a')")
                throw Stop()
            }
        }
        #expect(database.rows("SELECT name FROM items").isEmpty)
    }
}
