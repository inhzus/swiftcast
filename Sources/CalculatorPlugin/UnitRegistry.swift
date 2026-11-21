/// One unit, such as "km" or "MiB". Amounts are stored in the category's base unit
/// (metres, grams, seconds, bytes, kelvin), so converting is a multiply and a divide.
struct UnitDef: Sendable {
    /// Shown in results: "km", "MB", "°C".
    let symbol: String
    /// Spelled out when a word was ambiguous: "B = bytes".
    let name: String
    /// Base units in one of this unit.
    let factor: Double
    /// For affine units like °C: base = amount × factor + offset.
    let offset: Double
    /// Spellings matched ignoring case.
    let aliases: [String]
    /// Spellings matched only as typed, for cases where case carries meaning ("Mb", "M", "m").
    let exactAliases: [String]

    init(_ symbol: String, _ name: String, _ factor: Double, offset: Double = 0,
         aliases: [String] = [], exact: [String] = []) {
        self.symbol = symbol
        self.name = name
        self.factor = factor
        self.offset = offset
        self.aliases = aliases
        self.exactAliases = exact
    }
}

/// A family of interchangeable units, declared in `Units/`. Adding a unit is one row in
/// `units`; adding a category is one new file plus an entry in `UnitRegistry.builtIn`.
struct UnitCategory: Sendable {
    let id: String
    let dimension: Dimension
    let units: [UnitDef]
    /// Symbols to pick a readable unit from when no target is given, smallest first.
    var ladder: [String] = []
    /// Always pick from `ladder` rather than reuse a unit from the query: "10000 * 10MB" is
    /// "97.66 GB", not "1,000,000 MB".
    var alwaysUsesLadder = false
    /// `false` for affine units (temperature): plain conversions only, no arithmetic.
    var allowsArithmetic = true

    func unit(_ symbol: String) -> UnitDef? {
        units.first { $0.symbol == symbol }
    }

    /// `value` in the largest ladder unit that keeps the amount at least 1.
    func readable(_ value: Double) -> (amount: Double, unit: UnitDef)? {
        let steps = ladder.compactMap(unit)
        guard var best = steps.first else { return nil }
        for step in steps.dropFirst() where abs(value) >= step.factor {
            best = step
        }
        return (value / best.factor, best)
    }
}

/// A reading of a word as a unit.
struct Candidate: Sendable {
    let unit: UnitDef
    let category: UnitCategory
}

/// Every known unit, indexed by spelling. Immutable: a change (e.g. new currency rates)
/// builds a new registry.
struct UnitRegistry: Sendable {
    let categories: [UnitCategory]
    /// For words that more than one category claims, which one wins when nothing in the
    /// query says otherwise. `problems()` requires an entry for every such word.
    let defaults: [String: String]

    private var exactIndex: [String: [(category: Int, unit: Int)]] = [:]
    private var foldedIndex: [String: [(category: Int, unit: Int)]] = [:]

    static let builtIn = UnitRegistry(
        categories: [.dataSize, .count, .length, .area, .volume, .mass, .time, .speed, .temperature],
        defaults: ["B": "data", "K": "count"]
    )

    init(categories: [UnitCategory], defaults: [String: String]) {
        self.categories = categories
        self.defaults = defaults
        for (c, category) in categories.enumerated() {
            for (u, unit) in category.units.enumerated() {
                for alias in unit.exactAliases { exactIndex[alias, default: []].append((c, u)) }
                for alias in unit.aliases { foldedIndex[alias.lowercased(), default: []].append((c, u)) }
            }
        }
    }

    /// Every reading of `word`, at most one per category. Within a category an exact-case
    /// spelling beats a case-insensitive one, so "Mb" is megabits while "mb" is megabytes.
    func candidates(for word: String) -> [Candidate] {
        let exact = exactIndex[word] ?? []
        let folded = (foldedIndex[word.lowercased()] ?? []).filter { hit in
            !exact.contains { $0.category == hit.category }
        }
        return (exact + folded)
            .sorted { $0.category < $1.category }
            .map { Candidate(unit: categories[$0.category].units[$0.unit], category: categories[$0.category]) }
    }

    /// The candidate to use for an ambiguous word when the query doesn't decide.
    func preferred(_ word: String, among candidates: [Candidate]) -> Candidate {
        candidates.first { $0.category.id == defaults[word] } ?? candidates[0]
    }

    func category(for dimension: Dimension) -> UnitCategory? {
        categories.first { $0.dimension == dimension }
    }

    /// Mistakes in the unit tables, for a test to catch before they reach a user: clashing
    /// spellings with no default, spellings that shadow functions or constants, and ladder
    /// entries that name no unit.
    func problems() -> [String] {
        var problems: [String] = []
        var spellings = Set<String>()
        for category in categories {
            var seenExact = Set<String>()
            var seenFolded = Set<String>()
            for unit in category.units {
                for alias in unit.exactAliases {
                    if !seenExact.insert(alias).inserted { problems.append("\(category.id): \"\(alias)\" is listed twice") }
                    spellings.insert(alias)
                }
                for alias in unit.aliases {
                    if !seenFolded.insert(alias.lowercased()).inserted { problems.append("\(category.id): \"\(alias)\" is listed twice") }
                    spellings.formUnion([alias, alias.lowercased(), alias.uppercased(), alias.capitalized])
                }
            }
            for symbol in category.ladder where category.unit(symbol) == nil {
                problems.append("\(category.id): ladder names unknown unit \"\(symbol)\"")
            }
        }
        for spelling in spellings.sorted() {
            if Parser.reservedWords.contains(spelling.lowercased()) {
                problems.append("\"\(spelling)\" is a unit and also a function, constant, or keyword")
            }
            let readings = candidates(for: spelling)
            if readings.count > 1, !readings.contains(where: { $0.category.id == defaults[spelling] }) {
                let ids = readings.map(\.category.id).joined(separator: ", ")
                problems.append("\"\(spelling)\" means \(ids) and has no default")
            }
        }
        return problems
    }
}
