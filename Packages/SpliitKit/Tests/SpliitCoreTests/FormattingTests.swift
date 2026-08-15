import Foundation
import Testing

@testable import SpliitCore

@Suite("Money formatting")
struct MoneyFormatterTests {

    @Test("Minor units are rendered with the group's symbol")
    func formatsWithGroupSymbol() {
        let formatter = MoneyFormatter(
            currencySymbol: "$", currencyCode: "USD", locale: Locale(identifier: "en_US")
        )

        #expect(formatter.string(minorUnits: 4250) == "$42.50")
        #expect(formatter.string(minorUnits: 0) == "$0.00")
    }

    @Test("Two decimal places are always shown")
    func alwaysShowsCents() {
        let formatter = MoneyFormatter(
            currencySymbol: "$", currencyCode: "USD", locale: Locale(identifier: "en_US")
        )

        #expect(formatter.string(minorUnits: 100) == "$1.00")
        #expect(formatter.string(minorUnits: 105) == "$1.05")
    }

    @Test("A negative balance keeps its sign")
    func formatsNegativeAmounts() {
        let formatter = MoneyFormatter(
            currencySymbol: "$", currencyCode: "USD", locale: Locale(identifier: "en_US")
        )

        #expect(formatter.string(minorUnits: -7797).contains("77.97"))
        #expect(formatter.string(minorUnits: -7797).contains("-"))
    }

    /// The old app formatted every amount as euros in `en-US` and swapped the sign, so a
    /// French user saw "€1,234.56" instead of "1 234,56 €". The user's locale should decide
    /// separators and placement while the group decides the symbol.
    @Test("The user's locale decides separators and placement, the group decides the symbol")
    func respectsUserLocale() {
        let french = MoneyFormatter(
            currencySymbol: "€", currencyCode: "EUR", locale: Locale(identifier: "fr_FR")
        )
        let formatted = french.string(minorUnits: 123_456)

        #expect(formatted.contains("€"))
        #expect(formatted.contains("234,56"))
        #expect(formatted.hasSuffix("€"))
    }

    @Test("A group with only a symbol and no ISO code still formats")
    func formatsWithoutISOCode() {
        let formatter = MoneyFormatter(
            currencySymbol: "kr", currencyCode: nil, locale: Locale(identifier: "en_US")
        )

        #expect(formatter.string(minorUnits: 4250).contains("42.50"))
        #expect(formatter.string(minorUnits: 4250).contains("kr"))
    }

    @Test("The plain form drops the symbol, for input fields")
    func formatsWithoutSymbol() {
        let formatter = MoneyFormatter(
            currencySymbol: "$", currencyCode: "USD", locale: Locale(identifier: "en_US")
        )

        #expect(formatter.plainString(minorUnits: 123_456) == "1234.56")
    }
}

@Suite("Parsing typed amounts")
struct AmountParsingTests {

    @Test("A plain decimal becomes minor units")
    func parsesDecimal() {
        #expect(MoneyFormatter.minorUnits(from: "42.50", locale: Locale(identifier: "en_US")) == 4250)
        #expect(MoneyFormatter.minorUnits(from: "42", locale: Locale(identifier: "en_US")) == 4200)
        #expect(MoneyFormatter.minorUnits(from: "0.05", locale: Locale(identifier: "en_US")) == 5)
    }

    /// The old app shipped a fix for exactly this: a French keyboard produces a comma, and
    /// parsing it as a thousands separator turned 12,50 into 1250.00.
    @Test("A comma decimal separator is understood")
    func parsesCommaSeparator() {
        #expect(MoneyFormatter.minorUnits(from: "42,50", locale: Locale(identifier: "fr_FR")) == 4250)
        #expect(MoneyFormatter.minorUnits(from: "42.50", locale: Locale(identifier: "fr_FR")) == 4250)
    }

    @Test("A third decimal place is rounded, not truncated")
    func roundsSubCentValues() {
        #expect(MoneyFormatter.minorUnits(from: "1.005", locale: Locale(identifier: "en_US")) == 101)
        #expect(MoneyFormatter.minorUnits(from: "1.004", locale: Locale(identifier: "en_US")) == 100)
    }

    @Test("A negative amount is preserved")
    func parsesNegative() {
        #expect(MoneyFormatter.minorUnits(from: "-12.30", locale: Locale(identifier: "en_US")) == -1230)
    }

    @Test("Empty or nonsense input yields nil rather than zero")
    func rejectsUnparseableInput() {
        #expect(MoneyFormatter.minorUnits(from: "", locale: Locale(identifier: "en_US")) == nil)
        #expect(MoneyFormatter.minorUnits(from: "   ", locale: Locale(identifier: "en_US")) == nil)
        #expect(MoneyFormatter.minorUnits(from: "abc", locale: Locale(identifier: "en_US")) == nil)
    }

    @Test("A currency symbol pasted along with the number is ignored")
    func ignoresStraySymbols() {
        #expect(MoneyFormatter.minorUnits(from: "$42.50", locale: Locale(identifier: "en_US")) == 4250)
        #expect(MoneyFormatter.minorUnits(from: "42.50 €", locale: Locale(identifier: "en_US")) == 4250)
    }
}
