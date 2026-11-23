import Foundation

/// Scores how well a query matches a candidate name. Higher is better; `nil` means no match.
/// Shared by plugins, so their rows report `MatchQuality` and highlights the same way.
///
/// Matches fall into tiers (exact > prefix > initials > word prefix > substring > subsequence).
/// Within a tier, shorter candidates score slightly higher.
public enum FuzzyMatcher {
    public enum Tier: Int, Sendable {
        case subsequence = 100
        case substring = 600
        case wordPrefix = 700
        case initials = 800
        case prefix = 900
        case exact = 1000

        /// The same kind of match, in the terms the app ranks every plugin's rows by.
        public var quality: MatchQuality {
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
    public struct Candidate: Sendable {
        public let chars: [Character]
        public let wordStarts: [Int]
        let wordStartSet: Set<Int>
        let initials: [Character]
        /// For a reading of another name (pinyin), the offset in that name each character came
        /// from; `nil` for a name matched as written.
        public let sources: [Int]?

        public init(_ name: String) {
            let original = Array(name)
            self.init(folded: original.map { FuzzyMatcher.fold($0) }, wordStarts: FuzzyMatcher.wordStarts(original), sources: nil)
        }

        /// A candidate from text that's already folded, such as a reading of another name.
        public init(folded chars: [Character], wordStarts starts: [Int], sources: [Int]?) {
            self.chars = chars
            wordStarts = starts
            wordStartSet = Set(starts)
            initials = starts.map { chars[$0] }
            self.sources = sources
        }
    }

    /// A query normalized once; `nil` when the query is blank.
    public struct Query: Sendable {
        public let chars: [Character]

        public init?(_ query: String) {
            chars = Array(FuzzyMatcher.normalize(query.trimmingCharacters(in: .whitespaces)))
            if chars.isEmpty { return nil }
        }
    }

    /// A successful match: its score, its kind and the matched character positions in the
    /// candidate.
    public struct Match: Equatable, Sendable {
        public let score: Int
        public let tier: Tier
        public let indices: [Int]

        public init(score: Int, tier: Tier, indices: [Int]) {
            self.score = score
            self.tier = tier
            self.indices = indices
        }
    }

    public static func score(query: String, candidate: String) -> Int? {
        match(query: query, candidate: candidate)?.score
    }

    public static func match(query: String, candidate: String) -> Match? {
        guard let q = Query(query) else { return nil }
        return match(q, Candidate(candidate))
    }

    public static func score(_ query: Query, _ candidate: Candidate) -> Int? {
        match(query, candidate)?.score
    }

    public static func match(_ query: Query, _ candidate: Candidate) -> Match? {
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

    public static func fold(_ ch: Character) -> Character {
        normalize(String(ch)).first ?? ch
    }

    public static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
    }

    /// Indices where a word begins: the first character, a letter or digit after a separator,
    /// an uppercase letter after a lowercase one (camelCase), and a digit after a letter.
    public static func wordStarts(_ chars: [Character]) -> [Int] {
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
