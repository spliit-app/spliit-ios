import Foundation
import Testing

@testable import SpliitCore

@Suite("Exchange rates")
struct ExchangeRatesTests {

    private func rates(
        answering body: @escaping @Sendable (URL) throws -> String
    ) -> ExchangeRates {
        ExchangeRates { url in Data(try body(url).utf8) }
    }

    private func rates(returning json: String) -> ExchangeRates {
        rates { _ in json }
    }

    @Test("A rate is read for the pair that was asked for")
    func readsTheRate() async throws {
        let rate = try await rates(
            returning: #"{"amount":1.0,"base":"USD","date":"2026-08-27","rates":{"EUR":0.9241}}"#
        ).rate(on: "2026-08-27", from: "USD", to: "EUR")

        #expect(rate.rate == Decimal(string: "0.9241"))
        #expect(rate.day == "2026-08-27")
    }

    /// A JSON number reaches `Decimal` through a `Double`, and 0.9241 does not survive that
    /// unchanged. It has to come back as the number that was printed, or the rate the form
    /// stores is not the rate that was published.
    @Test("A rate keeps the digits it was published with")
    func keepsThePublishedDigits() async throws {
        let rate = try await rates(
            returning: #"{"amount":1.0,"base":"EUR","date":"2026-08-27","rates":{"JPY":163.55}}"#
        ).rate(on: "2026-08-27", from: "EUR", to: "JPY")

        #expect("\(rate.rate)" == "163.55")
    }

    @Test("The day asked for and the currencies go into the request")
    func buildsTheRequest() async throws {
        let seen = Recorder()
        _ = try? await rates(answering: { url in
            seen.record(url)
            return #"{"amount":1.0,"base":"USD","date":"2026-08-27","rates":{"EUR":0.9}}"#
        }).rate(on: "2026-08-27", from: "usd", to: "eur")

        let url = try #require(seen.url?.absoluteString)
        #expect(url == "https://api.frankfurter.dev/v1/2026-08-27?base=USD&symbols=EUR")
    }

    /// Rates are published on working days, so a Sunday or a date still to come answers with the
    /// last day there is one. The form says which day, rather than quietly showing a number for
    /// a different date than the expense.
    @Test("The day the rate is actually from comes back with it")
    func reportsTheDayTheRateIsFrom() async throws {
        let rate = try await rates(
            returning: #"{"amount":1.0,"base":"USD","date":"2026-08-28","rates":{"EUR":0.92}}"#
        ).rate(on: "2026-08-30", from: "USD", to: "EUR")

        #expect(rate.day == "2026-08-28")
        #expect(rate.date == Calendar.autoupdatingCurrent.date(
            from: DateComponents(year: 2026, month: 8, day: 28)
        ))
    }

    @Test("A pair the service has no rate for is told apart from a service that is down")
    func distinguishesAMissingRate() async throws {
        await #expect(throws: ExchangeRates.Failure.noRateForCurrency) {
            try await rates(
                returning: #"{"amount":1.0,"base":"USD","date":"2026-08-27","rates":{}}"#
            ).rate(on: "2026-08-27", from: "USD", to: "XPF")
        }

        await #expect(throws: ExchangeRates.Failure.unavailable) {
            try await rates(returning: "<html>nope</html>")
                .rate(on: "2026-08-27", from: "USD", to: "EUR")
        }

        await #expect(throws: ExchangeRates.Failure.unavailable) {
            try await ExchangeRates(fetch: { _ in throw URLError(.notConnectedToInternet) })
                .rate(on: "2026-08-27", from: "USD", to: "EUR")
        }
    }

    /// Nothing to convert, and nothing to ask: the form should never get this far, but a request
    /// for a currency against itself would come back as 1 and look like an answer.
    @Test("A pair that isn't one is refused without a request")
    func refusesANonPair() async throws {
        await #expect(throws: ExchangeRates.Failure.noRateForCurrency) {
            try await ExchangeRates(fetch: { _ in
                Issue.record("Should not have asked for a rate.")
                return Data()
            }).rate(on: "2026-08-27", from: "EUR", to: "eur")
        }
    }

    @Test("A date becomes the day it is in the calendar on screen")
    func formatsTheDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try! #require(TimeZone(identifier: "Europe/Paris"))
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 9))!

        #expect(ExchangeRates.day(of: date, calendar: calendar) == "2026-03-09")
    }

    /// Written from the fetch closure and read from the test — a lock rather than an actor, so
    /// the closure it is used from can stay synchronous.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: URL?

        var url: URL? { lock.withLock { stored } }

        func record(_ url: URL) { lock.withLock { stored = url } }
    }
}
