import Foundation
import Testing

@testable import SpliitCore

/// The log's own buckets, which are finer than the expense list's — a log is mostly the last day
/// or two, where "This week" would be the whole screen. A fixed "today" keeps these from drifting
/// with the wall clock.
@Suite("Activity date buckets")
struct ActivityDateGroupTests {

    /// Thursday 13 August 2026, midday UTC. Weeks below run Sunday to Saturday, so "this week"
    /// is the 9th to the 15th.
    private let today = Date(timeIntervalSince1970: 1_786_622_400)

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 1
        return calendar
    }

    private func bucket(hoursFromToday hours: Int) -> ActivityDateGroup {
        let date = calendar.date(byAdding: .hour, value: hours, to: today)!
        return ActivityDateGroup.containing(date, today: today, calendar: calendar)
    }

    private func bucket(daysFromToday days: Int) -> ActivityDateGroup {
        let date = calendar.date(byAdding: .day, value: days, to: today)!
        return ActivityDateGroup.containing(date, today: today, calendar: calendar)
    }

    private func bucket(monthsFromToday months: Int) -> ActivityDateGroup {
        let date = calendar.date(byAdding: .month, value: months, to: today)!
        return ActivityDateGroup.containing(date, today: today, calendar: calendar)
    }

    @Test("Any time on the same calendar day is today")
    func today_() {
        #expect(bucket(hoursFromToday: 0) == .today)
        #expect(bucket(hoursFromToday: -11) == .today)
    }

    /// Nothing records an activity in the future, but a phone whose clock runs fast reads one,
    /// and it belongs at the top of the log rather than wherever the arithmetic lands it.
    @Test("An activity stamped in the future is shown as today")
    func future() {
        #expect(bucket(hoursFromToday: 2) == .today)
        #expect(bucket(daysFromToday: 3) == .today)
    }

    @Test("The previous calendar day is yesterday, not merely earlier this week")
    func yesterday() {
        #expect(bucket(daysFromToday: -1) == .yesterday)
    }

    @Test("Two days back, in the same week, is earlier this week")
    func earlierThisWeek() {
        // Tuesday the 11th and Monday the 10th, both after the Sunday this week began on.
        #expect(bucket(daysFromToday: -2) == .earlierThisWeek)
        #expect(bucket(daysFromToday: -3) == .earlierThisWeek)
    }

    @Test("The previous calendar week is last week")
    func lastWeek() {
        // Saturday the 8th closed the previous week; Sunday the 2nd opened it.
        #expect(bucket(daysFromToday: -5) == .lastWeek)
        #expect(bucket(daysFromToday: -11) == .lastWeek)
    }

    @Test("Earlier in the same month, but two weeks back, is earlier this month")
    func earlierThisMonth() {
        // Saturday 1 August: two weeks back, and still August.
        #expect(bucket(daysFromToday: -12) == .earlierThisMonth)
    }

    @Test("The previous calendar month is last month")
    func lastMonth() {
        #expect(bucket(monthsFromToday: -1) == .lastMonth)
    }

    @Test("Earlier in the same year is earlier this year")
    func earlierThisYear() {
        #expect(bucket(monthsFromToday: -3) == .earlierThisYear)
        #expect(bucket(monthsFromToday: -7) == .earlierThisYear)
    }

    @Test("The previous calendar year is last year")
    func lastYear() {
        #expect(bucket(monthsFromToday: -12) == .lastYear)
        #expect(bucket(monthsFromToday: -19) == .lastYear)
    }

    @Test("Anything older falls into the last bucket")
    func older() {
        #expect(bucket(monthsFromToday: -25) == .older)
        #expect(bucket(monthsFromToday: -60) == .older)
    }

    @Test("Buckets sort newest first")
    func sortsNewestFirst() {
        let shuffled: [ActivityDateGroup] = [.older, .lastWeek, .today, .lastYear, .yesterday]

        #expect(shuffled.sorted() == [.today, .yesterday, .lastWeek, .lastYear, .older])
    }

    /// The heading says which day it was for the first two buckets and names a span for the
    /// rest, so only the rest need the date spelled out on every row.
    @Test("Only the buckets that name a span make their rows carry a date")
    func needsDate() {
        #expect(ActivityDateGroup.today.needsDate == false)
        #expect(ActivityDateGroup.yesterday.needsDate == false)
        let spans = ActivityDateGroup.allCases.filter { $0 != .today && $0 != .yesterday }
        #expect(spans.allSatisfy { $0.needsDate })
    }
}
