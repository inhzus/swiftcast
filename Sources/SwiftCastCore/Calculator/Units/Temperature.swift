extension UnitCategory {
    /// Base unit: kelvin. Affine, so only plain conversions ("30 C in F"), no arithmetic.
    /// "K" alone defaults to thousand unless °C or °F is in the query.
    static let temperature = UnitCategory(id: "temperature", dimension: Dimension(.temperature), units: [
        UnitDef("°C", "celsius", 1, offset: 273.15, aliases: ["c", "°c", "celsius"]),
        UnitDef("°F", "fahrenheit", 5.0 / 9, offset: 459.67 * 5 / 9, aliases: ["f", "°f", "fahrenheit"]),
        UnitDef("K", "kelvin", 1, aliases: ["kelvin", "kelvins"], exact: ["K"]),
    ], allowsArithmetic: false)
}
