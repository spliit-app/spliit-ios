import Foundation
import SpliitAPI
import Testing

@testable import SpliitCore

/// Folding a group's expenses into what it spent per category.
///
/// The fold is deliberately the web app's `getSpendingByCategory`, so these pin the behaviours
/// that would otherwise drift: reimbursements excluded, uncategorised counted as General, empty
/// categories dropped, biggest first.
@Suite("Spending by category")
struct CategorySpendingTests {

    private func expense(
        _ title: String,
        _ amount: Int,
        category: ExpenseCategory? = nil,
        isReimbursement: Bool = false
    ) -> ExpenseListItem {
        ExpenseListItem(
            id: title,
            title: title,
            amount: amount,
            isReimbursement: isReimbursement,
            category: category
        )
    }

    private let groceries = ExpenseCategory(id: 5, grouping: "Food and Drink", name: "Groceries")
    private let taxi = ExpenseCategory(id: 12, grouping: "Transportation", name: "Taxi")

    @Test("Expenses are summed per category, biggest spend first")
    func sumsByCategory() {
        let breakdown = CategorySpending.breakdown(of: [
            expense("Market", 2000, category: groceries),
            expense("Airport", 4250, category: taxi),
            expense("Corner shop", 1500, category: groceries),
        ])

        // Taxi's single 4250 outranks the two shopping trips that came to 3500 between them.
        #expect(breakdown.map(\.categoryID) == [12, 5])
        #expect(breakdown.map(\.total) == [4250, 3500])
        #expect(breakdown.last?.name == "Groceries")
        #expect(breakdown.last?.grouping == "Food and Drink")
    }

    /// The invariant the screen leans on: the section only draws when it adds up to the total
    /// the stats endpoint reported, and that endpoint drops reimbursements too.
    @Test("Reimbursements are not spending and are left out")
    func excludesReimbursements() {
        let breakdown = CategorySpending.breakdown(of: [
            expense("Hotel", 10000, category: groceries),
            expense("Paying Ana back", 5000, category: taxi, isReimbursement: true),
        ])

        #expect(breakdown.count == 1)
        #expect(breakdown.reduce(0) { $0 + $1.total } == 10000)
    }

    /// An expense filed under nothing and one filed under General are the same row, because the
    /// server gives them the same ID — and an uncategorised expense is a general one.
    @Test("An expense with no category counts as General")
    func foldsUncategorised() {
        let general = ExpenseCategory(id: 0, grouping: "Uncategorized", name: "General")
        let breakdown = CategorySpending.breakdown(of: [
            expense("Something", 800),
            expense("Something else", 200, category: general),
        ])

        #expect(breakdown.count == 1)
        #expect(breakdown.first?.categoryID == 0)
        #expect(breakdown.first?.name == "General")
        #expect(breakdown.first?.total == 1000)
    }

    /// A refund can cancel a category out entirely. A row reading zero says the group spent
    /// nothing on it, which is true and not worth a line.
    @Test("A category that nets to nothing is dropped, and the rest still add up")
    func dropsEmptyCategories() {
        let breakdown = CategorySpending.breakdown(of: [
            expense("Deposit", 5000, category: taxi),
            expense("Deposit returned", -5000, category: taxi),
            expense("Market", 2000, category: groceries),
        ])

        #expect(breakdown.map(\.categoryID) == [5])
        #expect(breakdown.reduce(0) { $0 + $1.total } == 2000)
    }

    /// Negative totals sort below positive ones rather than being treated as large.
    @Test("A category that came to a refund sorts last and keeps its sign")
    func keepsNegativesSigned() {
        let breakdown = CategorySpending.breakdown(of: [
            expense("Refund", -1500, category: taxi),
            expense("Market", 2000, category: groceries),
        ])

        #expect(breakdown.map(\.total) == [2000, -1500])
    }

    /// `sorted(by:)` is not stable, so two categories on the same amount need something else to
    /// order them — or they swap places on a refresh that changed neither.
    @Test("Categories on equal amounts keep a fixed order")
    func breaksTiesDeterministically() {
        let expenses = [
            expense("Market", 2000, category: groceries),
            expense("Airport", 2000, category: taxi),
        ]

        let first = CategorySpending.breakdown(of: expenses).map(\.categoryID)
        let second = CategorySpending.breakdown(of: expenses.reversed()).map(\.categoryID)

        #expect(first == [5, 12])
        #expect(first == second, "The input order must not decide the output order.")
    }

    /// The screen folds a page at a time so it never holds a whole group's expenses in memory.
    /// What that must not change is the answer.
    @Test("Folding page by page gives the same breakdown as folding all at once")
    func foldsIncrementally() {
        let expenses = [
            expense("Market", 2000, category: groceries),
            expense("Airport", 4250, category: taxi),
            expense("Corner shop", 1500, category: groceries),
            expense("Settling up", 900, category: taxi, isReimbursement: true),
            expense("Something", 300),
        ]

        var fold = CategorySpending.Fold()
        for page in [Array(expenses[0..<2]), Array(expenses[2..<4]), Array(expenses[4...])] {
            fold.add(page)
        }

        #expect(fold.breakdown == CategorySpending.breakdown(of: expenses))
        #expect(fold.breakdown.reduce(0) { $0 + $1.total } == 2000 + 4250 + 1500 + 300)
    }

    @Test("A group with nothing but reimbursements has no breakdown at all")
    func handlesNothingToShow() {
        #expect(CategorySpending.breakdown(of: []).isEmpty)
        #expect(
            CategorySpending.breakdown(of: [
                expense("Settling up", 500, category: taxi, isReimbursement: true)
            ]).isEmpty
        )
    }
}
