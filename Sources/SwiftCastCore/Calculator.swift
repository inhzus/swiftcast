import Foundation

/// The result of a math query, ready to show and copy.
public struct Calculation: Hashable, Sendable {
    /// The query as typed, trimmed.
    public let expression: String
    /// The value in base units: bytes for sizes, otherwise the plain number.
    public let value: Double
    /// Formatted for display, with grouping separators (e.g. "1,536 MB").
    public let display: String
    /// The same without grouping separators, for the clipboard.
    public let copyText: String
}

/// Evaluates quick-math queries: arithmetic, a few functions, percentages, and data sizes.
///
/// Returns `nil` for anything that isn't clearly math, so app searches like "1password" or
/// "2048" are never hijacked: the whole query must parse, and it must contain an operator,
/// a percentage, a function call, or an `in`/`to` unit conversion.
public enum Calculator {
    public static func evaluate(_ input: String) -> Calculation? {
        let expression = input.trimmingCharacters(in: .whitespaces)
        var source = expression
        var target: SizeUnit?
        if let (body, unit) = splitConversion(expression) {
            source = body
            target = unit
        }
        guard let tokens = tokenize(source) else { return nil }
        var parser = Parser(tokens: tokens)
        guard let result = parser.parse(), parser.isAtEnd,
              parser.operations > 0 || target != nil,
              result.value.isFinite,
              result.sizePower == 0 || result.sizePower == 1 else { return nil }
        // Snap float noise like sin(pi) = 1.2e-16 to 0, which also avoids "-0".
        let value = abs(result.value) < 1e-15 ? 0 : result.value

        if let target {
            guard result.sizePower == 1 else { return nil }
            let amount = value / target.bytes
            return Calculation(expression: expression, value: value,
                               display: Format.size(amount, unit: target.name, grouping: true),
                               copyText: Format.size(amount, unit: target.name, grouping: false))
        }
        if result.sizePower == 1 {
            let (amount, unit) = SizeUnit.readable(for: value)
            return Calculation(expression: expression, value: value,
                               display: Format.size(amount, unit: unit, grouping: true),
                               copyText: Format.size(amount, unit: unit, grouping: false))
        }
        return Calculation(expression: expression, value: value,
                           display: Format.number(value, grouping: true),
                           copyText: Format.number(value, grouping: false))
    }

    /// Splits "1.5 GB in MB" into ("1.5 GB", MB) when it ends in `in`/`to` and a unit.
    private static func splitConversion(_ text: String) -> (String, SizeUnit)? {
        let words = text.split(separator: " ", omittingEmptySubsequences: true)
        guard words.count >= 3,
              ["in", "to"].contains(words[words.count - 2].lowercased()),
              let unit = SizeUnit(String(words[words.count - 1])) else { return nil }
        return (words.dropLast(2).joined(separator: " "), unit)
    }
}

// MARK: - Units

/// A data-size unit. Prefixes are powers of 1024, so KB and KiB are the same size.
struct SizeUnit: Equatable {
    let name: String
    let bytes: Double

    private static let prefixes: [Character: Int] = ["k": 1, "m": 2, "g": 3, "t": 4, "p": 5]
    private static let readableNames = ["B", "KB", "MB", "GB", "TB", "PB"]

    /// Parses a unit name. Byte units are case-insensitive ("mb" is megabytes); bits are
    /// "bit(s)", "Mbit", or an uppercase prefix with a lowercase "b" ("Mb").
    init?(_ text: String) {
        let lower = text.lowercased()
        switch lower {
        case "b", "byte", "bytes": self.init(name: "B", bytes: 1); return
        case "bit", "bits": self.init(name: "bit", bytes: 1.0 / 8); return
        default: break
        }
        guard let first = lower.first, let power = Self.prefixes[first] else { return nil }
        let rest = lower.dropFirst()
        let scale = pow(1024, Double(power))
        let prefix = String(text.first!).uppercased()
        if rest == "bit" || rest == "bits" {
            self.init(name: prefix + "bit", bytes: scale / 8)
        } else if rest == "b" {
            let isBits = text.count == 2 && text.first!.isUppercase && text.last == "b"
            self.init(name: prefix + (isBits ? "b" : "B"), bytes: isBits ? scale / 8 : scale)
        } else if rest == "ib" {
            self.init(name: prefix + "iB", bytes: scale)
        } else {
            return nil
        }
    }

    private init(name: String, bytes: Double) {
        self.name = name
        self.bytes = bytes
    }

    /// `bytes` in the largest unit (B … PB) that keeps the amount at least 1.
    static func readable(for bytes: Double) -> (Double, String) {
        var index = 0
        while index < readableNames.count - 1, abs(bytes) >= pow(1024, Double(index + 1)) {
            index += 1
        }
        return (bytes / pow(1024, Double(index)), readableNames[index])
    }
}

// MARK: - Formatting

private enum Format {
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
    static func size(_ amount: Double, unit: String, grouping: Bool) -> String {
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

// MARK: - Tokens

private enum Token: Equatable {
    case number(Double)
    case unit(SizeUnit)
    case plus, minus, times, divide, power, percent
    case open, close
    case identifier(String)
}

/// Splits `text` into tokens, or returns `nil` for anything it doesn't understand.
private func tokenize(_ text: String) -> [Token]? {
    let chars = Array(text)
    var tokens: [Token] = []
    var i = 0

    func endsWithValue() -> Bool {
        switch tokens.last {
        case .number, .unit, .close, .percent, .identifier: true
        default: false
        }
    }

    while i < chars.count {
        let c = chars[i]
        if c.isWhitespace {
            i += 1
        } else if c.isASCII && (c.isNumber || (c == "." && i + 1 < chars.count && chars[i + 1].isNumber)) {
            var j = i
            while j < chars.count, chars[j].isASCII, chars[j].isNumber || chars[j] == "." { j += 1 }
            guard let number = Double(String(chars[i..<j])) else { return nil }
            tokens.append(.number(number))
            i = j
            // A unit may follow, with or without a space.
            var k = j
            while k < chars.count, chars[k] == " " { k += 1 }
            var end = k
            while end < chars.count, chars[end].isASCII, chars[end].isLetter { end += 1 }
            if end > k, let unit = SizeUnit(String(chars[k..<end])) {
                tokens.append(.unit(unit))
                i = end
            }
        } else if c.isLetter || c == "π" {
            var j = i
            while j < chars.count, chars[j].isLetter || chars[j] == "π" { j += 1 }
            let word = String(chars[i..<j])
            if (word == "x" || word == "X") && endsWithValue() {
                tokens.append(.times)  // "2x3", "2 x (1+1)"
            } else {
                tokens.append(.identifier(word.lowercased()))
            }
            i = j
        } else {
            switch c {
            case "+": tokens.append(.plus)
            case "-", "−": tokens.append(.minus)
            case "*", "×": tokens.append(.times)
            case "/", "÷": tokens.append(.divide)
            case "^": tokens.append(.power)
            case "%": tokens.append(.percent)
            case "(": tokens.append(.open)
            case ")": tokens.append(.close)
            default: return nil
            }
            i += 1
        }
    }
    return tokens
}

// MARK: - Parser

/// A number, or a data size in bytes (`sizePower` 1). Powers other than 0 and 1 can appear
/// mid-expression (e.g. size × size ÷ size) but aren't valid results.
private struct Quantity {
    var value: Double
    var sizePower: Int
}

/// Recursive descent, lowest precedence first:
/// sum → product → unary → power → postfix (%) → primary.
private struct Parser {
    let tokens: [Token]
    var index = 0
    /// Binary operators, percentages, and function calls seen; zero means "not math".
    private(set) var operations = 0

    init(tokens: [Token]) {
        self.tokens = tokens
    }

    var isAtEnd: Bool { index == tokens.count }

    mutating func parse() -> Quantity? {
        sum()?.quantity
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
                guard left.quantity.sizePower == right.quantity.sizePower else { return nil }
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
                left.quantity.sizePower += right.quantity.sizePower
            } else {
                guard right.quantity.value != 0 else { return nil }
                left.quantity.value /= right.quantity.value
                left.quantity.sizePower -= right.quantity.sizePower
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

    /// Right-associative, and binds tighter than unary minus: -2^2 = -4.
    private mutating func power() -> (quantity: Quantity, isPercent: Bool)? {
        guard let base = postfix() else { return nil }
        guard take(.power) else { return base }
        guard let exponent = unary(), base.quantity.sizePower == 0, exponent.quantity.sizePower == 0 else {
            return nil
        }
        operations += 1
        return (Quantity(value: pow(base.quantity.value, exponent.quantity.value), sizePower: 0), false)
    }

    private mutating func postfix() -> (quantity: Quantity, isPercent: Bool)? {
        guard var value = primary() else { return nil }
        if take(.percent) {
            guard value.sizePower == 0 else { return nil }
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
            if case .unit(let unit) = current {
                index += 1
                return Quantity(value: number * unit.bytes, sizePower: 1)
            }
            return Quantity(value: number, sizePower: 0)
        case .open:
            guard let inner = sum()?.quantity, take(.close) else { return nil }
            return inner
        case .identifier(let name):
            switch name {
            case "pi", "π": return Quantity(value: .pi, sizePower: 0)
            case "e": return Quantity(value: M_E, sizePower: 0)
            default: return call(name)
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
        case "abs": return Quantity(value: abs(x), sizePower: argument.sizePower)
        case "round": return Quantity(value: x.rounded(), sizePower: argument.sizePower)
        default: break
        }
        guard argument.sizePower == 0 else { return nil }
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
        return Quantity(value: result, sizePower: 0)
    }
}
