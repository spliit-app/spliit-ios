import Foundation
import Testing

@testable import SpliitCore

/// Buckets must land exactly where the React Native app put them, so the list looks unchanged
/// to someone who just updated. A fixed "today" keeps these from drifting with the wall clock.
@Suite("Expense date buckets")
struct ExpenseDateGroupTests {

    /// Wednesday 12 August 2026, midday UTC.
    private let today = Date(timeIntervalSince1970: 1_786_622_400)

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 1
        return calendar
    }

    private func bucket(daysFromToday days: Int) -> ExpenseDateGroup {
        let date = calendar.date(byAdding: .day, value: days, to: today)!
        return ExpenseDateGroup.containing(date, today: today, calendar: calendar)
    }

    private func bucket(monthsFromToday months: Int) -> ExpenseDateGroup {
        let date = calendar.date(byAdding: .month, value: months, to: today)!
        return ExpenseDateGroup.containing(date, today: today, calendar: calendar)
    }

    @Test("A future expense is upcoming")
    func upcoming() {
        #expect(bucket(daysFromToday: 1) == .upcoming)
        #expect(bucket(daysFromToday: 30) == .upcoming)
    }

    @Test("Earlier today and earlier this week land in this week")
    func thisWeek() {
        #expect(bucket(daysFromToday: -1) == .thisWeek)
        #expect(bucket(daysFromToday: -2) == .thisWeek)
    }

    @Test("Earlier in the same month, but a previous week, is earlier this month")
    func earlierThisMonth() {
        // 12 August is a Wednesday; 3 August is the previous week but the same month.
        #expect(bucket(daysFromToday: -9) == .earlierThisMonth)
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
        let shuffled: [ExpenseDateGroup] = [.older, .thisWeek, .lastYear, .upcoming]

        #expect(shuffled.sorted() == [.upcoming, .thisWeek, .lastYear, .older])
    }
}
