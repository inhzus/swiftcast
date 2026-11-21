import SwiftCastPluginKit

/// Quick math: a single row with the result of a math query, which ↩ copies.
@MainActor
public final class CalculatorPlugin: LauncherPlugin {
    public let id = "calculator"
    public let name = "Calculator"
    public let summary = "Does arithmetic and converts units as you type; ↩ copies the result."
    public let icon = ResultIcon.file(iconPath)
    public let sectionTitle = "Calculator"
    public let resultLimit = 1

    static let iconPath = "/System/Applications/Calculator.app"

    public init() {}

    public func results(for query: String) -> [ResultItem] {
        guard let calculation = Calculator.evaluate(query) else { return [] }
        return [Self.item(for: calculation)]
    }

    public func iconPaths() -> [String] {
        [Self.iconPath]
    }

    static func item(for calculation: Calculation) -> ResultItem {
        ResultItem(
            id: "result",
            title: calculation.display,
            highlightedIndices: Array(0..<calculation.display.count),
            detail: ["= " + calculation.expression, calculation.note].compactMap { $0 }.joined(separator: " · "),
            icon: .file(iconPath),
            actions: [ResultAction("Copy", .copy(calculation.copyText))],
            match: .exact
        )
    }
}
