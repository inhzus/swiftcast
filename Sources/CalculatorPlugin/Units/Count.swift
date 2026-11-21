extension UnitCategory {
    /// Plain multipliers: "1.2M * 3", "1B in M". No dimension, so they mix freely with
    /// plain numbers, and results show the full number unless a target is given.
    static let count = UnitCategory(id: "count", dimension: .none, units: [
        UnitDef("K", "thousand", 1e3, aliases: ["thousand"], exact: ["K", "k"]),
        UnitDef("M", "million", 1e6, aliases: ["million", "mn"], exact: ["M"]),
        UnitDef("B", "billion", 1e9, aliases: ["billion", "bn"], exact: ["B"]),
        UnitDef("T", "trillion", 1e12, aliases: ["trillion", "tn"], exact: ["T"]),
    ])
}
