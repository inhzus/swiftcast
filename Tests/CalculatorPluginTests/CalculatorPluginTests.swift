import SwiftCastPluginKit
import Testing
@testable import CalculatorPlugin

@MainActor
struct CalculatorPluginTests {
    @Test func mathGivesOneCopyRow() throws {
        let rows = CalculatorPlugin().results(for: "1.5 GB in MB")
        let row = try #require(rows.first)
        #expect(rows.count == 1)
        #expect(row.title == "1,536 MB")
        #expect(row.detail == "= 1.5 GB in MB")
        #expect(row.actions == [ResultAction("Copy", .copy("1536 MB"))])
    }

    @Test func otherQueriesGiveNoRows() {
        #expect(CalculatorPlugin().results(for: "safari").isEmpty)
        #expect(CalculatorPlugin().results(for: "2048").isEmpty)
    }
}
