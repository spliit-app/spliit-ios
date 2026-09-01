import SpliitAPI
import SwiftUI

/// How a recurrence rule is worded — shared by the form that sets one and the row that shows
/// an expense has one, so the two never drift into saying it differently.
extension RecurrenceRule {

    /// For the picker. "Never" rather than "None", because the row reads as a frequency.
    var title: LocalizedStringKey {
        switch self {
        case .never: "Never"
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        }
    }

    /// What an expense row says about repeating, to something that reads rather than looks.
    ///
    /// Spelled out once per rule rather than assembled from the glyph's label and the frequency:
    /// where the cadence goes in the sentence, and whether it agrees with anything, is the
    /// translation's business and not this call site's.
    var repeatDescription: LocalizedStringKey? {
        switch self {
        case .never: nil
        case .daily: "Repeats daily"
        case .weekly: "Repeats weekly"
        case .monthly: "Repeats monthly"
        }
    }
}
