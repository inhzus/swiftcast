extension UnitCategory {
    /// Base unit: seconds. A year is 365.25 days.
    static let time = UnitCategory(id: "time", dimension: Dimension(.time), units: [
        UnitDef("ms", "milliseconds", 1e-3, aliases: ["ms", "millisecond", "milliseconds"]),
        UnitDef("s", "seconds", 1, aliases: ["s", "sec", "secs", "second", "seconds"]),
        UnitDef("min", "minutes", 60, aliases: ["min", "mins", "minute", "minutes"]),
        UnitDef("h", "hours", 3600, aliases: ["h", "hr", "hrs", "hour", "hours"]),
        UnitDef("d", "days", 86400, aliases: ["d", "day", "days"]),
        UnitDef("wk", "weeks", 604_800, aliases: ["wk", "week", "weeks"]),
        UnitDef("yr", "years", 31_557_600, aliases: ["yr", "year", "years"]),
    ], ladder: ["ms", "s", "min", "h", "d"])

    /// Base unit: metres per second. Compound speeds like "km/h" and "m/s" also work
    /// through dimension math; these are the names that don't split.
    static let speed = UnitCategory(id: "speed", dimension: Dimension(.length) / Dimension(.time), units: [
        UnitDef("km/h", "kilometres per hour", 1 / 3.6, aliases: ["kph", "kmh"]),
        UnitDef("mph", "miles per hour", 0.44704, aliases: ["mph"]),
        UnitDef("kn", "knots", 1852.0 / 3600, aliases: ["kn", "knot", "knots"]),
    ], ladder: ["km/h"])
}
