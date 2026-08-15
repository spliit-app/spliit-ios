import Foundation
import Testing

@testable import SpliitAPI

/// Decodes recorded responses from a real instance. Assertions deliberately avoid the
/// server-generated IDs, which change every time the fixtures are re-recorded.
@Suite("Decoding real API responses")
struct ResponseDecodingTests {

    @Test("A group carries its participants, symbol and ISO code")
    func decodesGroup() throws {
        let response = try SuperJSON.decode(
            Spliit.GroupResponse.self, fromResponse: Fixture.data("groups-get")
        )
        let group = try #require(response.group)

        #expect(group.name == "Weekend in Lisbon")
        #expect(group.currency == "€")
        #expect(group.currencyCode == "EUR")
        #expect(group.participants.map(\.name) == ["Ana", "Bruno", "Chloé"])
        #expect(group.information?.hasPrefix("Shared costs") == true)
    }

    /// `groups.list` builds `createdAt` with `.toISOString()`, so unlike every other endpoint
    /// it sends the timestamp with *no* superjson annotation. Decoding has to work anyway —
    /// this is the case that justifies ignoring `meta.values` entirely.
    @Test("A group summary decodes an unannotated date and the participant count")
    func decodesGroupSummaries() throws {
        let response = try SuperJSON.decode(
            Spliit.GroupsListResponse.self, fromResponse: Fixture.data("groups-list")
        )

        #expect(response.groups.count == 3)
        let lisbon = try #require(response.groups.first { $0.name == "Weekend in Lisbon" })
        #expect(lisbon.participantCount == 3)
        #expect(lisbon.currency == "€")
        #expect(lisbon.createdAt.timeIntervalSince1970 > 0)
    }

    @Test("An expense list decodes amounts, split modes and payers")
    func decodesExpenseList() throws {
        let response = try SuperJSON.decode(
            Spliit.ExpensesListResponse.self, fromResponse: Fixture.data("expenses-list")
        )

        #expect(response.expenses.count == 4)
        #expect(response.hasMore == false)

        let taxi = try #require(response.expenses.first { $0.title == "Airport taxi" })
        #expect(taxi.amount == 4250)
        #expect(taxi.splitMode == .evenly)
        #expect(taxi.paidBy.name == "Ana")
        #expect(taxi.paidFor.count == 3)
        #expect(taxi.category?.name == "General")
        #expect(taxi.documentCount == 0)
        #expect(taxi.isReimbursement == false)

        let apartment = try #require(response.expenses.first { $0.title == "Apartment" })
        #expect(apartment.splitMode == .byShares)
        // Chloé took the double room and carries two of the four shares.
        #expect(apartment.paidFor.first { $0.participant.name == "Chloé" }?.shares == 200)

        let tram = try #require(response.expenses.first { $0.title == "Tram tickets" })
        #expect(tram.splitMode == .byAmount)
        // For BY_AMOUNT, shares are minor-unit amounts that sum to the expense total.
        #expect(tram.paidFor.reduce(0) { $0 + $1.shares } == tram.amount)
    }

    @Test("Expense details decode the editable fields")
    func decodesExpenseDetails() throws {
        let response = try SuperJSON.decode(
            Spliit.ExpenseResponse.self, fromResponse: Fixture.data("expenses-get")
        )
        let expense = response.expense

        #expect(expense.title == "Airport taxi")
        #expect(expense.amount == 4250)
        #expect(expense.categoryId == 0)
        #expect(expense.paidBy.name == "Ana")
        #expect(expense.paidFor.count == 3)
        #expect(expense.splitMode == .evenly)
        #expect(expense.recurrenceRule == RecurrenceRule.never)
        #expect(expense.notes == nil)
        #expect(expense.documents.isEmpty)
        #expect(expense.originalAmount == nil)
        #expect(expense.conversionRate == nil)
    }

    @Test("Balances and reimbursements decode, and balance totals cancel out")
    func decodesBalances() throws {
        let response = try SuperJSON.decode(
            Spliit.BalancesResponse.self, fromResponse: Fixture.data("balances-list")
        )

        #expect(response.balances.count == 3)
        // Every expense is someone's credit and someone else's debit, so the totals net to zero.
        #expect(response.balances.values.reduce(0) { $0 + $1.total } == 0)

        #expect(response.reimbursements.count == 2)
        let total = response.reimbursements.reduce(0) { $0 + $1.amount }
        let owed = response.balances.values.filter { $0.total > 0 }.reduce(0) { $0 + $1.total }
        #expect(total == owed)
    }

    @Test("The full category list decodes with its groupings")
    func decodesCategories() throws {
        let response = try SuperJSON.decode(
            Spliit.CategoriesResponse.self, fromResponse: Fixture.data("categories-list")
        )

        #expect(response.categories.count > 20)
        #expect(response.categories.first?.id == 0)
        #expect(response.categories.first?.name == "General")
        #expect(response.categories.contains { $0.grouping == "Food and Drink" })
    }

    @Test("getDetails reports which participants can no longer be removed")
    func decodesGroupDetails() throws {
        let response = try SuperJSON.decode(
            Spliit.GroupDetailsResponse.self, fromResponse: Fixture.data("groups-get-details")
        )

        #expect(response.group.name == "Weekend in Lisbon")
        #expect(response.participantsWithExpenses.count == 3)
    }

    @Test("A tRPC error envelope becomes a typed server error")
    func decodesErrorEnvelope() throws {
        let error = try #require(
            SuperJSON.decodeError(fromResponse: Fixture.data("error-not-found"))
        )

        #expect(error.code == "NOT_FOUND")
        #expect(error.message == "Group not found.")
        #expect(error.httpStatus == 404)
        #expect(error.path == "groups.getDetails")
        #expect(error.isUnknownProcedure == false)
    }

    @Test("A missing group decodes as an absent group, not an error")
    func decodesNullGroup() throws {
        let body = Data(#"{"result":{"data":{"json":{"group":null}}}}"#.utf8)
        let response = try SuperJSON.decode(Spliit.GroupResponse.self, fromResponse: body)
        #expect(response.group == nil)
    }

    @Test("A procedure that returns undefined decodes as void")
    func decodesVoidResult() throws {
        let body = Data(#"{"result":{"data":{"json":null,"meta":{"values":["undefined"]}}}}"#.utf8)
        #expect(throws: Never.self) {
            try SuperJSON.decode(TRPCVoid.self, fromResponse: body)
        }
    }
}
