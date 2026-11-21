import SwiftCastPluginKit

/// Orders rows from every plugin as one list, Raycast-style.
public enum ResultRanker {
    /// `rows` in registry order, each plugin's best first, sorted by how well they matched,
    /// then by `boost` (how much the user picks them), keeping that order for ties.
    public static func rank<Row>(
        _ rows: [Row], match: (Row) -> MatchQuality, boost: (Row) -> Int
    ) -> [Row] {
        rows.enumerated()
            .map { (row: $0.element, match: match($0.element), boost: boost($0.element), index: $0.offset) }
            .sorted {
                if $0.match != $1.match { return $0.match > $1.match }
                if $0.boost != $1.boost { return $0.boost > $1.boost }
                return $0.index < $1.index
            }
            .map(\.row)
    }
}
