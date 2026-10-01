import SpliitAPI
import Testing

@testable import SpliitCore

@Suite("Suggesting a category from the title")
struct CategorySuggestionTests {

    private let taxi = 12
    private let dining = 8

    @Test("A title too short for the form is not asked about")
    func shortTitles() {
        #expect(CategorySuggestion.question(for: "") == nil)
        #expect(CategorySuggestion.question(for: "  T ") == nil)
        #expect(CategorySuggestion.question(for: " Taxi \n") == "Taxi")
    }

    @Test("Only the head of a long title is read")
    func longTitles() {
        let title = String(repeating: "pizza ", count: 40)
        #expect(CategorySuggestion.question(for: title)?.count == CategorySuggestion.maximumLength)
    }

    @Test("General is the form's to change")
    func replacesGeneral() {
        var draft = ExpenseFormDraft()
        var suggestion = CategorySuggestion()
        #expect(suggestion.apply(taxi, to: &draft))
        #expect(draft.categoryID == taxi)
        #expect(suggestion.isShowingSuggestion(in: draft))
    }

    @Test("A guess may be replaced by the next one, as the title changes")
    func replacesItsOwnGuess() {
        var draft = ExpenseFormDraft()
        var suggestion = CategorySuggestion()
        suggestion.apply(taxi, to: &draft)
        #expect(suggestion.apply(dining, to: &draft))
        #expect(draft.categoryID == dining)
    }

    @Test("A category from a receipt or a shortcut is left alone")
    func keepsSomebodyElsesCategory() {
        var draft = ExpenseFormDraft(categoryID: dining)
        var suggestion = CategorySuggestion()
        #expect(!suggestion.apply(taxi, to: &draft))
        #expect(draft.categoryID == dining)
        #expect(!suggestion.isShowingSuggestion(in: draft))
    }

    @Test("A receipt scanned over a guess wins, and stays")
    func receiptOverAGuess() {
        var draft = ExpenseFormDraft()
        var suggestion = CategorySuggestion()
        suggestion.apply(taxi, to: &draft)
        draft.categoryID = dining
        #expect(!suggestion.mayReplace(draft.categoryID))
        #expect(!suggestion.isShowingSuggestion(in: draft))
    }

    @Test("A receipt that agrees with the guess still wins, and stays")
    func receiptThatAgreesWithTheGuess() {
        var draft = ExpenseFormDraft()
        var suggestion = CategorySuggestion()
        suggestion.apply(taxi, to: &draft)
        suggestion.forget()
        #expect(!suggestion.apply(dining, to: &draft))
        #expect(draft.categoryID == taxi)
        #expect(!suggestion.isShowingSuggestion(in: draft))
    }

    @Test("A category picked by hand is never replaced — General included")
    func keepsTheUsersChoice() {
        var draft = ExpenseFormDraft()
        var suggestion = CategorySuggestion()
        suggestion.apply(taxi, to: &draft)
        draft.categoryID = 0
        suggestion.noteUserChoice()
        #expect(!suggestion.apply(dining, to: &draft))
        #expect(draft.categoryID == 0)
        #expect(!suggestion.isShowingSuggestion(in: draft))
    }

    @Test("A guess of General is not announced as a guess")
    func generalIsNotAnnounced() {
        var draft = ExpenseFormDraft()
        var suggestion = CategorySuggestion()
        suggestion.apply(taxi, to: &draft)
        suggestion.apply(0, to: &draft)
        #expect(draft.categoryID == 0)
        #expect(!suggestion.isShowingSuggestion(in: draft))
        #expect(suggestion.mayReplace(draft.categoryID))
    }

    @Test("The vocabulary is what the match reads back")
    func vocabularyRoundTrips() {
        let categories = [
            ExpenseCategory(id: 0, grouping: "Uncategorized", name: "General"),
            ExpenseCategory(id: taxi, grouping: "Transportation", name: "Taxi"),
            ExpenseCategory(id: dining, grouping: "Food and Drink", name: "Dining Out"),
        ]
        let names = CategorySuggestion.names(of: categories)
        #expect(names.count == 3)
        for (name, category) in zip(names, categories.sorted { "\($0.grouping)/\($0.name)" < "\($1.grouping)/\($1.name)" }) {
            #expect(ReceiptCategories.match(name, in: categories) == category.id)
        }
    }
}
