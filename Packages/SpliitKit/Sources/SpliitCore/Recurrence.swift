import Foundation
import SpliitAPI

extension RecurrenceRule {

    /// When the next expense in a series would fall, given the one before it — or nil for a rule
    /// that schedules nothing.
    ///
    /// This mirrors `calculateNextDate` in the web app, quirks included. The server is what
    /// actually creates the expense, so a date shown here that it then disagrees with would be
    /// worse than showing no date at all. Two things follow from copying it rather than doing
    /// the obvious thing.
    ///
    /// It counts in **UTC**, which is where the server counts: it steps expense dates with
    /// `setUTCDate` and `setUTCMonth`, and around a month end the local day and the UTC day are
    /// not always the same day.
    ///
    /// And a monthly series **gives up a day it cannot fit, permanently**. Each step is measured
    /// from the expense before it rather than from the first one, so the 31st of January comes
    /// round to the 28th of February — and then to the 28th of March, not back to the 31st. The
    /// server reduces the day until the month has one; `Calendar` clamps to the last day of the
    /// target month, which is the same answer for every date either can be handed. The web app
    /// records this as a known limitation rather than a decision, but it is the behaviour, and
    /// showing the date is how somebody setting up rent on the 31st finds out before they save.
    public func nextDate(after date: Date) -> Date? {
        switch self {
        case .never: return nil
        case .daily: return Self.utc.date(byAdding: .day, value: 1, to: date)
        case .weekly: return Self.utc.date(byAdding: .day, value: 7, to: date)
        case .monthly: return Self.utc.date(byAdding: .month, value: 1, to: date)
        }
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()
}
