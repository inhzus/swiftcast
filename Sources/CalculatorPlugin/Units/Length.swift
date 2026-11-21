extension UnitCategory {
    /// Base unit: metres. "m" is case-sensitive, since "M" is a million.
    static let length = UnitCategory(id: "length", dimension: Dimension(.length), units: [
        UnitDef("nm", "nanometres", 1e-9, aliases: ["nm"]),
        UnitDef("µm", "micrometres", 1e-6, aliases: ["µm", "um"]),
        UnitDef("mm", "millimetres", 1e-3, aliases: ["mm"]),
        UnitDef("cm", "centimetres", 1e-2, aliases: ["cm"]),
        UnitDef("m", "metres", 1, aliases: ["metre", "metres", "meter", "meters"], exact: ["m"]),
        UnitDef("km", "kilometres", 1e3, aliases: ["km"]),
        UnitDef("in", "inches", 0.0254, aliases: ["in", "inch", "inches"]),
        UnitDef("ft", "feet", 0.3048, aliases: ["ft", "foot", "feet"]),
        UnitDef("yd", "yards", 0.9144, aliases: ["yd", "yard", "yards"]),
        UnitDef("mi", "miles", 1609.344, aliases: ["mi", "mile", "miles"]),
    ], ladder: ["mm", "cm", "m", "km"])

    /// Base unit: square metres. "m^2" also works, through dimension math.
    static let area = UnitCategory(id: "area", dimension: Dimension(.length, 2), units: [
        UnitDef("cm²", "square centimetres", 1e-4, aliases: ["cm²"]),
        UnitDef("m²", "square metres", 1, aliases: ["m²", "sqm"]),
        UnitDef("km²", "square kilometres", 1e6, aliases: ["km²"]),
        UnitDef("ha", "hectares", 1e4, aliases: ["ha", "hectare", "hectares"]),
        UnitDef("acre", "acres", 4046.8564224, aliases: ["acre", "acres"]),
    ], ladder: ["cm²", "m²", "km²"])

    /// Base unit: cubic metres.
    static let volume = UnitCategory(id: "volume", dimension: Dimension(.length, 3), units: [
        UnitDef("mL", "millilitres", 1e-6, aliases: ["ml", "millilitre", "millilitres", "milliliter", "milliliters"]),
        UnitDef("L", "litres", 1e-3, aliases: ["l", "litre", "litres", "liter", "liters"]),
        UnitDef("m³", "cubic metres", 1, aliases: ["m³"]),
        UnitDef("gal", "US gallons", 0.003785411784, aliases: ["gal", "gallon", "gallons"]),
    ], ladder: ["mL", "L"])
}
