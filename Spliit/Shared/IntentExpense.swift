import Foundation

/// What `AddExpenseIntent` would have opened the form with, for the end-to-end suite.
///
/// The intents themselves cannot be driven from XCUITest, so a test hands this to the app as
/// JSON under `-uiTestAddExpense` and the app routes it exactly as the intent would. It lives in
/// `Shared/` so both sides compile the one type: a field renamed on one side alone would decode
/// to nothing, route nothing, and fail thirty seconds later with a form that never opened.
struct IntentExpense: Codable {
    var groupID: String
    var title: String? = nil
    var amount: String? = nil
    var categoryID: Int? = nil
    var notes: String? = nil
    /// How many photographs to hand over — copies of the receipt the app draws for itself, since
    /// a test has none of its own to give a shortcut.
    var documents: Int = 0
}
