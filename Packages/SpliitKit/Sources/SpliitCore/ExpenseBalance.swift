import SpliitAPI

/// Where a single expense leaves one participant: what they paid, less what their share of it
/// comes to.
///
/// The share comes from `ExpenseShares`, so these figures add up, expense by expense, to the
/// participant's total on the balances tab.
public enum ExpenseBalance {

    /// In the group's minor units: positive when the expense leaves the participant owed, negative
    /// when it leaves them owing, zero when it leaves them even — they paid exactly their own
    /// share, or their share came to nothing. Nil when they neither paid it nor were in it — not
    /// involved, which is a different thing from even.
    public static func of(_ participantID: String, in expense: ExpenseListItem) -> Int? {
        let shares = ExpenseShares.shares(
            expenseId: expense.id,
            amount: expense.amount,
            splitMode: expense.splitMode,
            paidFor: expense.paidFor
        )
        let share = shares[participantID]
        let didPay = expense.paidBy.id == participantID
        guard didPay || share != nil else { return nil }
        return (didPay ? expense.amount : 0) - (share ?? 0)
    }

    /// What a balance that is not zero means, which depends on what the expense was as much as
    /// on its sign.
    public enum Reading: Equatable, Sendable {
        /// A spend you paid for others, or one somebody else paid for you.
        case lent, borrowed
        /// A reimbursement settles a debt rather than creating one.
        case paidBack, wasPaidBack
        /// An income: whoever received it holds the others' shares, and has lent nobody anything.
        case isOwed, owes

        public init(balance: Int, of expense: ExpenseListItem) {
            let isOwed = balance > 0
            self = if expense.isReimbursement {
                isOwed ? .paidBack : .wasPaidBack
            } else if expense.amount < 0 {
                isOwed ? .isOwed : .owes
            } else {
                isOwed ? .lent : .borrowed
            }
        }
    }
}
