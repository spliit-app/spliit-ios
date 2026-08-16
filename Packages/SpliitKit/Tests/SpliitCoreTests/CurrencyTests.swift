import Foundation
import Testing

@testable import SpliitCore

/// The currency list comes from the system rather than from a table in the repo, so these
/// pin down what we rely on it for: names, symbols, minor units, and an order.
@Suite("Currencies")
struct CurrencyTests {

    private let english = Locale(identifier: "en_US")

    @Test("Currencies are named, symbolised and sorted for the user's language")
    func buildsTheList() {
        let currencies = Currency.all(in: english)

        #expect(currencies.count > 100)
        #expect(currencies.contains { $0.code == "CHF" })
        #expect(currencies.allSatisfy { $0.code.count == 3 })
        #expect(currencies.allSatisfy { !$0.name.isEmpty && !$0.symbol.isEmpty })

        let names = currencies.map(\.name)
        #expect(names == names.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }

    @Test("A currency knows its name and its symbol")
    func describesOneCurrency() throws {
        let swiss = try #require(Currency.named("CHF", in: english))

        #expect(swiss.name == "Swiss Franc")
        #expect(swiss.symbol == "CHF")
        #expect(swiss.minorUnitDigits == 2)
    }

    /// The symbol is what gets stored as the group's `currency`, and the language decides it:
    /// an American writes the dollar "$", a French speaker "$US".
    @Test("Names and symbols follow the user's language")
    func localisesToTheUser() throws {
        let french = try #require(Currency.named("USD", in: Locale(identifier: "fr_FR")))

        #expect(french.name == "dollar des États-Unis")
        #expect(french.symbol == "$US")
    }

    @Test("Minor units are not two everywhere")
    func knowsMinorUnits() throws {
        #expect(try #require(Currency.named("USD", in: english)).minorUnitDigits == 2)
        #expect(try #require(Currency.named("JPY", in: english)).minorUnitDigits == 0)
        #expect(try #require(Currency.named("KWD", in: english)).minorUnitDigits == 3)
    }

    @Test("Anything that isn't a currency code isn't a currency")
    func rejectsNonCurrencies() {
        #expect(Currency.named("") == nil)
        #expect(Currency.named("US") == nil)
        #expect(Currency.named("DOLLARS") == nil)
        #expect(Currency.named("ZZZ") == nil)
    }

    @Test("A code is accepted however it was stored")
    func normalisesCodes() {
        #expect(Currency.named("chf", in: english)?.code == "CHF")
        #expect(Currency.named(" EUR ", in: english)?.code == "EUR")
    }

    /// The two-letter prefix of an ISO-4217 code is the country it belongs to, which is what
    /// makes a flag possible at all — and the supranational currencies have no country.
    @Test("Currencies of a country get its flag, the rest get none")
    func showsFlags() {
        #expect(Currency.named("CHF", in: english)?.flag == "🇨🇭")
        #expect(Currency.named("EUR", in: english)?.flag == "🇪🇺")
        #expect(Currency.named("XPF", in: english)?.flag == nil)
    }

    @Test("Search matches the name, the code or the symbol")
    func searches() throws {
        let swiss = try #require(Currency.named("CHF", in: english))

        #expect(swiss.matches("swiss"))
        #expect(swiss.matches("FRA"))
        #expect(swiss.matches("chf"))
        #expect(swiss.matches(""))
        #expect(!swiss.matches("peso"))
    }

    @Test("Accents in the name don't have to be typed")
    func searchesWithoutDiacritics() throws {
        let icelandic = try #require(Currency.named("ISK", in: english))

        #expect(icelandic.name == "Icelandic Króna")
        #expect(icelandic.matches("krona"))
    }

    @Test("The device's own currency is suggested first")
    func suggestsTheDeviceCurrency() {
        let swiss = Currency.suggested(in: Locale(identifier: "de_CH"))

        #expect(swiss.first?.code == "CHF")
        #expect(Set(swiss.map(\.code)) == ["CHF", "USD", "EUR", "GBP", "JPY", "CNY"])

        // And it isn't listed twice when it is already one of the common ones.
        let american = Currency.suggested(in: english)
        #expect(american.first?.code == "USD")
        #expect(american.count == 5)
    }
}
