import Foundation
import SwiftCastPluginKit

/// Scores how well a query matches a candidate name. Higher is better; `nil` means no match.
///
/// Matches fall into tiers (exact > prefix > initials > word prefix > substring > subsequence).
/// Within a tier, shorter candidates score slightly higher.
enum FuzzyMatcher {
    enum Tier: Int {
        case subsequence = 100
        case substring = 600
        case wordPrefix = 700
        case initials = 800
        case prefix = 900
        case exact = 1000

        /// The same kind of match, in the terms the app ranks every plugin's rows by.
        var quality: MatchQuality {
            switch self {
            case .subsequence: .fuzzy
            case .substring: .substring
            case .wordPrefix: .wordPrefix
            case .initials: .initials
            case .prefix: .prefix
            case .exact: .exact
            }
        }
    }

    /// A candidate name prepared once (folded characters, word starts) so it can be scored
    /// against many queries cheaply.
    struct Candidate: Sendable {
        let chars: [Character]
        let wordStarts: [Int]
        let wordStartSet: Set<Int>
        let initials: [Character]

        init(_ name: String) {
            let original = Array(name)
            let chars = original.map { FuzzyMatcher.fold($0) }
            let starts = FuzzyMatcher.wordStarts(original)
            self.chars = chars
            wordStarts = starts
            wordStartSet = Set(starts)
            initials = starts.map { chars[$0] }
        }
    }

    /// A query normalized once; `nil` when the query is blank.
    struct Query: Sendable {
        let chars: [Character]

        init?(_ query: String) {
            chars = Array(FuzzyMatcher.normalize(query.trimmingCharacters(in: .whitespaces)))
            if chars.isEmpty { return nil }
        }
    }

    /// A successful match: its score, its kind and the matched character positions in the
    /// candidate.
    struct Match: Equatable, Sendable {
        let score: Int
        let tier: Tier
        let indices: [Int]
    }

    static func score(query: String, candidate: String) -> Int? {
        match(query: query, candidate: candidate)?.score
    }

    static func match(query: String, candidate: String) -> Match? {
        guard let q = Query(query) else { return nil }
        return match(q, Candidate(candidate))
    }

    static func score(_ query: Query, _ candidate: Candidate) -> Int? {
        match(query, candidate)?.score
    }

    static func match(_ query: Query, _ candidate: Candidate) -> Match? {
        let q = query.chars
        let c = candidate.chars
        guard q.count <= c.count else { return nil }

        let lengthPenalty = min(c.count, 99)

        if q == c {
            return Match(score: Tier.exact.rawValue, tier: .exact, indices: Array(c.indices))
        }
        if c.starts(with: q) {
            return Match(score: Tier.prefix.rawValue - lengthPenalty, tier: .prefix, indices: Array(q.indices))
        }
        if q.count > 1, candidate.initials.starts(with: q) {
            return Match(score: Tier.initials.rawValue - lengthPenalty, tier: .initials, indices: Array(candidate.wordStarts.prefix(q.count)))
        }
        if let start = candidate.wordStarts.first(where: { c[$0...].starts(with: q) }) {
            return Match(score: Tier.wordPrefix.rawValue - lengthPenalty, tier: .wordPrefix, indices: Array(start..<(start + q.count)))
        }
        if let offset = firstIndex(of: q, in: c) {
            return Match(
                score: Tier.substring.rawValue - min(offset * 5, 50) - lengthPenalty / 2,
                tier: .substring,
                indices: Array(offset..<(offset + q.count))
            )
        }
        return subsequenceMatch(q, c, wordStarts: candidate.wordStartSet)
    }

    // MARK: - Helpers

    static func fold(_ ch: Character) -> Character {
        normalize(String(ch)).first ?? ch
    }

    static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
    }

    /// Indices where a word begins: the first character, a letter or digit after a separator,
    /// an uppercase letter after a lowercase one (camelCase), and a digit after a letter.
    static func wordStarts(_ chars: [Character]) -> [Int] {
        var result: [Int] = []
        for i in chars.indices {
            let ch = chars[i]
            guard ch.isLetter || ch.isNumber else { continue }
            if i == 0 {
                result.append(i)
                continue
            }
            let prev = chars[i - 1]
            if !(prev.isLetter || prev.isNumber)
                || (prev.isLowercase && ch.isUppercase)
                || (prev.isLetter && ch.isNumber) {
                result.append(i)
            }
        }
        return result
    }

    static func firstIndex(of needle: [Character], in haystack: [Character]) -> Int? {
        guard needle.count <= haystack.count else { return nil }
        for i in 0...(haystack.count - needle.count)
        where haystack[i..<(i + needle.count)].elementsEqual(needle) {
            return i
        }
        return nil
    }

    /// Greedy left-to-right subsequence match; rewards consecutive runs and word starts.
    static func subsequenceMatch(_ q: [Character], _ c: [Character], wordStarts: Set<Int>) -> Match? {
        var indices: [Int] = []
        var qi = 0
        var last = -1
        var bonus = 0
        var first = -1
        for ci in c.indices where qi < q.count && c[ci] == q[qi] {
            if first < 0 { first = ci }
            if last >= 0 {
                if ci == last + 1 {
                    bonus += 10
                } else {
                    bonus -= min(ci - last - 1, 5)
                }
            }
            if wordStarts.contains(ci) { bonus += 15 }
            last = ci
            indices.append(ci)
            qi += 1
        }
        guard qi == q.count else { return nil }
        let score = Tier.subsequence.rawValue + 200 + bonus - min(first, 20) - min(c.count, 99) / 2
        return Match(score: max(1, min(score, Tier.substring.rawValue - 51)), tier: .subsequence, indices: indices)
    }
}
