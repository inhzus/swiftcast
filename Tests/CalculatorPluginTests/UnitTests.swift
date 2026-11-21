import Testing
@testable import CalculatorPlugin

/// One table per category: adding a unit adds a row here.
struct UnitTests {
    private func check(_ cases: [(String, String)], sourceLocation: SourceLocation = #_sourceLocation) {
        for (input, expected) in cases {
            #expect(Calculator.evaluate(input)?.display == expected, "\(input)", sourceLocation: sourceLocation)
        }
    }

    @Test func count() {
        check([
            ("1B in M", "1,000 M"),
            ("1000M in B", "1 B"),
            ("1B + 500M", "1,500,000,000"),
            ("1.2M * 3", "3,600,000"),
            ("5k * 3", "15,000"),
            ("5B / 200M", "25"),
            ("25000000 in M", "25 M"),
            ("2 billion / 4", "500,000,000"),
            ("3 bn in K", "3,000,000 K"),
        ])
        #expect(Calculator.evaluate("1B + 500M")?.copyText == "1500000000")
    }

    @Test func length() {
        check([
            ("5 km in mi", "3.11 mi"),
            ("1 km + 500 m", "1.5 km"),
            ("5 ft + 3 in", "5.25 ft"),
            ("1 ft in in", "12 in"),
            ("5 in in cm", "12.7 cm"),
            ("10 cm in in", "3.94 in"),
            ("3 m * 2", "6 m"),
        ])
    }

    @Test func areaAndVolume() {
        check([
            ("5 m * 3 m", "15 m²"),
            ("2 m^2 * 3", "6 m²"),
            ("1 ha in m^2", "10,000 m²"),
            ("1 acre in m²", "4,046.86 m²"),
            ("2 L + 500 ml", "2.5 L"),
            ("1 gal in L", "3.79 L"),
            ("1 m^3 in L", "1,000 L"),
        ])
    }

    @Test func massAndTime() {
        check([
            ("2 kg in lb", "4.41 lb"),
            ("500 g * 3", "1,500 g"),
            ("1 t in kg", "1,000 kg"),
            ("90 min in h", "1.5 h"),
            ("2 h + 30 min", "2.5 h"),
            ("1 week in days", "7 d"),
        ])
    }

    @Test func compoundUnits() {
        check([
            ("1 GB / 20 MB/s", "51.2 s"),
            ("60 km/h * 2", "120 km/h"),
            ("100 km / 2 h", "50 km/h"),
            ("60 mph in km/h", "96.56 km/h"),
            ("10 m/s in km/h", "36 km/h"),
            ("2 GB / 512MB", "4"),
        ])
    }

    @Test func temperature() {
        check([
            ("30 C in F", "86 °F"),
            ("72 F to C", "22.22 °C"),
            ("-40 °C in °F", "-40 °F"),
            ("0 C in K", "273.15 K"),
            ("300 K in C", "26.85 °C"),
        ])
        for input in ["30 C + 1", "30 C", "2 * 30 C in F", "30 C in km"] {
            #expect(Calculator.evaluate(input) == nil, "\(input)")
        }
    }

    @Test func mismatchedKindsAreNotMath() {
        for input in ["5 km + 3 kg", "1 GB in km", "5 m * 3 s", "1 km", "go to Safari", "5 in"] {
            #expect(Calculator.evaluate(input) == nil, "\(input)")
        }
    }
}
