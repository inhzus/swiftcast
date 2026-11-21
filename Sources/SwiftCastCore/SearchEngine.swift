import Foundation

/// Ranks indexed apps against a query, combining match quality with launch frequency.
@MainActor
public final class SearchEngine {
    public private(set) var apps: [AppEntry] = []
    public let usage: UsageStore
    /// Prepared match candidates, parallel to `apps`.
    private var candidates: [FuzzyMatcher.Candidate] = []

    public init(usage: UsageStore) {
        self.usage = usage
    }

    public func update(apps: [AppEntry]) {
        self.apps = apps
        candidates = apps.map { FuzzyMatcher.Candidate($0.name) }
    }

    public func results(for query: String, limit: Int = 20) -> [AppEntry] {
        var scored: [(app: AppEntry, score: Int)] = []
        if let q = FuzzyMatcher.Query(query) {
            for (app, candidate) in zip(apps, candidates) {
                if let score = FuzzyMatcher.score(q, candidate) {
                    scored.append((app, score + usageBoost(for: app)))
                }
            }
        } else {
            for app in apps {
                let count = usage.count(for: app.id)
                if count > 0 { scored.append((app, count)) }
            }
        }
        return scored
            .sorted(by: Self.ranksBefore)
            .prefix(limit)
            .map(\.app)
    }

    private static func ranksBefore(_ a: (app: AppEntry, score: Int), _ b: (app: AppEntry, score: Int)) -> Bool {
        a.score != b.score ? a.score > b.score : a.app.name < b.app.name
    }

    /// Up to 60 points, growing logarithmically with launch count.
    func usageBoost(for app: AppEntry) -> Int {
        let count = usage.count(for: app.id)
        guard count > 0 else { return 0 }
        return min(Int(15 * log2(Double(count + 1))), 60)
    }
}
