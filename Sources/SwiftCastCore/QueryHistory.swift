import Foundation

/// Searches the user acted on (opened an app, revealed one, copied a result), newest first.
@MainActor
public final class QueryHistory {
    public static let limit = 100

    private let defaults: UserDefaults
    private let key = "queryHistory"
    public private(set) var entries: [String]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = defaults.stringArray(forKey: key) ?? []
    }

    /// Moves `query` to the front, dropping an earlier copy. Blank queries are ignored.
    public func record(_ query: String) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        entries.removeAll { $0 == query }
        entries.insert(query, at: 0)
        if entries.count > Self.limit {
            entries.removeLast(entries.count - Self.limit)
        }
        defaults.set(entries, forKey: key)
    }

    public func clear() {
        entries = []
        defaults.removeObject(forKey: key)
    }
}

/// Where the user is while stepping through history with ↑/↓, shell-style.
public struct HistoryCursor: Sendable {
    /// The entry being shown; `nil` when not browsing.
    public private(set) var index: Int?

    public init() {}

    public var isBrowsing: Bool { index != nil }

    /// Steps older (`delta` +1) or newer (−1) and returns the text to show, or `nil` when the
    /// key isn't a history step and should do its usual job. Stepping newer than the newest
    /// entry ends browsing and returns "".
    public mutating func move(_ delta: Int, through entries: [String]) -> String? {
        guard let index else {
            guard delta > 0, !entries.isEmpty else { return nil }
            self.index = 0
            return entries[0]
        }
        let next = index + delta
        if next < 0 {
            self.index = nil
            return ""
        }
        let clamped = min(next, entries.count - 1)
        self.index = clamped
        return entries[clamped]
    }

    public mutating func reset() {
        index = nil
    }
}
