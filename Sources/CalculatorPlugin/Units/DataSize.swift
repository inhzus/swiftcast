import Foundation

extension UnitCategory {
    /// Bytes and bits. Prefixes are powers of 1024, so KB and KiB are the same size. Byte
    /// units ignore case ("mb" is megabytes); bits are "bit(s)", "Mbit", or an uppercase
    /// prefix with a lowercase "b" ("Mb").
    static let dataSize: UnitCategory = {
        var units = [
            UnitDef("B", "bytes", 1, aliases: ["b", "byte", "bytes"]),
            UnitDef("bit", "bits", 1.0 / 8, aliases: ["bit", "bits"]),
        ]
        let prefixes = [("K", "kilo"), ("M", "mega"), ("G", "giga"), ("T", "tera"), ("P", "peta")]
        for (power, (prefix, name)) in prefixes.enumerated() {
            let scale = pow(1024, Double(power + 1))
            let lower = prefix.lowercased()
            units += [
                UnitDef(prefix + "B", name + "bytes", scale, aliases: [lower + "b"]),
                UnitDef(prefix + "iB", name + "bytes", scale, aliases: [lower + "ib"]),
                UnitDef(prefix + "b", name + "bits", scale / 8, exact: [prefix + "b"]),
                UnitDef(prefix + "bit", name + "bits", scale / 8, aliases: [lower + "bit", lower + "bits"]),
            ]
        }
        return UnitCategory(id: "data", dimension: Dimension(.data), units: units,
                            ladder: ["B", "KB", "MB", "GB", "TB", "PB"], alwaysUsesLadder: true)
    }()
}
