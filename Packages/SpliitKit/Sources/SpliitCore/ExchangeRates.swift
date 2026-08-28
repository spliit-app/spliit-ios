import Foundation

/// A conversion rate, and the day it is actually from.
public struct ExchangeRate: Equatable, Sendable {
    /// How much of the target currency one unit of the base buys.
    public let rate: Decimal
    /// The day the rate is quoted for. Rates are published on working days only, so asking for
    /// a Sunday — or for a date in the future — answers with the last day there is one.
    public let day: String

    public init(rate: Decimal, day: String) {
        self.rate = rate
        self.day = day
    }

    /// The day as a date, so a screen can show it the way the platform shows every other date.
    public var date: Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.autoupdatingCurrent.date(
            from: DateComponents(year: parts[0], month: parts[1], day: parts[2])
        )
    }
}

/// Looks up a conversion rate, from the same source the web app uses.
///
/// [Frankfurter](https://frankfurter.dev) publishes the European Central Bank's reference rates,
/// needs no key, and is what `useCurrencyRate` calls in the web repo — so an expense converted
/// on a phone and the same expense converted in a browser agree. Nothing about the user is sent:
/// a request carries a date and two currency codes.
///
/// A rate is a convenience, never a requirement. Every failure here is one the form recovers
/// from by letting someone type the rate themselves, which is also the only way to record the
/// rate a card issuer actually charged.
public struct ExchangeRates: Sendable {

    public enum Failure: Error, Equatable {
        /// The lookup itself failed — offline, blocked, or the service is down.
        case unavailable
        /// The service answered, but has no rate for that currency on that day. True of every
        /// currency outside the ECB's list, which is a good deal narrower than ISO-4217.
        case noRateForCurrency
    }

    /// Injected so the tests never touch the network, and so the app could point this at a
    /// self-hosted mirror later without the form knowing.
    private let fetch: @Sendable (URL) async throws -> Data

    public init(
        fetch: @escaping @Sendable (URL) async throws -> Data = {
            try await URLSession.shared.data(from: $0).0
        }
    ) {
        self.fetch = fetch
    }

    /// - Parameter day: the expense's date as a plain calendar day, `yyyy-MM-dd`.
    public func rate(on day: String, from base: String, to target: String) async throws -> ExchangeRate {
        let base = base.uppercased()
        let target = target.uppercased()
        guard base.count == 3, target.count == 3, base != target else {
            throw Failure.noRateForCurrency
        }
        guard let url = URL(
            string: "https://api.frankfurter.dev/v1/\(day)?base=\(base)&symbols=\(target)"
        ) else {
            throw Failure.unavailable
        }

        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: await fetch(url))
        } catch {
            throw Failure.unavailable
        }

        guard let rate = response.rates[target] else { throw Failure.noRateForCurrency }
        return ExchangeRate(rate: rate.value, day: response.date)
    }

    /// The day of `date` as Frankfurter wants it.
    ///
    /// Formatted in the current calendar rather than UTC, which is what the expense list already
    /// shows for the same `Date` — a rate quoted for a different day than the row displays would
    /// be the confusing answer, not the correct one.
    public static func day(of date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0
        )
    }

    private struct Response: Decodable {
        let date: String
        let rates: [String: LooseDecimal]
    }

    /// JSON numbers reach `Decimal` through a `Double`, and 0.9412 does not survive that as
    /// itself. Going via the shortest representation that round-trips the double gives back the
    /// number that was printed, which is the one the service meant.
    private struct LooseDecimal: Decodable {
        let value: Decimal

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            let double = try container.decode(Double.self)
            value = Decimal(string: "\(double)") ?? Decimal(double)
        }
    }
}
