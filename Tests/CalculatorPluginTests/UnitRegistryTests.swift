import Testing
@testable import CalculatorPlugin

struct UnitRegistryTests {
    @Test func builtInTablesHaveNoProblems() {
        #expect(UnitRegistry.builtIn.problems() == [])
    }

    @Test func problemsCatchClashesWithoutADefault() {
        let a = UnitCategory(id: "a", dimension: .none, units: [UnitDef("q", "q", 1, exact: ["q"])])
        let b = UnitCategory(id: "b", dimension: Dimension(.mass), units: [UnitDef("Q", "q", 1, aliases: ["q"])])
        #expect(UnitRegistry(categories: [a, b], defaults: [:]).problems() == ["\"q\" means a, b and has no default"])
        #expect(UnitRegistry(categories: [a, b], defaults: ["q": "b"]).problems() == [])
    }

    @Test func problemsCatchReservedWordsAndBadLadders() {
        let bad = UnitCategory(id: "bad", dimension: .none, units: [UnitDef("e", "e", 1, exact: ["e"])], ladder: ["nope"])
        #expect(UnitRegistry(categories: [bad], defaults: [:]).problems() == [
            "bad: ladder names unknown unit \"nope\"",
            "\"e\" is a unit and also a function, constant, or keyword",
        ])
    }
}
