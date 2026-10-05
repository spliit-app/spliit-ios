import Foundation
import Testing

@testable import SpliitAPI

@Suite("Expense dates as calendar days")
struct CalendarDayTests {

    private let toronto = TimeZone(identifier: "America/Toronto")!
    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!

    private func instant(_ text: String) throws -> Date {
        try SuperJSON.iso8601.parse(text)
    }

    private func day(_ date: Date, in timeZone: TimeZone) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.dateComponents([.year, .month, .day], from: date)
    }

    /// 20:36 on Oct 4 in Toronto is already Oct 5 in UTC; the server would keep Oct 5.
    @Test("An evening west of UTC goes out as that day, not tomorrow")
    func sendsTheLocalDayWestOfUTC() throws {
        let evening = try instant("2026-10-05T00:36:00Z")
        #expect(CalendarDay.wire(evening, in: toronto) == (try instant("2026-10-04T00:00:00Z")))
    }

    /// 08:00 on Oct 5 in Tokyo is still Oct 4 in UTC.
    @Test("A morning east of UTC goes out as that day, not yesterday")
    func sendsTheLocalDayEastOfUTC() throws {
        let morning = try instant("2026-10-04T23:00:00Z")
        #expect(CalendarDay.wire(morning, in: tokyo) == (try instant("2026-10-05T00:00:00Z")))
    }

    @Test("A day from the server is the same day wherever the phone is")
    func readsTheSameDayEverywhere() throws {
        let stored = try instant("2026-10-04T00:00:00Z")
        for timeZone in [toronto, tokyo, TimeZone.gmt] {
            let local = CalendarDay.local(stored, in: timeZone)
            #expect(day(local, in: timeZone) == DateComponents(year: 2026, month: 10, day: 4))
            #expect(CalendarDay.wire(local, in: timeZone) == stored)
        }
    }
}
