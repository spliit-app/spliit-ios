import Foundation
import SpliitAPI
import Testing

@testable import SpliitCore

/// The cases are the web app's own (`src/lib/shares.test.ts`), so that a split here and a split
/// there agree to the minor unit — that is the whole point of the port.
@Suite("Expense shares")
struct ExpenseSharesTests {

    private func shares(
        id: String? = "e1",
        amount: Int,
        splitMode: SplitMode = .evenly,
        _ paidFor: [(String, Int)]
    ) -> [String: Int] {
        ExpenseShares.shares(
            expenseId: id,
            amount: amount,
            splitMode: splitMode,
            paidFor: paidFor.map { ExpenseDetails.PaidFor(participantId: $0.0, shares: $0.1) }
        )
    }

    @Test(
        "The whole amount is split and nothing more, whatever the mode",
        arguments: SplitMode.allCases
    )
    func splitsTheWholeAmount(splitMode: SplitMode) {
        let split = shares(
            amount: 9500, splitMode: splitMode, [("alice", 1), ("bob", 1), ("carol", 1)]
        )

        #expect(split.values.reduce(0, +) == 9500)
    }

    @Test("An even split leaves no stranded minor unit")
    func leavesNoStrandedUnit() {
        let split = shares(amount: 9500, [("alice", 1), ("bob", 1), ("carol", 1)])

        #expect(split.values.sorted() == [3166, 3167, 3167])
    }

    @Test("The stored shares are ignored when splitting evenly")
    func ignoresSharesWhenEven() {
        let split = shares(amount: 100, [("alice", 7), ("bob", 1)])

        #expect(split == ["alice": 50, "bob": 50])
    }

    @Test("Shares split proportionally")
    func splitsByShares() {
        let split = shares(amount: 100, splitMode: .byShares, [("alice", 1), ("bob", 2)])

        #expect(split == ["alice": 33, "bob": 67])
    }

    @Test("Amounts that already add up are left exactly as they are")
    func leavesExactAmountsAlone() {
        let split = shares(
            amount: 1000, splitMode: .byAmount, [("alice", 333), ("bob", 333), ("carol", 334)]
        )

        #expect(split == ["alice": 333, "bob": 333, "carol": 334])
    }

    /// A row that predates the server's sum check, or came in through an import: 60/20 of a
    /// 100 expense. Taken literally that splits 80 and leaks the rest; as a ratio it splits the
    /// whole amount 75/25.
    @Test("Percentages that do not add up to 100 are taken as a ratio")
    func normalisesPercentages() {
        let split = shares(amount: 100, splitMode: .byPercentage, [("alice", 6000), ("bob", 2000)])

        #expect(split == ["alice": 75, "bob": 25])
    }

    @Test("Amounts that do not add up to the total are taken as a ratio")
    func normalisesAmounts() {
        let split = shares(amount: 100, splitMode: .byAmount, [("alice", 30), ("bob", 30)])

        #expect(split.values.reduce(0, +) == 100)
    }

    @Test("An income — a negative amount — splits without losing a minor unit")
    func splitsAnIncome() {
        let split = shares(amount: -9500, [("alice", 1), ("bob", 1), ("carol", 1)])

        #expect(split.values.reduce(0, +) == -9500)
        #expect(split.values.sorted() == [-3167, -3167, -3166])
    }

    @Test("Shares adding up to zero give everyone nothing")
    func givesNothingForZeroShares() {
        let split = shares(amount: 100, splitMode: .byShares, [("alice", 0), ("bob", 0)])

        #expect(split == ["alice": 0, "bob": 0])
    }

    @Test("An expense nobody was paid for has no shares")
    func handlesNobody() {
        #expect(shares(amount: 100, []).isEmpty)
    }

    @Test("The order the rows come back in makes no difference")
    func ignoresRowOrder() {
        let rows = [("alice", 1), ("bob", 1), ("carol", 1)]

        #expect(shares(amount: 100, rows) == shares(amount: 100, rows.reversed()))
    }

    /// Fifty expenses, three people: the extra unit has to visit everyone. The rotation is what
    /// stops the same person absorbing it on every bill, and the hash is what decides the
    /// rotation — so this is the test that catches a hash the web app does not share.
    @Test("The leftover minor unit does not always go to the same participant")
    func rotatesTheLeftover() {
        let participants = ["alice", "bob", "carol"]
        var receivers: Set<String> = []

        for index in 0..<50 {
            let split = shares(id: "expense-\(index)", amount: 100, participants.map { ($0, 1) })
            for id in participants where split[id] == 34 { receivers.insert(id) }
        }

        #expect(receivers == Set(participants))
    }

    @Test("Without an ID the rotation starts at the first participant")
    func startsAtTheFirstWithoutAnID() {
        let split = shares(id: nil, amount: 100, [("bob", 1), ("alice", 1), ("carol", 1)])

        #expect(split["alice"] == 34)
        #expect(split.values.reduce(0, +) == 100)
    }

    /// The reference values are FNV-1a's published test vectors, and — for the last one — what
    /// the web app's `hashString` answers for an ID of its own shape. The rotation is only the
    /// same as the balances tab's while this hash is.
    @Test("The hash is FNV-1a over UTF-16 code units, as the web app computes it")
    func hashesLikeTheWebApp() {
        #expect(ExpenseShares.fnv1a("") == 0x811c_9dc5)
        #expect(ExpenseShares.fnv1a("a") == 0xe40c_292c)
        #expect(ExpenseShares.fnv1a("foobar") == 0xbf9c_f968)
        #expect(ExpenseShares.fnv1a("clx0v3kqf0001l3086v6y8t4c") == 0x5216_378f)
    }
}

@Suite("Expense form shares")
struct ExpenseFormDraftSharesTests {

    private let group = Group(
        id: "g1",
        name: "Weekend in Lisbon",
        information: nil,
        currency: "€",
        currencyCode: "EUR",
        createdAt: .now,
        participants: [
            .init(id: "ana", name: "Ana"),
            .init(id: "bruno", name: "Bruno"),
            .init(id: "chloe", name: "Chloé"),
        ]
    )

    private func draft(
        amount: String = "95.00",
        splitMode: SplitMode = .evenly,
        values: [String: String] = [:],
        included: [String] = ["ana", "bruno", "chloe"]
    ) -> ExpenseFormDraft {
        var form = ExpenseFormDraft(creatingIn: group, locale: Locale(identifier: "en_US"))
        form.amountText = amount
        form.splitMode = splitMode
        form.participants = form.participants.map {
            var participant = $0
            participant.isIncluded = included.contains($0.id)
            if let value = values[$0.id] { participant.valueText = value }
            return participant
        }
        return form
    }

    @Test("An even split of the total comes out in whole minor units that add up")
    func splitsTheTotalEvenly() throws {
        let split = try #require(draft().shares(expenseId: nil))

        #expect(split.values.sorted() == [3166, 3167, 3167])
    }

    @Test("Only the participants in the split get a share")
    func leavesOutTheExcluded() throws {
        let split = try #require(draft(included: ["ana", "bruno"]).shares(expenseId: nil))

        #expect(split == ["ana": 4750, "bruno": 4750])
    }

    @Test("Share counts and percentages are typed unscaled and still divide the total")
    func dividesByWhatWasTyped() throws {
        let byShares = try #require(
            draft(splitMode: .byShares, values: ["ana": "2", "bruno": "1", "chloe": "1"])
                .shares(expenseId: nil)
        )
        #expect(byShares == ["ana": 4750, "bruno": 2375, "chloe": 2375])

        let byPercentage = try #require(
            draft(splitMode: .byPercentage, values: ["ana": "50", "bruno": "30", "chloe": "20"])
                .shares(expenseId: nil)
        )
        #expect(byPercentage == ["ana": 4750, "bruno": 2850, "chloe": 1900])
    }

    /// The web form does the same: a field that does not parse weighs nothing, rather than
    /// taking the whole column down with it.
    @Test("A share that is not a number counts as nothing")
    func treatsGarbageAsNothing() throws {
        let split = try #require(
            draft(splitMode: .byShares, values: ["ana": "x", "bruno": "1", "chloe": "1"])
                .shares(expenseId: nil)
        )

        #expect(split == ["ana": 0, "bruno": 4750, "chloe": 4750])
    }

    @Test("There is nothing to divide until the total is a number")
    func waitsForATotal() {
        #expect(draft(amount: "").shares(expenseId: nil) == nil)
        #expect(draft(amount: "abc").shares(expenseId: nil) == nil)
    }

    /// The group's precision is what the total is parsed at, so a yen expense splits whole yen.
    @Test("The split is in the group's minor units")
    func splitsInTheGroupsUnits() throws {
        let yen = Group(
            id: "g2", name: "Tokyo", information: nil, currency: "¥", currencyCode: "JPY",
            createdAt: .now,
            participants: [.init(id: "ana", name: "Ana"), .init(id: "bruno", name: "Bruno")]
        )
        var form = ExpenseFormDraft(creatingIn: yen, locale: Locale(identifier: "en_US"))
        form.amountText = "1001"

        let split = try #require(form.shares(expenseId: nil))
        #expect(split.values.sorted() == [500, 501])
    }

    @Test("Share amounts are shown except on a reimbursement or a split by amount")
    func decidesWhenToShow() {
        #expect(draft().showsShareAmounts)
        #expect(draft(splitMode: .byShares).showsShareAmounts)
        #expect(draft(splitMode: .byPercentage).showsShareAmounts)
        #expect(!draft(splitMode: .byAmount).showsShareAmounts)

        var reimbursement = draft()
        reimbursement.isReimbursement = true
        #expect(!reimbursement.showsShareAmounts)
    }
}
