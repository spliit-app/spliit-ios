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

    /// Recorded for Ana in the seeded Lisbon group: she paid the taxi and the tram tickets, and
    /// is on all four expenses.
    @Test("Stats answer for a participant with what they paid and what they owe")
    func decodesStats() throws {
        let response = try SuperJSON.decode(
            Spliit.GroupStatsResponse.self, fromResponse: Fixture.data("groups-stats-get")
        )

        #expect(response.totalGroupSpendings == 4250 + 9630 + 48000 + 1800)
        #expect(response.totalParticipantSpendings == 4250 + 1800)
        // A third of the taxi, a third of the dinner, a quarter of the apartment and the tram
        // amount she was billed for — apportioned into whole minor units by the server.
        #expect(response.totalParticipantShare == 17627)
    }

    /// Asking about nobody is a different answer from asking about someone who spent nothing,
    /// and superjson says so with `meta.values` rather than by leaving the keys out. The
    /// decoder ignores that metadata, so what has to work is the `null` underneath it.
    @Test("Stats for nobody in particular leave the participant figures absent")
    func decodesStatsWithoutAParticipant() throws {
        let response = try SuperJSON.decode(
            Spliit.GroupStatsResponse.self,
            fromResponse: Fixture.data("groups-stats-get-anonymous")
        )

        #expect(response.totalGroupSpendings == 63680)
        #expect(response.totalParticipantSpendings == nil)
        #expect(response.totalParticipantShare == nil)
    }

    /// The wire type is `Double` for instances older than the web app's *Shares* change, which
    /// summed floating-point thirds and rounded to two decimals. `Int` would throw on this and
    /// take the screen with it, so the type has to stay wide enough for a server nobody has
    /// upgraded yet.
    @Test("A share from a server that still splits in floating point decodes")
    func decodesFractionalShare() throws {
        let legacy = Data(
            #"{"result":{"data":{"json":{"totalGroupSpendings":4250,"totalParticipantSpendings":4250,"totalParticipantShare":1416.67}}}}"#
                .utf8
        )

        let response = try SuperJSON.decode(Spliit.GroupStatsResponse.self, fromResponse: legacy)

        #expect(response.totalParticipantShare == 1416.67)
    }

    @Test("An activity log decodes every kind of entry, newest first")
    func decodesActivities() throws {
        let response = try SuperJSON.decode(
            Spliit.ActivitiesListResponse.self, fromResponse: Fixture.data("activities-list")
        )

        #expect(response.hasMore == false)
        #expect(response.activities.count == 8)
        #expect(response.activities.allSatisfy { $0.activityType.isRecognised })

        // The server orders by time descending, and the log is drawn in the order it arrives.
        let times = response.activities.map(\.time)
        #expect(times == times.sorted(by: >))

        // The seed makes the last thing that happened a change to the group itself, which is
        // the one kind of entry that names no expense at all.
        let settings = try #require(response.activities.first)
        #expect(settings.activityType == .updateGroup)
        #expect(settings.expenseId == nil)
        #expect(settings.title == nil)
        #expect(settings.expenseStillExists == false)

        // Every entry is attributed, because the seed sends a `participantId` on every write.
        #expect(response.activities.allSatisfy { $0.participantId != nil })

        let created = try #require(
            response.activities.first { $0.activityType == .createExpense && $0.title == "Airport taxi" }
        )
        #expect(created.expenseStillExists)
        #expect(created.expenseId != nil)

        // Created and then deleted, so its two entries point at an expense that is no longer
        // there. This is what tells a row that leads somewhere from one that cannot.
        let vanished = response.activities.filter { $0.title == "Pastéis de Belém" }
        #expect(vanished.map(\.activityType) == [.deleteExpense, .createExpense])
        #expect(vanished.allSatisfy { !$0.expenseStillExists })
        #expect(vanished.allSatisfy { $0.expenseId != nil })
    }

    /// The one place this client is deliberately lenient where `SplitMode` is not: a split mode
    /// it cannot read is money it would divide wrongly, and an activity it cannot read is a line
    /// of prose it can leave out.
    ///
    /// Hand-written rather than recorded, and legitimately so: no server sends this today, which
    /// is the entire premise. It is a fifth `ActivityType` arriving from a server newer than
    /// this app — the thing a recorded fixture cannot be made to contain.
    @Test("An activity kind this version has never heard of decodes rather than throwing")
    func decodesUnknownActivityType() throws {
        let envelope = """
        {"result":{"data":{"json":{"activities":[{"id":"a1","groupId":"g1",\
        "time":"2026-08-20T10:00:00.000Z","activityType":"ARCHIVE_GROUP",\
        "participantId":null,"expenseId":null,"data":null,"expense":null}],\
        "hasMore":false,"nextCursor":20}}}}
        """

        let response = try SuperJSON.decode(
            Spliit.ActivitiesListResponse.self, fromResponse: Data(envelope.utf8)
        )

        #expect(response.activities.count == 1)
        #expect(response.activities.first?.activityType == .unknown("ARCHIVE_GROUP"))
        #expect(response.activities.first?.activityType.isRecognised == false)
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
