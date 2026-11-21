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

/// Ranks indexed apps against a query, combining match quality with frecency.
@MainActor
final class SearchEngine {
    /// Points an alternate-name match loses against the same kind of match on the app's name.
    static let alternateNamePenalty = 50

    private(set) var apps: [AppEntry] = []
    /// How much the user opens each app, by ID; the app supplies these (see `PluginContext`).
    var usageBoost: (String) -> Int = { _ in 0 }
    var frecency: (String) -> Double = { _ in 0 }
    /// Prepared match candidates, parallel to `apps`: the name first, then alternate names.
    private var candidates: [[FuzzyMatcher.Candidate]] = []
    /// Text that tells apart apps sharing a name, keyed by app ID.
    private var details: [String: String] = [:]

    func update(apps: [AppEntry]) {
        self.apps = apps
        candidates = apps.map { app in
            ([app.name] + app.alternateNames).map { FuzzyMatcher.Candidate($0) }
        }
        details = Self.details(for: apps)
    }

    func results(for query: String, limit: Int = 20) -> [SearchResult] {
        var scored: [(result: SearchResult, score: Double)] = []
        if let q = FuzzyMatcher.Query(query) {
            for (app, names) in zip(apps, candidates) {
                if let match = Self.bestMatch(q, names) {
                    let total = match.score + usageBoost(app.id)
                    let result = SearchResult(app: app, matchedIndices: match.indices, match: match.tier.quality)
                    scored.append((result, Double(total)))
                }
            }
        } else {
            for app in apps {
                let used = frecency(app.id)
                if used > 0 { scored.append((SearchResult(app: app), used)) }
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
    /// (the first candidate), so they're kept from its match even when an alternate scores higher.
    private static func bestMatch(_ q: FuzzyMatcher.Query, _ names: [FuzzyMatcher.Candidate]) -> FuzzyMatcher.Match? {
        let own = FuzzyMatcher.match(q, names[0])
        var best = own.map { (score: $0.score, tier: $0.tier) }
        for name in names.dropFirst() {
            if let match = FuzzyMatcher.match(q, name), match.score - alternateNamePenalty > best?.score ?? .min {
                best = (match.score - alternateNamePenalty, match.tier)
            }
        }
        return best.map { FuzzyMatcher.Match(score: $0.score, tier: $0.tier, indices: own?.indices ?? []) }
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
