import Testing
@testable import CalculatorPlugin

/// Pins the one rule for ambiguous words: an anchored category wins, otherwise the default.
struct UnitResolverTests {
    private func result(_ input: String) -> (String?, String?) {
        let calculation = Calculator.evaluate(input)
        return (calculation?.display, calculation?.note)
    }

    @Test func bareBIsBytesUnlessACountUnitAnchorsIt() {
        #expect(result("256B * 2") == ("512 B", "B = bytes"))
        #expect(result("2B * 3") == ("6 B", "B = bytes"))
        #expect(result("1B in M") == ("1,000 M", "B = billion"))
        #expect(result("1B + 500M") == ("1,500,000,000", "B = billion"))
        #expect(result("1B in KB") == ("0.000977 KB", "B = bytes"))
    }

    @Test func bothKindsAnchoredFallsBackToTheDefault() {
        // KB anchors data and M anchors count, so neither wins and B takes its default.
        #expect(result("2B * 1M in KB") == ("1,953.12 KB", "B = bytes"))
    }

    @Test func ambiguousWordsSharingOneCategoryTakeIt() {
        // B is bytes or billion, K is thousand or kelvin: the only shared reading is count.
        #expect(result("1B/1000 in K") == ("1,000 K", "B = billion, K = thousand"))
        #expect(result("2K * 1B") == ("2,000,000,000,000", "K = thousand, B = billion"))
    }

    @Test func bareKIsThousandUnlessATemperatureAnchorsIt() {
        #expect(result("5K + 1") == ("5,001", "K = thousand"))
        #expect(result("0 C in K") == ("273.15 K", "K = kelvin"))
        #expect(result("300 K in C") == ("26.85 °C", "K = kelvin"))
    }

    @Test func explicitSpellingsAreNeverAmbiguous() {
        #expect(result("2 bytes * 3") == ("6 B", nil))
        #expect(result("2 billion * 3") == ("6,000,000,000", nil))
        #expect(result("1 bn in M") == ("1,000 M", nil))
        #expect(result("1 GB in MB").1 == nil)
    }

    @Test func caseCarriesMeaningWhereConventionHasIt() {
        #expect(result("100 Mb in MB").0 == "12.5 MB")
        #expect(result("3 m * 2").0 == "6 m")
        #expect(result("3M * 2").0 == "6,000,000")
        #expect(result("2 t in kg").0 == "2,000 kg")
        #expect(result("2T / 4").0 == "500,000,000,000")
    }
}
