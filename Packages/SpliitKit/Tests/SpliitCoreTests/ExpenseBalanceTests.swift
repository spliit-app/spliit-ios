import Testing

@testable import SpliitAPI
@testable import SpliitCore

@Suite("Expense balance")
struct ExpenseBalanceTests {

    private let ana = Participant(id: "ana", name: "Ana")
    private let bruno = Participant(id: "bruno", name: "Bruno")
    private let chloe = Participant(id: "chloe", name: "Chloé")
    private let dan = Participant(id: "dan", name: "Dan")

    private func expense(
        id: String = "e1",
        amount: Int,
        splitMode: SplitMode = .evenly,
        isReimbursement: Bool = false,
        paidBy: Participant,
        _ paidFor: [(Participant, Int)]
    ) -> ExpenseListItem {
        ExpenseListItem(
            id: id,
            title: "",
            amount: amount,
            isReimbursement: isReimbursement,
            splitMode: splitMode,
            paidBy: paidBy,
            paidFor: paidFor.map { ExpenseListItem.PaidFor(participant: $0.0, shares: $0.1) }
        )
    }

    @Test("Whoever paid is owed everyone else's share, and everyone else owes their own")
    func payerLendsTheRest() {
        let dinner = expense(
            amount: 12_000, paidBy: ana, [(ana, 100), (bruno, 100), (chloe, 100), (dan, 100)]
        )
        #expect(ExpenseBalance.of("ana", in: dinner) == 9_000)
        #expect(ExpenseBalance.of("bruno", in: dinner) == -3_000)
        #expect(ExpenseBalance.of("dan", in: dinner) == -3_000)
    }

    @Test("Someone the expense was neither paid by nor for is not involved")
    func outsiderIsNotInvolved() {
        let taxi = expense(amount: 4_000, paidBy: ana, [(ana, 100), (bruno, 100)])
        #expect(ExpenseBalance.of("chloe", in: taxi) == nil)
    }

    /// Paying for something you are not in is lending all of it, not being uninvolved.
    @Test("A payer left out of the split is owed the whole amount")
    func payerOutsideTheSplit() {
        let gift = expense(amount: 5_000, paidBy: ana, [(bruno, 100), (chloe, 100)])
        #expect(ExpenseBalance.of("ana", in: gift) == 5_000)
    }

    @Test("Paying only for yourself leaves you even, and still involved")
    func payingForYourself() {
        let coffee = expense(amount: 450, paidBy: ana, [(ana, 100)])
        #expect(ExpenseBalance.of("ana", in: coffee) == 0)
    }

    /// The figures have to be the balances tab's, cent for cent, or a row and the tab would
    /// disagree about who carries the odd cent. Whatever the rotation, they sum to nothing.
    @Test("An uneven split nets to zero across the group", arguments: ["e1", "e2", "e3", "x"])
    func netsToZero(id: String) {
        let museum = expense(
            id: id, amount: 10_000, paidBy: chloe, [(ana, 100), (bruno, 100), (chloe, 100)]
        )
        let total = [ana, bruno, chloe, dan]
            .compactMap { ExpenseBalance.of($0.id, in: museum) }
            .reduce(0, +)
        #expect(total == 0)
    }

    @Test("Each share follows the split mode")
    func followsTheSplitMode() {
        let airbnb = expense(
            amount: 48_000, splitMode: .byShares, paidBy: ana, [(ana, 200), (bruno, 100), (chloe, 100)]
        )
        #expect(ExpenseBalance.of("ana", in: airbnb) == 24_000)
        #expect(ExpenseBalance.of("bruno", in: airbnb) == -12_000)

        let tickets = expense(
            amount: 8_800, splitMode: .byAmount, paidBy: bruno, [(ana, 3_000), (bruno, 5_800)]
        )
        #expect(ExpenseBalance.of("ana", in: tickets) == -3_000)
        #expect(ExpenseBalance.of("bruno", in: tickets) == 3_000)
    }

    @Test("Paying someone back moves both balances by the whole amount")
    func reimbursement() {
        let payback = expense(
            amount: 6_769, isReimbursement: true, paidBy: bruno, [(ana, 100)]
        )
        #expect(ExpenseBalance.of("bruno", in: payback) == 6_769)
        #expect(ExpenseBalance.of("ana", in: payback) == -6_769)
        #expect(ExpenseBalance.of("chloe", in: payback) == nil)
    }

    /// An income is a negative amount: whoever received it holds everyone else's share.
    @Test("An income leaves whoever received it owing the others their share")
    func income() {
        let refund = expense(amount: -3_000, paidBy: ana, [(ana, 100), (bruno, 100), (chloe, 100)])
        #expect(ExpenseBalance.of("ana", in: refund) == -2_000)
        #expect(ExpenseBalance.of("bruno", in: refund) == 1_000)
    }

    /// In the split for nothing is still in it: "Paid by Bruno for Ana and Bruno" names them.
    @Test("A share that comes to nothing leaves you even, not uninvolved")
    func zeroShare() {
        let snack = expense(
            amount: 1_000, splitMode: .byShares, paidBy: bruno, [(ana, 0), (bruno, 100)]
        )
        #expect(ExpenseBalance.of("ana", in: snack) == 0)
    }

    @Test("A balance reads by what the expense was, not only by its sign")
    func reading() {
        let dinner = expense(amount: 9_000, paidBy: ana, [(ana, 100), (bruno, 100)])
        #expect(ExpenseBalance.Reading(balance: 4_500, of: dinner) == .lent)
        #expect(ExpenseBalance.Reading(balance: -4_500, of: dinner) == .borrowed)

        let payback = expense(amount: 6_769, isReimbursement: true, paidBy: bruno, [(ana, 100)])
        #expect(ExpenseBalance.Reading(balance: 6_769, of: payback) == .paidBack)
        #expect(ExpenseBalance.Reading(balance: -6_769, of: payback) == .wasPaidBack)

        // Ana received the refund and holds the others' shares; Bruno lent nobody anything.
        let refund = expense(amount: -3_000, paidBy: ana, [(ana, 100), (bruno, 100), (chloe, 100)])
        #expect(ExpenseBalance.Reading(balance: -2_000, of: refund) == .owes)
        #expect(ExpenseBalance.Reading(balance: 1_000, of: refund) == .isOwed)
    }
}
