import Testing
@testable import SwiftCastCore

struct FuzzyMatcherTests {
    private func score(_ q: String, _ c: String) -> Int? {
        FuzzyMatcher.score(query: q, candidate: c)
    }

    @Test func emptyQueryAndNonSubsequenceDoNotMatch() {
        #expect(score("", "Safari") == nil)
        #expect(score("   ", "Safari") == nil)
        #expect(score("xyz", "Safari") == nil)
        #expect(score("saf", "Disk Utility") == nil)
    }

    @Test func caseAndDiacriticInsensitive() {
        #expect(score("SAFARI", "Safari") != nil)
        #expect(score("cafe", "Café") != nil)
    }

    @Test func tiersAreOrdered() throws {
        let exact = try #require(score("notes", "Notes"))
        let prefix = try #require(score("not", "Notes"))
        let initials = try #require(score("vsc", "Visual Studio Code"))
        let wordPrefix = try #require(score("code", "Visual Studio Code"))
        let substring = try #require(score("ari", "Safari"))
        let subsequence = try #require(score("sfr", "Safari"))
        #expect(exact > prefix)
        #expect(prefix > initials)
        #expect(initials > wordPrefix)
        #expect(wordPrefix > substring)
        #expect(substring > subsequence)
    }

    @Test func camelCaseWordStarts() {
        #expect(score("term", "iTerm") != nil)
        #expect(score("term", "Terminal")! > score("term", "iTerm")!)
        #expect(score("xc", "XcodeCloud") != nil)
    }

    @Test func preparedCandidateScoresMatchStringOverload() {
        let names = ["Safari", "Visual Studio Code", "iTerm", "Café", "System Settings", "TV"]
        let queries = ["s", "saf", "vsc", "code", "term", "cafe", "sfr", "xyz", "system settings"]
        for name in names {
            let candidate = FuzzyMatcher.Candidate(name)
            for query in queries {
                let prepared = FuzzyMatcher.Query(query).flatMap { FuzzyMatcher.score($0, candidate) }
                #expect(prepared == score(query, name), "\(query) vs \(name)")
            }
        }
        #expect(FuzzyMatcher.Query("  ") == nil)
    }

    @Test func shorterNamesWinWithinTier() {
        #expect(score("mail", "Mail")! > score("mail", "Mailplane")!)
        #expect(score("sa", "Safari")! > score("sa", "Safari Technology Preview")!)
    }
}
