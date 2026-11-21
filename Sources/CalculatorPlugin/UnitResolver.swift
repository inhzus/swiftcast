/// Decides what each unit word in a query means, by one rule:
///
/// 1. A word with a single reading means that, and *anchors* its category.
/// 2. A word with several readings ("B": bytes or billion) takes the one whose category is
///    anchored, if exactly one is.
/// 3. Ambiguous words still undecided that share exactly one category take it: in
///    "1B/1000 in K" both B and K can be counts, so they are billion and thousand.
/// 4. Otherwise a word takes the registry's default.
///
/// The rule looks only at which words appear, not at values or order, so a query always
/// means the same thing. Spelled-out words ("bytes", "billion") are never ambiguous.
enum UnitResolver {
    struct Resolution {
        /// The chosen reading of each word that is a unit.
        var units: [String: Candidate] = [:]
        /// How ambiguous words were read, in query order: ["B = billion"].
        var readings: [String] = []
    }

    static func resolve(_ words: [String], in registry: UnitRegistry) -> Resolution {
        var seen = Set<String>()
        let unique = words.filter { seen.insert($0).inserted }
        let candidates = unique.map { registry.candidates(for: $0) }
        let anchored = Set(candidates.filter { $0.count == 1 }.map { $0[0].category.id })

        func anchoredOption(_ options: [Candidate]) -> Candidate? {
            let inQuery = options.filter { anchored.contains($0.category.id) }
            return inQuery.count == 1 ? inQuery[0] : nil
        }
        let undecided = zip(unique, candidates).filter { $1.count > 1 && anchoredOption($1) == nil }
        let shared = undecided.count > 1
            ? undecided.dropFirst().reduce(Set(undecided[0].1.map(\.category.id))) {
                $0.intersection($1.1.map(\.category.id))
            }
            : []

        var resolution = Resolution()
        for (word, options) in zip(unique, candidates) where !options.isEmpty {
            guard options.count > 1 else {
                resolution.units[word] = options[0]
                continue
            }
            let choice = anchoredOption(options)
                ?? (shared.count == 1 ? options.first { shared.contains($0.category.id) } : nil)
                ?? registry.preferred(word, among: options)
            resolution.units[word] = choice
            resolution.readings.append("\(word) = \(choice.unit.name)")
        }
        return resolution
    }
}
