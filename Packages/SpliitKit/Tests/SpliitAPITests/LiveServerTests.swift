import Foundation
import Testing

@testable import SpliitAPI

/// Round-trips against a real Spliit instance.
///
/// Recorded fixtures prove we can *read* what the server sends. Only a live server proves we
/// can *write* something it accepts — in particular that our superjson envelope, which omits
/// the `meta.v` field the server's own serializer emits, still deserializes into a real `Date`.
///
/// Skipped unless `SPLIIT_LIVE_BASE_URL` is set:
///
///     make e2e-up
///     SPLIIT_LIVE_BASE_URL=http://localhost:3009/ swift test --filter Live
@Suite("Live server", .enabled(if: LiveServer.baseURL != nil))
struct LiveServerTests {

    private var client: TRPCClient {
        get throws { TRPCClient(baseURL: try #require(LiveServer.baseURL)) }
    }

    @Test("Categories load from a real instance")
    func fetchesCategories() async throws {
        let response = try await client.call(Spliit.categories())

        #expect(response.categories.contains { $0.name == "General" })
    }

    @Test("A group survives a create-then-read round trip")
    func createsAndReadsGroup() async throws {
        let client = try client
        let name = "Round trip \(UUID().uuidString.prefix(8))"

        let created = try await client.call(
            Spliit.createGroup(
                GroupFormValues(
                    name: name,
                    information: "Created by the Swift client test suite.",
                    currency: "€",
                    currencyCode: "EUR",
                    participants: [.init(name: "Ana"), .init(name: "Bruno")]
                )
            )
        )

        let fetched = try await client.call(Spliit.group(id: created.groupId))
        let group = try #require(fetched.group)

        #expect(group.name == name)
        #expect(group.currency == "€")
        #expect(group.currencyCode == "EUR")
        #expect(group.participants.map(\.name).sorted() == ["Ana", "Bruno"])
    }

    /// The one that matters: if the server rejected or mangled our date annotation, the stored
    /// `expenseDate` would come back as something other than the day we sent.
    @Test("An expense round-trips with its date, amount and split intact")
    func createsAndReadsExpense() async throws {
        let client = try client

        let created = try await client.call(
            Spliit.createGroup(
                GroupFormValues(
                    name: "Expense round trip \(UUID().uuidString.prefix(8))",
                    currency: "$",
                    currencyCode: "USD",
                    participants: [.init(name: "Dana"), .init(name: "Eli")]
                )
            )
        )
        let group = try #require(try await client.call(Spliit.group(id: created.groupId)).group)
        let dana = try #require(group.participants.first { $0.name == "Dana" })
        let eli = try #require(group.participants.first { $0.name == "Eli" })

        // Midday UTC on a fixed day, so a timezone slip would move the calendar date.
        let expenseDate = try #require(
            Date.ISO8601FormatStyle().parseStrategy.parse("2026-03-17T12:00:00Z") as Date?
        )

        let expense = try await client.call(
            Spliit.createExpense(
                groupId: group.id,
                ExpenseFormValues(
                    title: "Round trip dinner",
                    expenseDate: expenseDate,
                    amount: 4250,
                    paidBy: dana.id,
                    paidFor: [
                        .init(participant: dana.id, shares: 100),
                        .init(participant: eli.id, shares: 100),
                    ],
                    notes: "Sent by the Swift client."
                )
            )
        )

        let fetched = try await client.call(
            Spliit.expense(groupId: group.id, expenseId: expense.expenseId)
        ).expense

        #expect(fetched.title == "Round trip dinner")
        #expect(fetched.amount == 4250)
        #expect(fetched.paidById == dana.id)
        #expect(fetched.paidFor.count == 2)
        #expect(fetched.notes == "Sent by the Swift client.")
        #expect(fetched.splitMode == .evenly)

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        #expect(utc.dateComponents([.year, .month, .day], from: fetched.expenseDate)
            == DateComponents(year: 2026, month: 3, day: 17))
    }

    /// The two halves the server has to accept: a conversion written and read back with its
    /// decimal rate intact, and the same expense moved to the group's own currency, which only
    /// clears the columns because the fields go out as explicit nulls.
    @Test("An expense paid in another currency keeps its rate, and gives it up when cleared")
    func createsAndClearsAConversion() async throws {
        let client = try client

        let created = try await client.call(
            Spliit.createGroup(
                GroupFormValues(
                    name: "Conversion round trip \(UUID().uuidString.prefix(8))",
                    currency: "€",
                    currencyCode: "EUR",
                    participants: [.init(name: "Dana"), .init(name: "Eli")]
                )
            )
        )
        let group = try #require(try await client.call(Spliit.group(id: created.groupId)).group)
        let dana = try #require(group.participants.first { $0.name == "Dana" })
        let eli = try #require(group.participants.first { $0.name == "Eli" })

        let paidFor: [ExpenseFormValues.PaidFor] = [
            .init(participant: dana.id, shares: 100),
            .init(participant: eli.id, shares: 100),
        ]

        let expense = try await client.call(
            Spliit.createExpense(
                groupId: group.id,
                ExpenseFormValues(
                    title: "Dinner in dollars",
                    expenseDate: .now,
                    amount: 3696,
                    paidBy: dana.id,
                    paidFor: paidFor,
                    originalAmount: 4000,
                    originalCurrency: "USD",
                    conversionRate: Decimal(string: "0.9241")
                )
            )
        )

        let converted = try await client.call(
            Spliit.expense(groupId: group.id, expenseId: expense.expenseId)
        ).expense

        #expect(converted.amount == 3696)
        #expect(converted.originalAmount == 4000)
        #expect(converted.originalCurrency == "USD")
        #expect(converted.conversionRate?.value == Decimal(string: "0.9241"))

        _ = try await client.call(
            Spliit.updateExpense(
                groupId: group.id,
                expenseId: expense.expenseId,
                ExpenseFormValues(
                    title: "Dinner in euros",
                    expenseDate: .now,
                    amount: 3696,
                    paidBy: dana.id,
                    paidFor: paidFor
                )
            )
        )

        let cleared = try await client.call(
            Spliit.expense(groupId: group.id, expenseId: expense.expenseId)
        ).expense

        // The currency is the field that can be cleared, and the field that decides. The schema
        // takes null only here: `originalAmount` and `conversionRate` accept a number or an empty
        // string and reject null, so what they held stays in the database with nothing reading it.
        #expect(cleared.originalCurrency == nil)
    }

    @Test("Balances come back consistent after an expense is added")
    func readsBalances() async throws {
        let client = try client

        let created = try await client.call(
            Spliit.createGroup(
                GroupFormValues(
                    name: "Balances \(UUID().uuidString.prefix(8))",
                    currency: "$",
                    participants: [.init(name: "Dana"), .init(name: "Eli")]
                )
            )
        )
        let group = try #require(try await client.call(Spliit.group(id: created.groupId)).group)
        let dana = try #require(group.participants.first { $0.name == "Dana" })
        let eli = try #require(group.participants.first { $0.name == "Eli" })

        _ = try await client.call(
            Spliit.createExpense(
                groupId: group.id,
                ExpenseFormValues(
                    title: "Groceries",
                    expenseDate: .now,
                    amount: 5000,
                    paidBy: dana.id,
                    paidFor: [
                        .init(participant: dana.id, shares: 100),
                        .init(participant: eli.id, shares: 100),
                    ]
                )
            )
        )

        let balances = try await client.call(Spliit.balances(groupId: group.id))

        #expect(balances.balances[dana.id]?.total == 2500)
        #expect(balances.balances[eli.id]?.total == -2500)
        #expect(balances.reimbursements == [
            Reimbursement(from: eli.id, to: dana.id, amount: 2500)
        ])
    }

    /// What the stats tab claims in its footer, checked against a server rather than against
    /// our reading of the web app: settling up is spending that does not count.
    ///
    /// The fixtures prove the three numbers decode. Only a live instance proves that leaving
    /// `participantId` out is a question the server accepts — a null there is a 400 — and that
    /// it answers a different one from naming somebody who spent nothing.
    @Test("Stats count the expenses and not the settling up")
    func readsStats() async throws {
        let client = try client

        let created = try await client.call(
            Spliit.createGroup(
                GroupFormValues(
                    name: "Stats \(UUID().uuidString.prefix(8))",
                    currency: "$",
                    currencyCode: "USD",
                    participants: [.init(name: "Dana"), .init(name: "Eli")]
                )
            )
        )
        let group = try #require(try await client.call(Spliit.group(id: created.groupId)).group)
        let dana = try #require(group.participants.first { $0.name == "Dana" })
        let eli = try #require(group.participants.first { $0.name == "Eli" })

        let evenly: [ExpenseFormValues.PaidFor] = [
            .init(participant: dana.id, shares: 100),
            .init(participant: eli.id, shares: 100),
        ]

        _ = try await client.call(
            Spliit.createExpense(
                groupId: group.id,
                ExpenseFormValues(
                    title: "Groceries",
                    expenseDate: .now,
                    amount: 5000,
                    paidBy: dana.id,
                    paidFor: evenly
                )
            )
        )
        _ = try await client.call(
            Spliit.createExpense(
                groupId: group.id,
                ExpenseFormValues(
                    title: "Reimbursement",
                    expenseDate: .now,
                    amount: 2500,
                    paidBy: eli.id,
                    paidFor: [.init(participant: dana.id, shares: 100)],
                    isReimbursement: true
                )
            )
        )

        let group_ = try await client.call(Spliit.stats(groupId: group.id))
        #expect(group_.totalGroupSpendings == 5000)
        #expect(group_.totalParticipantSpendings == nil)
        #expect(group_.totalParticipantShare == nil)

        let hers = try await client.call(
            Spliit.stats(groupId: group.id, participantId: dana.id)
        )
        #expect(hers.totalGroupSpendings == 5000)
        #expect(hers.totalParticipantSpendings == 5000)
        #expect(hers.totalParticipantShare == 2500)

        let his = try await client.call(Spliit.stats(groupId: group.id, participantId: eli.id))
        #expect(his.totalParticipantSpendings == 0, "The 2500 Eli handed over was settling up.")
        #expect(his.totalParticipantShare == 2500)
    }

    @Test("An expense can be updated and then deleted")
    func updatesAndDeletesExpense() async throws {
        let client = try client

        let created = try await client.call(
            Spliit.createGroup(
                GroupFormValues(
                    name: "Edit \(UUID().uuidString.prefix(8))",
                    currency: "$",
                    participants: [.init(name: "Dana"), .init(name: "Eli")]
                )
            )
        )
        let group = try #require(try await client.call(Spliit.group(id: created.groupId)).group)
        let dana = try #require(group.participants.first { $0.name == "Dana" })

        let expense = try await client.call(
            Spliit.createExpense(
                groupId: group.id,
                ExpenseFormValues(
                    title: "Before",
                    expenseDate: .now,
                    amount: 1000,
                    paidBy: dana.id,
                    paidFor: [.init(participant: dana.id, shares: 100)]
                )
            )
        )

        _ = try await client.call(
            Spliit.updateExpense(
                groupId: group.id,
                expenseId: expense.expenseId,
                ExpenseFormValues(
                    title: "After",
                    expenseDate: .now,
                    amount: 2000,
                    paidBy: dana.id,
                    paidFor: [.init(participant: dana.id, shares: 100)]
                )
            )
        )

        let updated = try await client.call(
            Spliit.expense(groupId: group.id, expenseId: expense.expenseId)
        ).expense
        #expect(updated.title == "After")
        #expect(updated.amount == 2000)

        _ = try await client.call(
            Spliit.deleteExpense(groupId: group.id, expenseId: expense.expenseId)
        )

        let remaining = try await client.call(Spliit.expenses(groupId: group.id))
        #expect(remaining.expenses.isEmpty)
    }

    @Test("A group update returning undefined is handled")
    func updatesGroup() async throws {
        let client = try client

        let created = try await client.call(
            Spliit.createGroup(
                GroupFormValues(
                    name: "Rename me",
                    currency: "$",
                    participants: [.init(name: "Dana")]
                )
            )
        )
        let group = try #require(try await client.call(Spliit.group(id: created.groupId)).group)

        // `groups.update` returns nothing, which superjson sends as an annotated null.
        _ = try await client.call(
            Spliit.updateGroup(
                id: group.id,
                values: GroupFormValues(
                    name: "Renamed",
                    currency: "$",
                    participants: group.participants.map { .init(id: $0.id, name: $0.name) }
                )
            )
        )

        let reloaded = try await client.call(Spliit.group(id: group.id))
        #expect(reloaded.group?.name == "Renamed")
    }

    /// The log is written by the server as a side effect of every other mutation, so the only
    /// way to know our writes are recorded — and recorded against the right person — is to make
    /// some and read them back. Nothing local proves the `participantId` we send survives.
    @Test("Every kind of change writes an attributed entry to the activity log")
    func recordsActivities() async throws {
        let client = try client

        let created = try await client.call(
            Spliit.createGroup(
                GroupFormValues(
                    name: "Log \(UUID().uuidString.prefix(8))",
                    currency: "$",
                    participants: [.init(name: "Dana"), .init(name: "Eli")]
                )
            )
        )
        let group = try #require(try await client.call(Spliit.group(id: created.groupId)).group)
        let dana = try #require(group.participants.first { $0.name == "Dana" })
        let eli = try #require(group.participants.first { $0.name == "Eli" })

        let values = { (title: String) in
            ExpenseFormValues(
                title: title,
                expenseDate: .now,
                amount: 1000,
                paidBy: dana.id,
                paidFor: [.init(participant: dana.id, shares: 100)]
            )
        }

        let kept = try await client.call(
            Spliit.createExpense(groupId: group.id, values("Kept"), by: dana.id)
        )
        _ = try await client.call(
            Spliit.updateExpense(
                groupId: group.id, expenseId: kept.expenseId, values("Kept, renamed"), by: eli.id
            )
        )
        let doomed = try await client.call(
            Spliit.createExpense(groupId: group.id, values("Doomed"), by: eli.id)
        )
        _ = try await client.call(
            Spliit.deleteExpense(groupId: group.id, expenseId: doomed.expenseId, by: dana.id)
        )
        _ = try await client.call(
            Spliit.updateGroup(
                id: group.id,
                values: GroupFormValues(
                    name: "Log, renamed",
                    currency: "$",
                    participants: group.participants.map { .init(id: $0.id, name: $0.name) }
                ),
                by: eli.id
            )
        )

        let log = try await client.call(Spliit.activities(groupId: group.id)).activities

        // Newest first, so this is the reverse of the order they were made in.
        #expect(
            log.map(\.activityType) == [
                .updateGroup, .deleteExpense, .createExpense, .updateExpense, .createExpense,
            ]
        )
        #expect(log.map(\.participantId) == [eli.id, dana.id, eli.id, eli.id, dana.id])

        // `data` holds the title as it was at the time, not as it is now: the entry for the
        // creation still says "Kept" although the expense has since been renamed.
        #expect(log.map(\.title) == [nil, "Doomed", "Doomed", "Kept, renamed", "Kept"])

        // The expense the log points at is what decides whether a row can be opened, and the
        // deleted one's entries must not claim it can.
        let doomedEntries = log.filter { $0.expenseId == doomed.expenseId }
        #expect(doomedEntries.count == 2)
        #expect(doomedEntries.allSatisfy { !$0.expenseStillExists })

        let keptEntries = log.filter { $0.expenseId == kept.expenseId }
        #expect(keptEntries.count == 2)
        #expect(keptEntries.allSatisfy { $0.expenseStillExists })
    }

    /// Paging the log is what the tab does when someone scrolls, and the cursor is an offset
    /// rather than a key — so a limit smaller than the log is the only thing that proves the
    /// second page is the rest of it rather than the first page again.
    @Test("The activity log pages with an offset cursor")
    func pagesActivities() async throws {
        let client = try client

        let created = try await client.call(
            Spliit.createGroup(
                GroupFormValues(
                    name: "Paging \(UUID().uuidString.prefix(8))",
                    currency: "$",
                    participants: [.init(name: "Dana")]
                )
            )
        )
        let group = try #require(try await client.call(Spliit.group(id: created.groupId)).group)
        let dana = try #require(group.participants.first)

        for index in 1...5 {
            _ = try await client.call(
                Spliit.createExpense(
                    groupId: group.id,
                    ExpenseFormValues(
                        title: "Expense \(index)",
                        expenseDate: .now,
                        amount: 100 * index,
                        paidBy: dana.id,
                        paidFor: [.init(participant: dana.id, shares: 100)]
                    ),
                    by: dana.id
                )
            )
        }

        let first = try await client.call(Spliit.activities(groupId: group.id, limit: 2))
        #expect(first.activities.count == 2)
        #expect(first.hasMore)
        #expect(first.nextCursor == 2)

        let second = try await client.call(
            Spliit.activities(groupId: group.id, cursor: first.nextCursor, limit: 2)
        )
        #expect(second.activities.count == 2)
        #expect(second.hasMore)
        #expect(Set(second.activities.map(\.id)).isDisjoint(with: first.activities.map(\.id)))

        let last = try await client.call(
            Spliit.activities(groupId: group.id, cursor: second.nextCursor, limit: 2)
        )
        #expect(last.activities.count == 1)
        #expect(last.hasMore == false)
    }

    /// The four mutating procedures take an optional `participantId`, and this app leaves it out
    /// until someone has said who they are. Left out has to mean "unattributed", not "rejected".
    @Test("A change made by nobody in particular is still recorded")
    func recordsUnattributedActivity() async throws {
        let client = try client

        let created = try await client.call(
            Spliit.createGroup(
                GroupFormValues(
                    name: "Anon \(UUID().uuidString.prefix(8))",
                    currency: "$",
                    participants: [.init(name: "Dana")]
                )
            )
        )
        let group = try #require(try await client.call(Spliit.group(id: created.groupId)).group)
        let dana = try #require(group.participants.first)

        _ = try await client.call(
            Spliit.createExpense(
                groupId: group.id,
                ExpenseFormValues(
                    title: "Who paid?",
                    expenseDate: .now,
                    amount: 500,
                    paidBy: dana.id,
                    paidFor: [.init(participant: dana.id, shares: 100)]
                )
            )
        )

        let entry = try #require(
            try await client.call(Spliit.activities(groupId: group.id)).activities.first
        )
        #expect(entry.activityType == .createExpense)
        #expect(entry.participantId == nil)
        #expect(entry.title == "Who paid?")
    }

    @Test("A missing group surfaces as a typed server error")
    func reportsNotFound() async throws {
        await #expect(throws: TRPCServerError.self) {
            _ = try await client.call(Spliit.groupDetails(id: "definitely-not-a-group"))
        }
    }

    @Test("An unknown group reads as an absent group rather than an error")
    func reportsAbsentGroup() async throws {
        let response = try await client.call(Spliit.group(id: "definitely-not-a-group"))

        #expect(response.group == nil)
    }
}

enum LiveServer {
    static var baseURL: URL? {
        guard let raw = ProcessInfo.processInfo.environment["SPLIIT_LIVE_BASE_URL"] else {
            return nil
        }
        return URL(string: raw)
    }
}
