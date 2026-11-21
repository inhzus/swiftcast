import Foundation

/// The result of a math query, ready to show and copy.
struct Calculation: Hashable, Sendable {
    /// The query as typed, trimmed.
    let expression: String
    /// The value in its kind's base unit (bytes, metres, seconds…), or the plain number.
    let value: Double
    /// Formatted for display, with grouping separators (e.g. "1,536 MB").
    let display: String
    /// The same without grouping separators, for the clipboard.
    let copyText: String
    /// How ambiguous unit words were read, e.g. "B = billion"; `nil` when none were.
    let note: String?
}

/// Evaluates quick-math queries: arithmetic, a few functions, percentages, and units.
///
/// Returns `nil` for anything that isn't clearly math, so app searches like "1password" or
/// "2048" are never hijacked: the whole query must parse, and it must contain an operator,
/// a percentage, a function call, or an `in`/`to` unit conversion.
///
/// The pipeline is lex → split off the target → resolve unit words → parse → format. Only
/// the unit tables in `Units/` know about particular units.
enum Calculator {
    static func evaluate(_ input: String) -> Calculation? {
        evaluate(input, registry: .builtIn)
    }

    static func evaluate(_ input: String, registry: UnitRegistry) -> Calculation? {
        let expression = input.trimmingCharacters(in: .whitespaces)
        guard let tokens = Lexer.tokenize(expression) else { return nil }
        let (body, targetTokens) = splitConversion(tokens)
        let words = (body + (targetTokens ?? [])).compactMap(\.word)
        let resolution = UnitResolver.resolve(words, in: registry)
        let note = resolution.readings.isEmpty ? nil : resolution.readings.joined(separator: ", ")

        if resolution.units.values.contains(where: { !$0.category.allowsArithmetic }) {
            return convertAffine(body, to: targetTokens, units: resolution.units).map { amount, unit in
                let (display, copyText) = Format.both { Format.quantity(amount, unit: unit.symbol, grouping: $0) }
                return Calculation(expression: expression, value: amount, display: display, copyText: copyText, note: note)
            }
        }

        var target: UnitExpression?
        if let targetTokens {
            var parser = Parser(tokens: targetTokens, units: resolution.units)
            guard let unit = parser.unitExpression(), parser.isAtEnd else { return nil }
            target = unit
        }
        var parser = Parser(tokens: body, units: resolution.units)
        guard let result = parser.parse(), parser.isAtEnd,
              parser.operations > 0 || target != nil,
              result.value.isFinite else { return nil }
        // Snap float noise like sin(pi) = 1.2e-16 to 0, which also avoids "-0".
        let value = abs(result.value) < 1e-15 ? 0 : result.value
        guard let (display, copyText) = Format.result(value, result.dimension, target: target,
                                                      usedUnits: parser.usedUnits, registry: registry) else {
            return nil
        }
        return Calculation(expression: expression, value: value, display: display, copyText: copyText, note: note)
    }

    /// Splits "1.5 GB in MB" into the body and the target ("MB"), at the last `in`/`to`
    /// followed by something shaped like a unit: words, `/`, and `^` with a number. So
    /// "5 in in cm" is inches to centimetres, and a trailing "in" is just inches.
    private static func splitConversion(_ tokens: [Token]) -> ([Token], [Token]?) {
        for k in stride(from: tokens.count - 2, through: 1, by: -1) {
            guard let keyword = tokens[k].word?.lowercased(), keyword == "in" || keyword == "to" else { continue }
            let rest = Array(tokens[(k + 1)...])
            if isUnitShaped(rest) {
                return (Array(tokens[..<k]), rest)
            }
        }
        return (tokens, nil)
    }

    private static func isUnitShaped(_ tokens: [Token]) -> Bool {
        var expectsWord = true
        var i = 0
        while i < tokens.count {
            if expectsWord {
                guard tokens[i].word != nil else { return false }
                expectsWord = false
            } else if tokens[i] == .power, i + 1 < tokens.count, case .number = tokens[i + 1] {
                i += 1
            } else if tokens[i] == .divide {
                expectsWord = true
            } else {
                return false
            }
            i += 1
        }
        return !expectsWord
    }

    /// "30 C in F": an optionally negative number, one affine unit, and a target of the
    /// same category. Anything else involving these units isn't supported.
    private static func convertAffine(_ body: [Token], to target: [Token]?,
                                      units: [String: Candidate]) -> (Double, UnitDef)? {
        var body = body[...]
        let sign: Double = body.first == .minus ? -1 : 1
        if sign < 0 { body = body.dropFirst() }
        guard body.count == 2, case .number(let amount) = body.first,
              let fromWord = body.last?.word, let from = units[fromWord],
              let target, target.count == 1, let toWord = target[0].word, let to = units[toWord],
              from.category.id == to.category.id else { return nil }
        let base = sign * amount * from.unit.factor + from.unit.offset
        return ((base - to.unit.offset) / to.unit.factor, to.unit)
    }
}
