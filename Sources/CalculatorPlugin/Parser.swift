import Foundation

/// A number with a kind, its value in base units: 1.5 GB is 1,610,612,736 of `.data`.
struct Quantity {
    var value: Double
    var dimension: Dimension
}

/// A unit as written in a query, possibly compound: "km", "MB/s", "m^2".
struct UnitExpression {
    var symbol: String
    var factor: Double
    var dimension: Dimension

    init(_ candidate: Candidate) {
        symbol = candidate.unit.symbol
        factor = candidate.unit.factor
        dimension = candidate.category.dimension
    }
}

/// Recursive descent, lowest precedence first:
/// sum → product → unary → power → postfix (%) → primary.
///
/// Units are already resolved (see `UnitResolver`), so this only checks that kinds line up:
/// `+` needs matching dimensions, `×` and `÷` combine them.
struct Parser {
    /// Words with a fixed meaning here, which units must not reuse.
    static let reservedWords: Set<String> = [
        "pi", "π", "e", "abs", "round", "sqrt", "sin", "cos", "tan", "log", "ln", "to", "x",
    ]

    let tokens: [Token]
    let units: [String: Candidate]
    var index = 0
    /// Binary operators, percentages, and function calls seen; zero means "not math".
    private(set) var operations = 0
    /// Units written after numbers, in order, for picking how to show the result.
    private(set) var usedUnits: [UnitExpression] = []

    init(tokens: [Token], units: [String: Candidate]) {
        self.tokens = tokens
        self.units = units
    }

    var isAtEnd: Bool { index == tokens.count }

    mutating func parse() -> Quantity? {
        sum()?.quantity
    }

    /// A unit, optionally raised to an integer power, then optionally "/" another:
    /// "km", "m^2", "MB/s". Also used on its own for the target of "in"/"to".
    mutating func unitExpression() -> UnitExpression? {
        guard var expression = poweredUnit() else { return nil }
        while current == .divide, index + 1 < tokens.count, let word = tokens[index + 1].word, units[word] != nil {
            index += 1
            guard let denominator = poweredUnit() else { return nil }
            expression.symbol += "/" + denominator.symbol
            expression.factor /= denominator.factor
            expression.dimension = expression.dimension / denominator.dimension
        }
        return expression
    }

    private mutating func poweredUnit() -> UnitExpression? {
        guard let word = current?.word, let candidate = units[word], candidate.category.allowsArithmetic else {
            return nil
        }
        index += 1
        var expression = UnitExpression(candidate)
        if current == .power, index + 1 < tokens.count, case .number(let n) = tokens[index + 1],
           let power = Int(exactly: n) {
            index += 2
            expression.symbol += power == 2 ? "²" : power == 3 ? "³" : "^\(power)"
            expression.factor = pow(expression.factor, n)
            expression.dimension = expression.dimension.raised(to: power)
        }
        return expression
    }

    private var current: Token? { index < tokens.count ? tokens[index] : nil }

    private mutating func take(_ token: Token) -> Bool {
        guard current == token else { return false }
        index += 1
        return true
    }

    /// `a + b%` adds b percent of a.
    private mutating func sum() -> (quantity: Quantity, isPercent: Bool)? {
        guard var left = product() else { return nil }
        while let op = current, op == .plus || op == .minus {
            index += 1
            guard let right = product() else { return nil }
            operations += 1
            let sign: Double = op == .plus ? 1 : -1
            if right.isPercent {
                left.quantity.value *= 1 + sign * right.quantity.value
            } else {
                guard left.quantity.dimension == right.quantity.dimension else { return nil }
                left.quantity.value += sign * right.quantity.value
            }
            left.isPercent = false
        }
        return left
    }

    private mutating func product() -> (quantity: Quantity, isPercent: Bool)? {
        guard var left = unary() else { return nil }
        while let op = current, op == .times || op == .divide {
            index += 1
            guard let right = unary() else { return nil }
            operations += 1
            if op == .times {
                left.quantity.value *= right.quantity.value
                left.quantity.dimension = left.quantity.dimension * right.quantity.dimension
            } else {
                guard right.quantity.value != 0 else { return nil }
                left.quantity.value /= right.quantity.value
                left.quantity.dimension = left.quantity.dimension / right.quantity.dimension
            }
            left.isPercent = false
        }
        return left
    }

    private mutating func unary() -> (quantity: Quantity, isPercent: Bool)? {
        if take(.minus) {
            guard var operand = unary() else { return nil }
            operand.quantity.value = -operand.quantity.value
            return operand
        }
        if take(.plus) { return unary() }
        return power()
    }

    /// Right-associative, and binds tighter than unary minus: -2^2 = -4. A quantity with a
    /// kind can only be raised to a whole number: (3 m)^2 is 9 m².
    private mutating func power() -> (quantity: Quantity, isPercent: Bool)? {
        guard let base = postfix() else { return nil }
        guard take(.power) else { return base }
        guard let exponent = unary(), exponent.quantity.dimension.isNone else { return nil }
        let n = exponent.quantity.value
        var dimension = Dimension.none
        if !base.quantity.dimension.isNone {
            guard let whole = Int(exactly: n) else { return nil }
            dimension = base.quantity.dimension.raised(to: whole)
        }
        operations += 1
        return (Quantity(value: pow(base.quantity.value, n), dimension: dimension), false)
    }

    private mutating func postfix() -> (quantity: Quantity, isPercent: Bool)? {
        guard var value = primary() else { return nil }
        if take(.percent) {
            guard value.dimension.isNone else { return nil }
            operations += 1
            value.value /= 100
            return (value, true)
        }
        return (value, false)
    }

    private mutating func primary() -> Quantity? {
        guard let token = current else { return nil }
        index += 1
        switch token {
        case .number(let number):
            if current?.word.flatMap({ units[$0] }) != nil {
                guard let unit = unitExpression() else { return nil }
                usedUnits.append(unit)
                return Quantity(value: number * unit.factor, dimension: unit.dimension)
            }
            return Quantity(value: number, dimension: .none)
        case .open:
            guard let inner = sum()?.quantity, take(.close) else { return nil }
            return inner
        case .word(let word):
            switch word.lowercased() {
            case "pi", "π": return Quantity(value: .pi, dimension: .none)
            case "e": return Quantity(value: M_E, dimension: .none)
            case let name: return call(name)
            }
        default:
            return nil
        }
    }

    private mutating func call(_ name: String) -> Quantity? {
        guard take(.open), let argument = sum()?.quantity, take(.close) else { return nil }
        operations += 1
        let x = argument.value
        switch name {
        case "abs": return Quantity(value: abs(x), dimension: argument.dimension)
        case "round": return Quantity(value: x.rounded(), dimension: argument.dimension)
        default: break
        }
        guard argument.dimension.isNone else { return nil }
        let result: Double
        switch name {
        case "sqrt": result = sqrt(x)
        case "sin": result = sin(x)
        case "cos": result = cos(x)
        case "tan": result = tan(x)
        case "log": result = log10(x)
        case "ln": result = log(x)
        default: return nil
        }
        return Quantity(value: result, dimension: .none)
    }
}
