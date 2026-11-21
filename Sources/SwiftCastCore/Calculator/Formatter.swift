import Foundation

enum Format {
    /// How to show `value` of `dimension`, as (display, copyText), or `nil` when it isn't a
    /// kind anything in the query or registry can name (e.g. GB²).
    ///
    /// In order: the `in`/`to` target; the category's ladder when it always uses one (data);
    /// the first unit in the query of the same kind ("5 ft + 3 in" stays in feet); the
    /// category's ladder.
    static func result(_ value: Double, _ dimension: Dimension, target: UnitExpression?,
                       usedUnits: [UnitExpression], registry: UnitRegistry) -> (String, String)? {
        if let target {
            guard target.dimension == dimension else { return nil }
            return both { quantity(value / target.factor, unit: target.symbol, grouping: $0) }
        }
        if dimension.isNone {
            return both { number(value, grouping: $0) }
        }
        let category = registry.category(for: dimension)
        if let category, category.alwaysUsesLadder, let step = category.readable(value) {
            return both { quantity(step.amount, unit: step.unit.symbol, grouping: $0) }
        }
        if let unit = usedUnits.first(where: { $0.dimension == dimension }) {
            return both { quantity(value / unit.factor, unit: unit.symbol, grouping: $0) }
        }
        if let step = category?.readable(value) {
            return both { quantity(step.amount, unit: step.unit.symbol, grouping: $0) }
        }
        return nil
    }

    /// The display text (grouped) and the clipboard text (ungrouped).
    static func both(_ format: (Bool) -> String) -> (String, String) {
        (format(true), format(false))
    }

    /// Up to 12 significant digits; very large or small values as e.g. "1.152921505e18".
    static func number(_ value: Double, grouping: Bool) -> String {
        let magnitude = abs(value)
        guard magnitude >= 1e15 || (magnitude > 0 && magnitude < 1e-9) else {
            return decimal(value, significantDigits: 12, grouping: grouping)
        }
        var exponent = Int(floor(log10(magnitude)))
        var mantissa = decimal(value / pow(10, Double(exponent)), significantDigits: 10, grouping: false)
        if mantissa.hasPrefix("10") || mantissa.hasPrefix("-10") {  // 9.9999999999 rounded up
            exponent += 1
            mantissa = decimal(value / pow(10, Double(exponent)), significantDigits: 10, grouping: false)
        }
        return "\(mantissa)e\(exponent)"
    }

    private static func decimal(_ value: Double, significantDigits: Int, grouping: Bool) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesSignificantDigits = true
        formatter.maximumSignificantDigits = significantDigits
        formatter.usesGroupingSeparator = grouping
        return formatter.string(from: value as NSNumber) ?? String(value)
    }

    /// An amount of `unit`: up to 2 decimals, or 3 significant digits below 1.
    static func quantity(_ amount: Double, unit: String, grouping: Bool) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = grouping
        if abs(amount) < 1, amount != 0 {
            formatter.usesSignificantDigits = true
            formatter.maximumSignificantDigits = 3
        } else {
            formatter.maximumFractionDigits = 2
        }
        return (formatter.string(from: amount as NSNumber) ?? String(amount)) + " " + unit
    }
}
