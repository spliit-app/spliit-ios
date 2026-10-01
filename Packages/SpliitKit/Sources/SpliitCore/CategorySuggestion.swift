import Foundation
import SpliitAPI

/// Whether a new expense's category may still be filled in from its title, and what to ask.
///
/// The web app does this by posting the title to OpenAI from its server, behind a flag most
/// instances leave off; the app asks the on-device model instead, so it works against every
/// instance. Either way the answer is a guess about a field the user may already have an opinion
/// on, and everything here is about *when the guess is allowed to land*: the model's half lives in
/// the app target, and is the half no test can pin down.
///
/// The rule is the one the exchange rate follows in the same form — a value the screen put there
/// by itself may be replaced by the screen, and a value anybody else put there may not. "Anybody
/// else" is the user at the picker, a scanned receipt, and a shortcut that named a category.
public struct CategorySuggestion: Equatable, Sendable {

    /// The category this form last put there by itself.
    public private(set) var suggestedID: Int?
    /// Set the moment the user touches the picker, and never unset: a category chosen by hand is
    /// a decision, even when the one chosen is General.
    public private(set) var userHasChosen = false

    /// What a category the form has not been told anything about is: General.
    static let unchosen = 0

    /// The most of a title worth reading. A title is a few words; anything past this is a note
    /// typed into the wrong field, and the head of it says what the expense was.
    static let maximumLength = 60

    public init() {}

    /// What to ask the model about, or nil when there is nothing to ask yet.
    ///
    /// Nil for a title the form would refuse anyway — fewer than two characters — since "T" on the
    /// way to "Taxi" categorises as nothing in particular, and an answer to it would only be
    /// replaced a moment later.
    public static func question(for title: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return nil }
        return String(trimmed.prefix(maximumLength))
    }

    /// Whether a suggestion may replace what the draft says now.
    ///
    /// Asked twice: before the model is, so nothing is asked for that could not be used, and again
    /// once it answers, since a person can pick a category in the second it takes.
    public func mayReplace(_ categoryID: Int) -> Bool {
        !userHasChosen && (categoryID == Self.unchosen || categoryID == suggestedID)
    }

    /// Puts a suggested category on the draft, if it is still the form's to change.
    ///
    /// - Returns: whether it landed.
    @discardableResult
    public mutating func apply(_ categoryID: Int, to draft: inout ExpenseFormDraft) -> Bool {
        guard mayReplace(draft.categoryID) else { return false }
        draft.categoryID = categoryID
        suggestedID = categoryID
        return true
    }

    /// The user picked a category. Whatever they picked, it is theirs from now on.
    public mutating func noteUserChoice() {
        userHasChosen = true
    }

    /// Whether the category on show is the form's own guess, which is when the form says so.
    /// Not for General: a guess of "nothing in particular" looks exactly like no guess at all.
    public func isShowingSuggestion(in draft: ExpenseFormDraft) -> Bool {
        guard let suggestedID, suggestedID != Self.unchosen, !userHasChosen else { return false }
        return draft.categoryID == suggestedID
    }

    /// The vocabulary the model chooses from: every category the server offers, written the way
    /// ``ReceiptCategories/match(_:in:)`` reads it back.
    public static func names(of categories: [ExpenseCategory]) -> [String] {
        categories.map { "\($0.grouping)/\($0.name)" }.sorted()
    }
}
