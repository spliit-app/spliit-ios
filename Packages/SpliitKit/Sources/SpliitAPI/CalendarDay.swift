import Foundation

/// An expense's date is a calendar day, not a moment.
///
/// The server keeps `expenseDate` in a Postgres `date` column: it stores the UTC day of whatever
/// instant it is sent, and sends that day back as midnight UTC. The app works with the day as
/// midnight where the phone is, which is what `DatePicker`, `formatted(date:time:)` and the
/// calendar arithmetic all read. `SuperJSON` converts between the two at the edge, so nothing
/// past it has to know.
///
/// Without that, west of UTC every expense shows as the day before, and one saved in the
/// evening is stored as tomorrow. The web app does the same conversion since spliit#433.
public enum CalendarDay {

    /// Midnight UTC of the day `date` falls on in `timeZone`: what the server stores as that day.
    public static func wire(_ date: Date, in timeZone: TimeZone = .autoupdatingCurrent) -> Date {
        let day = gregorian(timeZone).dateComponents([.year, .month, .day], from: date)
        return gregorian(.gmt).date(from: day) ?? date
    }

    /// Midnight in `timeZone` of the day the server sent as midnight UTC.
    public static func local(_ date: Date, in timeZone: TimeZone = .autoupdatingCurrent) -> Date {
        let day = gregorian(.gmt).dateComponents([.year, .month, .day], from: date)
        return gregorian(timeZone).date(from: day) ?? date
    }

    /// Always Gregorian, whatever calendar the phone is set to: the server's days are.
    private static func gregorian(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}
