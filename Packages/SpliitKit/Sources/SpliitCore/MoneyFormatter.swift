import Foundation

/// Formats the integer minor units the API deals in.
///
/// A group's currency is a free-text symbol — "$", "CHF", "kr" — and only newer groups also
/// carry an ISO code. The old app worked around that by formatting as euros in `en-US` and
/// swapping the sign, which put every user on American conventions. Here the user's own locale
/// decides grouping, decimal separator and symbol placement, and the group's symbol is
/// substituted into that.
public final class MoneyFormatter: @unchecked Sendable {

    public let currencySymbol: String
    public let currencyCode: String?
    public let locale: Locale

    // `NumberFormatter` is documented as thread-safe for formatting, and this one is never
    // mutated after init, so sharing it across isolation domains is sound.
    private let formatter: NumberFormatter

    public init(currencySymbol: String, currencyCode: String? = nil, locale: Locale = .autoupdatingCurrent) {
        self.currencySymbol = currencySymbol
        self.currencyCode = currencyCode
        self.locale = locale

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2

        // Setting the symbol keeps the locale's placement and separators while showing what
        // the group actually uses. An ISO code, when present, also fixes the spacing rules.
        if let currencyCode, currencyCode.count == 3 {
            formatter.currencyCode = currencyCode
        }
        formatter.currencySymbol = currencySymbol
        self.formatter = formatter
    }

    public convenience init(group currency: String, code: String?, locale: Locale = .autoupdatingCurrent) {
        self.init(currencySymbol: currency, currencyCode: code, locale: locale)
    }

    /// - Parameter minorUnits: the value as stored, e.g. `1234` for 12.34.
    public func string(minorUnits: Int) -> String {
        let amount = Decimal(minorUnits) / 100
        return formatter.string(from: amount as NSDecimalNumber)
            ?? "\(currencySymbol)\(amount)"
    }

    /// The amount without its currency symbol — for inputs and axis labels.
    public func plainString(minorUnits: Int) -> String {
        let amount = Decimal(minorUnits) / 100
        return amount.formatted(
            .number.precision(.fractionLength(2)).grouping(.never).locale(locale)
        )
    }

    /// Parses what someone typed into an amount field back into minor units.
    ///
    /// Accepts the locale's decimal separator as well as a plain dot, since keyboards and
    /// pasted values disagree often enough to matter.
    public static func minorUnits(from text: String, locale: Locale = .autoupdatingCurrent) -> Int? {
        let separator = locale.decimalSeparator ?? "."
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: separator, with: ".")
        cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
        cleaned = cleaned.filter { $0.isNumber || $0 == "." || $0 == "-" }

        guard !cleaned.isEmpty, let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
        else {
            return nil
        }

        let scaled = (value * 100) as NSDecimalNumber
        let rounded = scaled.rounding(accordingToBehavior: NSDecimalNumberHandler(
            roundingMode: .plain, scale: 0,
            raiseOnExactness: false, raiseOnOverflow: false,
            raiseOnUnderflow: false, raiseOnDivideByZero: false
        ))
        return rounded.intValue
    }
}
