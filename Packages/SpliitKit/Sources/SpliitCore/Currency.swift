import Foundation

/// An ISO-4217 currency, as the system already knows it.
///
/// The list, the names, the symbols and the minor-unit precision all come from Foundation, so
/// the picker is translated wherever iOS is and there is no currency table in the repo to keep
/// up to date. The web app ships a generated JSON for exactly this and has to regenerate it;
/// the platform hands it over for free.
public struct Currency: Identifiable, Hashable, Sendable {

    /// ISO-4217, uppercase — "CHF".
    public let code: String
    /// Localised — "Swiss Franc", "franc suisse".
    public let name: String
    /// What amounts are shown with — "CHF", "$", "kr". This is what gets stored as the group's
    /// free-text `currency`, so it follows the user's locale the way the web app's does.
    public let symbol: String
    /// Digits in the minor unit: two nearly everywhere, none for the yen, three for the dinars.
    /// A fifth of the currencies here are not two, so this cannot be assumed.
    public let minorUnitDigits: Int

    public var id: String { code }

    public init(code: String, name: String, symbol: String, minorUnitDigits: Int) {
        self.code = code
        self.name = name
        self.symbol = symbol
        self.minorUnitDigits = minorUnitDigits
    }

    /// The flag of the country the code belongs to, when there is one.
    ///
    /// ISO-4217 codes start with the ISO-3166 country code, which is what makes this possible —
    /// but only for currencies that belong to a country. The supranational ones ("XPF", "XDR")
    /// have no flag and get none rather than a pair of unrelated letter tiles.
    public var flag: String? {
        let region = String(code.prefix(2)).uppercased()
        guard Self.isoRegions.contains(region) else { return nil }
        return String(String.UnicodeScalarView(region.unicodeScalars.compactMap {
            UnicodeScalar(0x1F1E6 - 65 + $0.value)
        }))
    }

    /// Whether this currency answers a search, matching on anything a user might type: the
    /// name, the code, or the symbol.
    public func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return name.range(of: query, options: options) != nil
            || code.range(of: query, options: options) != nil
            || symbol.range(of: query, options: options) != nil
    }

    private static let isoRegions = Set(Locale.Region.isoRegions.map(\.identifier))
}

extension Currency {

    /// Every currency the system can name, ordered the way the user's language orders words.
    ///
    /// Built once per locale and kept: a form holding the picker constructs it on every body
    /// pass — on every keystroke in the field above it — and walking the ISO list costs
    /// milliseconds each time.
    public static func all(in locale: Locale = .autoupdatingCurrent) -> [Currency] {
        catalog.list(for: locale) {
            Locale.commonISOCurrencyCodes
                .compactMap { make($0, in: locale) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    /// One currency by code, or nil if the system can't name it — an instance that stored
    /// something that isn't a currency should not be presented as one.
    public static func named(_ code: String, in locale: Locale = .autoupdatingCurrent) -> Currency? {
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        // Nearly always a hit, and cheaper than building one. The miss is a currency outside
        // the common list, which is legal to hold even though the picker doesn't offer it.
        return all(in: locale).first { $0.code == code } ?? make(code, in: locale)
    }

    private static func make(_ code: String, in locale: Locale) -> Currency? {
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count == 3, let name = locale.localizedString(forCurrencyCode: code) else {
            return nil
        }
        return Currency(
            code: code,
            name: name,
            symbol: symbol(for: code, in: locale),
            minorUnitDigits: MoneyFormatter.minorUnitDigits(forCurrencyCode: code, locale: locale)
        )
    }

    /// The currency the device is set to, which is the one a new group most often wants.
    public static func device(in locale: Locale = .autoupdatingCurrent) -> Currency? {
        locale.currency.flatMap { named($0.identifier, in: locale) }
    }

    /// Shown above the full list: the device's own currency, then the ones groups most often
    /// use. Same five the web app promotes, so the two apps put the same names at the top.
    public static func suggested(in locale: Locale = .autoupdatingCurrent) -> [Currency] {
        var codes = ["USD", "EUR", "GBP", "JPY", "CNY"]
        if let device = device(in: locale) {
            codes.removeAll { $0 == device.code }
            codes.insert(device.code, at: 0)
        }
        return codes.compactMap { named($0, in: locale) }
    }

    /// Foundation exposes a currency's symbol only through a locale that uses it, so this asks
    /// for the user's own locale with the currency swapped in — which is also what makes the
    /// answer localised: a French phone gets "$US" for the dollar, an American one "$".
    private static func symbol(for code: String, in locale: Locale) -> String {
        var components = Locale.Components(locale: locale)
        components.currency = Locale.Currency(code)
        return Locale(components: components).currencySymbol ?? code
    }

    private static let catalog = Catalog()
}

/// Holds the built list per locale.
///
/// Keyed by identifier rather than by the locale itself, which is what makes
/// `.autoupdatingCurrent` behave: it reports the identifier it currently resolves to, so
/// changing region in Settings asks for a list under a new key instead of getting the old one.
private final class Catalog: @unchecked Sendable {

    private let lock = NSLock()
    private var lists: [String: [Currency]] = [:]

    func list(for locale: Locale, build: () -> [Currency]) -> [Currency] {
        let key = locale.identifier
        lock.lock()
        if let cached = lists[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        // Built outside the lock: two threads arriving together do the work twice and agree on
        // the answer, which is cheaper than either of them waiting.
        let built = build()
        lock.lock()
        lists[key] = built
        lock.unlock()
        return built
    }
}
