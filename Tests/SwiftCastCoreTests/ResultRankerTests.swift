import SwiftCastPluginKit
import Testing
@testable import SwiftCastCore

struct ResultRankerTests {
    private struct Row: Equatable {
        let name: String
        let match: MatchQuality
        var boost = 0
    }

    private func rank(_ rows: [Row]) -> [String] {
        ResultRanker.rank(rows, match: \.match, boost: \.boost).map(\.name)
    }

    @Test func betterMatchesComeFirstWhateverTheirUsage() {
        #expect(rank([
            Row(name: "Clockwork", match: .prefix, boost: 60),
            Row(name: "Clock", match: .exact),
            Row(name: "Calendar", match: .fuzzy, boost: 60),
        ]) == ["Clock", "Clockwork", "Calendar"])
    }

    @Test func usageOrdersEqualMatchesAcrossPlugins() {
        #expect(rank([
            Row(name: "Clock", match: .prefix),
            Row(name: "Clipboard History", match: .prefix, boost: 15),
        ]) == ["Clipboard History", "Clock"])
    }

    @Test func tiesKeepTheirOrder() {
        #expect(rank([
            Row(name: "b", match: .prefix),
            Row(name: "a", match: .prefix),
            Row(name: "c", match: .prefix),
        ]) == ["b", "a", "c"])
    }
}
