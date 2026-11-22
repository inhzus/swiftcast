import Foundation
import SwiftCastPluginKit

/// An app in the results, with how it matched the query and the positions in its name that
/// matched.
struct SearchResult: Hashable, Identifiable, Sendable {
    let app: AppEntry
    /// Character offsets into `app.name`; empty when an alternate name matched.
    let matchedIndices: [Int]
    let match: MatchQuality

    var id: String { app.id }

    init(app: AppEntry, matchedIndices: [Int] = [], match: MatchQuality = .prefix) {
        self.app = app
        self.matchedIndices = matchedIndices
        self.match = match
    }
}

/// Ranks indexed apps against a query, combining match quality with usage.
@MainActor
final class SearchEngine {
    /// Points an alternate-name match loses against the same kind of match on the app's name.
    static let alternateNamePenalty = 50

    private(set) var apps: [AppEntry] = []
    /// How much the user opens each app, by ID; the app supplies these (see `PluginContext`).
    var usageBoost: (String) -> Int = { _ in 0 }
    /// Prepared match candidates, parallel to `apps`: the name first, then its pinyin readings, then alternate names.
    private var candidates: [[FuzzyMatcher.Candidate]] = []
    /// Text that tells apart apps sharing a name, keyed by app ID.
    private var details: [String: String] = [:]

    func update(apps: [AppEntry]) {
        self.apps = apps
        candidates = apps.map { app in
            [FuzzyMatcher.Candidate(app.name)]
                + app.pinyin.map { FuzzyMatcher.Candidate($0) }
                + app.alternateNames.map { FuzzyMatcher.Candidate($0) }
        }
        details = Self.details(for: apps)
    }

    func results(for query: String, limit: Int = 20) -> [SearchResult] {
        guard let q = FuzzyMatcher.Query(query) else { return [] }
        var scored: [(result: SearchResult, score: Int)] = []
        for (app, names) in zip(apps, candidates) {
            if let match = Self.bestMatch(q, names) {
                let result = SearchResult(app: app, matchedIndices: match.indices, match: match.tier.quality)
                scored.append((result, match.score + usageBoost(app.id)))
            }
        }
        return scored
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.result.app.name < $1.result.app.name }
            .prefix(limit)
            .map(\.result)
    }

    /// Distinguishing text for an app whose name another indexed app shares: its folder, or
    /// its bundle's file name when the folder is shared too. `nil` for unique names.
    func detail(for app: AppEntry) -> String? {
        details[app.id]
    }

    /// The best score across an app's names. Highlights always refer to the app's own name
    /// (the first candidate), so they're kept from its match even when an alternate scores
    /// higher. A pinyin reading counts as the name itself: no penalty, and its matched letters
    /// highlight the characters they were read from.
    private static func bestMatch(_ q: FuzzyMatcher.Query, _ names: [FuzzyMatcher.Candidate]) -> FuzzyMatcher.Match? {
        var best = FuzzyMatcher.match(q, names[0])
        var ownIndices = best?.indices ?? []
        for name in names.dropFirst() {
            guard let match = FuzzyMatcher.match(q, name) else { continue }
            if let sources = name.sources {
                if match.score > best?.score ?? .min {
                    ownIndices = Array(Set(match.indices.map { sources[$0] })).sorted()
                    best = match
                }
            } else if match.score - alternateNamePenalty > best?.score ?? .min {
                best = FuzzyMatcher.Match(score: match.score - alternateNamePenalty, tier: match.tier, indices: [])
            }
        }
        return best.map { FuzzyMatcher.Match(score: $0.score, tier: $0.tier, indices: ownIndices) }
    }

    private static func details(for apps: [AppEntry]) -> [String: String] {
        var result: [String: String] = [:]
        for group in Dictionary(grouping: apps, by: { $0.name.lowercased() }).values where group.count > 1 {
            let folders = group.map { $0.url.deletingLastPathComponent().path }
            let foldersDiffer = Set(folders).count == group.count
            for (app, folder) in zip(group, folders) {
                result[app.id] = foldersDiffer
                    ? (folder as NSString).abbreviatingWithTildeInPath
                    : app.url.lastPathComponent
            }
        }
        return result
    }
}
