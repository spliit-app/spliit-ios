import Foundation

/// The buckets the expense list is divided into, newest first.
///
/// This reproduces the rules the React Native app used, so an upgrading user sees their
/// expenses sectioned exactly as before.
public enum ExpenseDateGroup: String, Sendable, CaseIterable, Comparable {
    case upcoming
    case thisWeek
    case earlierThisMonth
    case lastMonth
    case earlierThisYear
    case lastYear
    case older

    /// Which bucket `date` falls into, as of `today`.
    public static func containing(
        _ date: Date,
        today: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> ExpenseDateGroup {
        if today < date {
            return .upcoming
        }
        if calendar.isDate(today, equalTo: date, toGranularity: .weekOfYear) {
            return .thisWeek
        }
        if calendar.isDate(today, equalTo: date, toGranularity: .month) {
            return .earlierThisMonth
        }
        if let aMonthAgo = calendar.date(byAdding: .month, value: -1, to: today),
           calendar.isDate(aMonthAgo, equalTo: date, toGranularity: .month) {
            return .lastMonth
        }
        if calendar.isDate(today, equalTo: date, toGranularity: .year) {
            return .earlierThisYear
        }
        if let aYearAgo = calendar.date(byAdding: .year, value: -1, to: today),
           calendar.isDate(aYearAgo, equalTo: date, toGranularity: .year) {
            return .lastYear
        }
        return .older
    }

    /// Display order, newest bucket first.
    private var rank: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    public static func < (lhs: ExpenseDateGroup, rhs: ExpenseDateGroup) -> Bool {
        lhs.rank < rhs.rank
    }
}
