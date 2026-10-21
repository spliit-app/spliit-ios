import Testing

@testable import SpliitCore

@Suite("Expense search match")
struct ExpenseSearchMatchTests {

    @Test func aTitleContainingTheQueryMatchedOnTheTitle() {
        #expect(ExpenseSearchMatch(title: "Pizza night", query: "pizza") == .title)
        #expect(ExpenseSearchMatch(title: "Pizza night", query: "ZZA NI") == .title)
    }

    /// spliit#660's own case: the server found it, and the title is not why.
    @Test func aTitleWithoutTheQueryMatchedOnTheNotes() {
        #expect(ExpenseSearchMatch(title: "Dinner", query: "lake house") == .notes)
    }

    /// `ILIKE` folds case and nothing else, so an accent the query lacks is not a title match —
    /// the server would only have returned the expense for its notes.
    @Test func accentsAreNotFolded() {
        #expect(ExpenseSearchMatch(title: "Café", query: "cafe") == .notes)
        #expect(ExpenseSearchMatch(title: "Café", query: "CAFÉ") == .title)
    }
}
