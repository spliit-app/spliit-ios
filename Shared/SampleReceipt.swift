import Foundation

/// The receipt the app draws for itself under UI test, and what reading it ought to produce.
///
/// Shared with the test bundle for the reason the accessibility identifiers are: the suite
/// asserts on what this says, and the same value written out in two files is a value that
/// drifts. Nothing in a release build refers to it — the app only draws it from a `#if DEBUG`
/// path — so it strips out along with the rest of the test scaffolding.
enum SampleReceipt {

    /// Dated relative to the run, and written the one way no locale can read backwards. A fixed
    /// date would fall out of the plausible window in a couple of years and take the suite with
    /// it. Three days back: not today, which the form would have filled in anyway, and not so
    /// long ago as to look like a misreading.
    static var day: Date {
        Calendar(identifier: .gregorian).date(byAdding: .day, value: -3, to: Date()) ?? Date()
    }

    static var dayText: String {
        day.formatted(.iso8601.year().month().day().dateSeparator(.dash))
    }

    /// A till receipt of the shape most of them have, including the subtotal / tax / total
    /// triple that is the whole reason the total is not simply the last number on it.
    static var lines: [String] {
        [
            "CAFE DU COIN", "12 rue de la Paix", "75002 Paris", "",
            dayText, "",
            "Cafe            3,50", "Croissant       2,40", "Sandwich        8,60", "",
            "SOUS-TOTAL     14,50", "TVA 10%         1,45", "TOTAL          15,95",
        ]
    }

    /// Shouted on the receipt, capitalised by the reader.
    static let merchant = "Cafe Du Coin"
    /// In the group's own currency, as the amount field writes it in an en-US simulator.
    static let total = "15.95"
    /// Guessed from "CAFE" in the merchant's name, in the server's own vocabulary.
    static let category = "Dining Out"
}
