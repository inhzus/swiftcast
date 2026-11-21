import Testing
@testable import SwiftCastCore

struct CalculatorTests {
    private func display(_ input: String) -> String? {
        Calculator.evaluate(input)?.display
    }

    @Test func arithmeticPrecedenceAndAssociativity() {
        #expect(display("23*4") == "92")
        #expect(display("1 + 2 * 3") == "7")
        #expect(display("(1 + 2) * 3") == "9")
        #expect(display("10 / 4") == "2.5")
        #expect(display("2^3^2") == "512")
        #expect(display("-2^2") == "-4")
        #expect(display("2^-1") == "0.5")
        #expect(display("-(3 - 5)") == "2")
    }

    @Test func alternativeOperatorSymbols() {
        #expect(display("3 × 4") == "12")
        #expect(display("10 ÷ 4") == "2.5")
        #expect(display("2x3") == "6")
        #expect(display("2 x (1+1)") == "4")
        #expect(display("5 − 2") == "3")
    }

    @Test func percent() {
        #expect(display("200 * 15%") == "30")
        #expect(display("50%") == "0.5")
        #expect(display("200 + 10%") == "220")
        #expect(display("200 - 10%") == "180")
    }

    @Test func functionsAndConstants() {
        #expect(display("sqrt(16)") == "4")
        #expect(display("sin(pi/2)") == "1")
        #expect(display("sin(pi)") == "0")
        #expect(display("log(1000)") == "3")
        #expect(display("ln(e)") == "1")
        #expect(display("abs(-3) + round(2.6)") == "6")
        #expect(display("2 * π") == "6.28318530718")
        #expect(display("sqrt(2)") == "1.41421356237")
    }

    @Test func formatting() {
        let big = Calculator.evaluate("1234567 + 0.5")
        #expect(big?.display == "1,234,567.5")
        #expect(big?.copyText == "1234567.5")
        #expect(display("10^20 * 2") == "2e20")
        #expect(display("2^60") == "1.152921505e18")
        #expect(display("1/3 * 10^-12") == "3.333333333e-13")
    }

    @Test func nonMathIsNotHijacked() {
        for input in ["safari", "1password", "2048", "e", "pi", "(1+2", "1/0", "2,5+1", "10MB", "", "-5", "System Settings", "微信"] {
            #expect(Calculator.evaluate(input) == nil, "\(input)")
        }
    }

    @Test func dataSizes() {
        #expect(display("10000 * 10MB") == "97.66 GB")
        #expect(display("1gb + 512mb") == "1.5 GB")
        #expect(display("2GB / 512MB") == "4")
        #expect(display("1GB + 10%") == "1.1 GB")
        #expect(display("1KiB * 2") == "2 KB")
        #expect(display("256B * 2") == "512 B")
        #expect(display("100 Mb in MB") == "12.5 MB")
        #expect(display("1 GB to Mb") == "8,192 Mb")
        #expect(display("1.5 GB in MB") == "1,536 MB")
        #expect(display("1 KB in GB") == "0.000000954 GB")
        #expect(Calculator.evaluate("10000 * 10MB")?.copyText == "97.66 GB")
        #expect(Calculator.evaluate("1.5 GB in MB")?.copyText == "1536 MB")
    }

    @Test func invalidSizeMath() {
        for input in ["1GB + 1", "1GB * 1GB", "5 in MB", "2^1GB", "sqrt(4GB)", "10% in MB"] {
            #expect(Calculator.evaluate(input) == nil, "\(input)")
        }
    }
}
