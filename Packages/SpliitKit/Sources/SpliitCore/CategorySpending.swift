import Foundation
import SpliitAPI

/// What a group spent, broken down by the category each expense was filed under.
///
/// Folded on the client, from the expenses themselves. `groups.stats.get` answers three totals
/// and no more; the wider `groups.stats.overview` that the web app's `main` has does return a
/// category breakdown, but nothing serves it yet — not `spliit.app`, not the published image —
/// so a tab that asked for it would show nothing to everybody.
///
/// This is deliberately the *same* fold as that endpoint's `getSpendingByCategory`, down to the
/// zero-total filter and the descending sort, so the day `overview` is worth taking the numbers
/// do not move: the section stops being computed and starts being read, and agrees with itself
/// across the change.
public struct CategorySpending: Identifiable, Sendable, Hashable {

    /// The server's category ID. Zero stands for both the "General" category and an expense
    /// filed under nothing at all, which is the same conflation the web app makes — and
    /// harmless, because an uncategorised expense *is* a general one.
    public let categoryID: Int
    /// The server's own English words, untranslated. Turning them into something to read is the
    /// view's job — `ExpenseCategory.displayName` — because the translation is per-device and
    /// this type is not.
    public let grouping: String
    public let name: String
    /// Minor units, in the group's currency. Can be negative: a refund is an expense too.
    public let total: Int

    public var id: Int { categoryID }

    public init(categoryID: Int, grouping: String, name: String, total: Int) {
        self.categoryID = categoryID
        self.grouping = grouping
        self.name = name
        self.total = total
    }

    /// Sums `expenses` into one entry per category, biggest spend first.
    ///
    /// Reimbursements are left out, which is what makes this add up to the
    /// `totalGroupSpendings` the stats endpoint reports — settling up is not spending, and the
    /// three figures above this section already say so.
    ///
    /// Categories that net to exactly zero are dropped rather than drawn as a row with nothing
    /// in it. They contribute nothing to the sum either way, so the total still reconciles.
    public static func breakdown(of expenses: [ExpenseListItem]) -> [CategorySpending] {
        var fold = Fold()
        fold.add(expenses)
        return fold.breakdown
    }

    /// The same sum, a page at a time.
    ///
    /// For a caller paging through an expense list it has no reason to keep: the running totals
    /// are a handful of integers per category, so a group of two thousand expenses only ever
    /// holds the hundred currently being folded. `breakdown(of:)` is this with one page.
    public struct Fold {

        private var totals: [Int: CategorySpending] = [:]

        public init() {}

        public mutating func add(_ expenses: [ExpenseListItem]) {
            for expense in expenses where !expense.isReimbursement {
                let category = expense.category
                let id = category?.id ?? 0
                let running = totals[id]?.total ?? 0
                totals[id] = CategorySpending(
                    categoryID: id,
                    grouping: category?.grouping ?? "Uncategorized",
                    name: category?.name ?? "General",
                    total: running + expense.amount
                )
            }
        }

        public var breakdown: [CategorySpending] {
            totals.values
                .filter { $0.total != 0 }
                // Descending by spend, then by ID — which is not something anyone reads, and is
                // the point: `sorted(by:)` is not stable, so without a tiebreak two categories
                // on the same amount could swap places on a refresh that changed neither.
                .sorted {
                    $0.total == $1.total ? $0.categoryID < $1.categoryID : $0.total > $1.total
                }
        }
    }
}
