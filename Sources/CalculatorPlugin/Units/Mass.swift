extension UnitCategory {
    /// Base unit: grams. "t" is case-sensitive, since "T" is a trillion.
    static let mass = UnitCategory(id: "mass", dimension: Dimension(.mass), units: [
        UnitDef("mg", "milligrams", 1e-3, aliases: ["mg", "milligram", "milligrams"]),
        UnitDef("g", "grams", 1, aliases: ["g", "gram", "grams"]),
        UnitDef("kg", "kilograms", 1e3, aliases: ["kg", "kilo", "kilos", "kilogram", "kilograms"]),
        UnitDef("t", "tonnes", 1e6, aliases: ["tonne", "tonnes"], exact: ["t"]),
        UnitDef("oz", "ounces", 28.349523125, aliases: ["oz", "ounce", "ounces"]),
        UnitDef("lb", "pounds", 453.59237, aliases: ["lb", "lbs", "pound", "pounds"]),
    ], ladder: ["mg", "g", "kg", "t"])
}
