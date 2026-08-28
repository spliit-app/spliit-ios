import Foundation

/// The buckets the activity log is divided into, newest first.
///
/// Finer than `ExpenseDateGroup`, and deliberately so. An expense is dated by the day it
/// happened and a group collects a handful a week, so "This week" is a useful heading; an
/// activity is stamped to the second and most of a log is from the last day or two, where the
/// same heading would be the whole screen. These are the web app's buckets, so both products
/// cut the same log in the same places.
public enum ActivityDateGroup: String, Sendable, CaseIterable, Comparable {
    case today
    case yesterday
    case earlierThisWeek
    case lastWeek
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
    ) -> ActivityDateGroup {
        // Nothing records an activity in the future, but a phone whose clock disagrees with the
        // server's can still read one — and it belongs at the top of the log rather than in
        // whichever bucket the arithmetic below happens to reach first.
        if date > today || calendar.isDate(today, inSameDayAs: date) {
            return .today
        }
        if let aDayAgo = calendar.date(byAdding: .day, value: -1, to: today),
           calendar.isDate(aDayAgo, inSameDayAs: date) {
            return .yesterday
        }
        if calendar.isDate(today, equalTo: date, toGranularity: .weekOfYear) {
            return .earlierThisWeek
        }
        if let aWeekAgo = calendar.date(byAdding: .weekOfYear, value: -1, to: today),
           calendar.isDate(aWeekAgo, equalTo: date, toGranularity: .weekOfYear) {
            return .lastWeek
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

    /// Whether a row in this bucket has to spell its date out. "Today" and "Yesterday" have
    /// already said which day it was; every other heading names a span, so the time alone would
    /// not place the row within it.
    public var needsDate: Bool {
        self != .today && self != .yesterday
    }

    /// Display order, newest bucket first.
    private var rank: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    public static func < (lhs: ActivityDateGroup, rhs: ActivityDateGroup) -> Bool {
        lhs.rank < rhs.rank
    }
}
