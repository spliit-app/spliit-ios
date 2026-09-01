import Foundation
import SpliitAPI
import Testing

@testable import SpliitCore

@Suite("Recurrence")
struct RecurrenceTests {

    /// The server counts in UTC, so the expectations are written in it too — a date built in
    /// local time would make these pass or fail by the machine's time zone.
    private func utc(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: components)!
    }

    @Test("A rule that never repeats schedules nothing")
    func neverSchedulesNothing() {
        #expect(RecurrenceRule.never.nextDate(after: utc(2026, 9, 1)) == nil)
        #expect(!RecurrenceRule.never.repeats)
        #expect(RecurrenceRule.daily.repeats)
    }

    @Test("Daily is the next day, and weekly the next week")
    func stepsByDays() {
        #expect(RecurrenceRule.daily.nextDate(after: utc(2026, 9, 1)) == utc(2026, 9, 2))
        #expect(RecurrenceRule.weekly.nextDate(after: utc(2026, 9, 1)) == utc(2026, 9, 8))
    }

    @Test("Days roll into the next month, and months into the next year")
    func rollsOver() {
        #expect(RecurrenceRule.daily.nextDate(after: utc(2026, 8, 31)) == utc(2026, 9, 1))
        #expect(RecurrenceRule.weekly.nextDate(after: utc(2026, 12, 28)) == utc(2027, 1, 4))
        #expect(RecurrenceRule.monthly.nextDate(after: utc(2026, 12, 31)) == utc(2027, 1, 31))
    }

    @Test("Monthly keeps the day of the month when the month has one")
    func keepsTheDayOfTheMonth() {
        #expect(RecurrenceRule.monthly.nextDate(after: utc(2026, 9, 15)) == utc(2026, 10, 15))
        #expect(RecurrenceRule.monthly.nextDate(after: utc(2026, 1, 30)) == utc(2026, 2, 28))
    }

    /// The behaviour the web app records as a limitation of its own date arithmetic, and the
    /// reason the form shows the date rather than only the word "Monthly": rent set up on the
    /// 31st of January is charged on the 28th from February onwards, for good.
    @Test("A monthly series gives up a day it cannot fit, and never gets it back")
    func monthlyDriftIsPermanent() {
        let january = utc(2026, 1, 31)

        let february = RecurrenceRule.monthly.nextDate(after: january)
        #expect(february == utc(2026, 2, 28))

        let march = RecurrenceRule.monthly.nextDate(after: february!)
        #expect(march == utc(2026, 3, 28))

        let april = RecurrenceRule.monthly.nextDate(after: march!)
        #expect(april == utc(2026, 4, 28))
    }

    @Test("A leap February takes the 29th")
    func leapFebruary() {
        #expect(RecurrenceRule.monthly.nextDate(after: utc(2028, 1, 31)) == utc(2028, 2, 29))
        #expect(RecurrenceRule.daily.nextDate(after: utc(2028, 2, 28)) == utc(2028, 2, 29))
    }
}
