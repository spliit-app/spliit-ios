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
    /// How many digits the stored integer keeps behind the decimal point. Two nearly
    /// everywhere, so `1234` is 12.34 — but none for the yen, where `1234` is ¥1,234, and three
    /// for the Gulf dinars. Only an ISO code can say which; a group with a bare symbol is
    /// assumed to be in hundredths, because that is what it was stored as.
    public let minorUnitDigits: Int

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

        // Setting the symbol keeps the locale's placement and separators while showing what
        // the group actually uses. An ISO code, when present, also fixes the spacing rules —
        // and the fraction digits, which is why they are not pinned to two alongside it.
        if let currencyCode, currencyCode.count == 3 {
            formatter.currencyCode = currencyCode
        } else {
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
        }
        formatter.currencySymbol = currencySymbol

        self.minorUnitDigits = formatter.maximumFractionDigits
        self.formatter = formatter
    }

    public convenience init(group currency: String, code: String?, locale: Locale = .autoupdatingCurrent) {
        self.init(currencySymbol: currency, currencyCode: code, locale: locale)
    }

    /// A formatter with no currency of its own, for the plain numbers an input field holds in a
    /// group whose precision is already known.
    public init(minorUnitDigits: Int, locale: Locale = .autoupdatingCurrent) {
        self.currencySymbol = ""
        self.currencyCode = nil
        self.locale = locale
        self.minorUnitDigits = minorUnitDigits

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.minimumFractionDigits = minorUnitDigits
        formatter.maximumFractionDigits = minorUnitDigits
        formatter.currencySymbol = ""
        self.formatter = formatter
    }

    /// Digits in the minor unit of a currency, without needing a formatter of your own.
    public static func minorUnitDigits(
        forCurrencyCode code: String?,
        locale: Locale = .autoupdatingCurrent
    ) -> Int {
        MoneyFormatter(currencySymbol: "", currencyCode: code, locale: locale).minorUnitDigits
    }

    /// - Parameter minorUnits: the value as stored, e.g. `1234` for 12.34 in a currency with
    ///   two decimal places, or ¥1,234 in one with none.
    public func string(minorUnits: Int) -> String {
        let amount = decimal(fromMinorUnits: minorUnits)
        return formatter.string(from: amount as NSDecimalNumber)
            ?? "\(currencySymbol)\(amount)"
    }

    /// The amount without its currency symbol — for inputs and axis labels.
    public func plainString(minorUnits: Int) -> String {
        decimal(fromMinorUnits: minorUnits).formatted(
            .number.precision(.fractionLength(minorUnitDigits)).grouping(.never).locale(locale)
        )
    }

    private func decimal(fromMinorUnits value: Int) -> Decimal {
        // `magnitude` rather than `abs`, which traps on `Int.min` — a number no amount will
        // ever be, but not one worth a crash if it ever is.
        Decimal(
            sign: value < 0 ? .minus : .plus,
            exponent: -minorUnitDigits,
            significand: Decimal(value.magnitude)
        )
    }

    /// Parses what someone typed into an amount field back into minor units.
    ///
    /// Accepts the locale's decimal separator as well as a plain dot, since keyboards and
    /// pasted values disagree often enough to matter.
    ///
    /// - Parameter minorUnitDigits: what to scale by, from the group's currency. The default
    ///   suits a share count or a percentage, which the protocol scales by 100 whatever the
    ///   group is denominated in.
    public static func minorUnits(
        from text: String,
        locale: Locale = .autoupdatingCurrent,
        minorUnitDigits: Int = 2
    ) -> Int? {
        guard let value = number(from: text, locale: locale) else { return nil }
        let scaled = value * pow(Decimal(10), minorUnitDigits)
        guard !scaled.isNaN, scaled > Decimal(Int.min), scaled < Decimal(Int.max) else { return nil }
        return roundToInteger(scaled)
    }

    /// The number or arithmetic expression someone typed, unscaled.
    ///
    /// A conversion rate is the one of those the form has: 1.0575 is a rate and not a hundredth
    /// of anything, so it must not go through the minor-unit scaling above.
    public static func number(from text: String, locale: Locale = .autoupdatingCurrent) -> Decimal? {
        let separator = locale.decimalSeparator ?? "."
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: separator, with: ".")
        cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
        cleaned = cleaned.replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-")
        // Keep pasted currency symbols working, without discarding invalid expression text.
        cleaned = String(cleaned.unicodeScalars.filter { $0.properties.generalCategory != .currencySymbol })
        // Bound nesting and work for pasted expressions as well as keyboard input.
        guard !cleaned.isEmpty, cleaned.count <= 512 else { return nil }
        let parser = AmountExpression(cleaned)
        guard let value = parser.sum(), parser.scanner.isAtEnd, !value.isNaN else { return nil }
        return value
    }

    /// Resolve only calculations; leave plain numbers and unfinished input as typed.
    public static func calculatedText(
        from text: String, locale: Locale = .autoupdatingCurrent, minorUnitDigits: Int = 2
    ) -> String? {
        guard text.contains(where: { "+-*/×÷−()".contains($0) }),
              let value = minorUnits(from: text, locale: locale, minorUnitDigits: minorUnitDigits)
        else { return nil }
        return MoneyFormatter(minorUnitDigits: minorUnitDigits, locale: locale).plainString(minorUnits: value)
    }

    static func roundToInteger(_ value: Decimal) -> Int {
        (value as NSDecimalNumber).rounding(accordingToBehavior: NSDecimalNumberHandler(
            roundingMode: .plain, scale: 0,
            raiseOnExactness: false, raiseOnOverflow: false,
            raiseOnUnderflow: false, raiseOnDivideByZero: false
        )).intValue
    }
}

/// Decimal arithmetic, with multiplication/division before addition/subtraction.
/// The scanner must consume the entire input so a typo can never save a partial amount.
private struct AmountExpression {
    let scanner: Scanner

    init(_ text: String) {
        scanner = Scanner(string: text)
    }

    func sum() -> Decimal? {
        guard var value = product() else { return nil }
        while true {
            if scanner.scanString("+") != nil {
                guard let next = product() else { return nil }
                value += next
            } else if scanner.scanString("-") != nil {
                guard let next = product() else { return nil }
                value -= next
            } else {
                return value.isNaN ? nil : value
            }
        }
    }

    private func product() -> Decimal? {
        guard var value = operand() else { return nil }
        while true {
            if scanner.scanString("*") != nil {
                guard let next = operand() else { return nil }
                value *= next
            } else if scanner.scanString("/") != nil {
                guard let next = operand(), next != 0 else { return nil }
                value /= next
            } else {
                return value.isNaN ? nil : value
            }
        }
    }

    private func operand() -> Decimal? {
        let negative = scanner.scanString("-") != nil
        if !negative { _ = scanner.scanString("+") }
        let value: Decimal
        if scanner.scanString("(") != nil {
            guard let inner = sum(), scanner.scanString(")") != nil else { return nil }
            value = inner
        } else {
            guard let token = scanner.scanCharacters(from: CharacterSet(charactersIn: "0123456789.")),
                  token.filter({ $0 == "." }).count <= 1,
                  token.contains(where: { $0.isNumber }),
                  let number = Decimal(string: token, locale: Locale(identifier: "en_US_POSIX"))
            else { return nil }
            value = number
        }
        return negative ? -value : value
    }
}
