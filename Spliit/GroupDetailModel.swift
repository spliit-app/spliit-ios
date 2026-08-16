import Foundation
import Observation
import SpliitAPI
import SpliitCore

/// Everything one group's screens need, loaded once and shared by both tabs so that adding an
/// expense updates the balances without either tab knowing about the other.
@Observable
final class GroupDetailModel {

    let groupID: String

    private(set) var group: Group?
    private(set) var expenses: [ExpenseListItem] = []
    private(set) var balances: [String: Balance] = [:]
    private(set) var reimbursements: [Reimbursement] = []
    private(set) var categories: [ExpenseCategory] = []

    /// One per request, because they run concurrently and finish in any order. Sharing a
    /// single flag is what made the list say "no expenses yet" the moment the *group* arrived.
    private(set) var groupLoad = LoadState()
    private(set) var expensesLoad = LoadState()
    private(set) var balancesLoad = LoadState()

    private(set) var isLoadingMore = false
    private(set) var hasMoreExpenses = false

    private var nextCursor = 0
    private static let pageSize = 20

    init(groupID: String) {
        self.groupID = groupID
    }

    var moneyFormatter: MoneyFormatter {
        MoneyFormatter(currencySymbol: group?.currency ?? "", currencyCode: group?.currencyCode)
    }

    func participant(_ id: String) -> Participant? {
        group?.participants.first { $0.id == id }
    }

    /// Where someone sits in the group's participant list, which is what their colour comes from.
    ///
    /// Zero for anyone the group doesn't know: a stale expense referencing a removed participant
    /// should be drawn in some colour rather than crash the screen it appears on.
    func participantPosition(_ id: String) -> Int {
        group?.participants.firstIndex { $0.id == id } ?? 0
    }

    /// Whatever went wrong most recently, preferring the failure that explains the most.
    var loadFailure: String? {
        groupLoad.failure ?? expensesLoad.failure ?? balancesLoad.failure
    }

    /// Nothing about the group is known yet: no name, no currency, nothing to lay a list out
    /// with.
    var isLoadingGroup: Bool {
        groupLoad.isAwaitingFirstResult && group == nil
    }

    /// The group itself never arrived, so there is nothing to show and nothing to add to.
    /// Distinct from "loaded, but empty", which is a perfectly good state.
    var didFailToLoad: Bool {
        !groupLoad.isAwaitingFirstResult && group == nil
    }

    /// The first page of expenses hasn't landed, so an empty list means "not yet", not "none".
    /// The group counts too: its currency is what the amounts are formatted with.
    var isLoadingExpenses: Bool {
        expenses.isEmpty && (expensesLoad.isAwaitingFirstResult || isLoadingGroup)
    }

    /// The expenses request failed with nothing to show — which is not a group without
    /// expenses, and must not be dressed up as one.
    var didFailToLoadExpenses: Bool {
        expensesLoad.failedWithNothingToShow
    }

    /// Until the balances arrive, "everyone is settled up" would be a guess.
    var isLoadingBalances: Bool {
        balancesLoad.isAwaitingFirstResult
    }

    var didFailToLoadBalances: Bool {
        balancesLoad.failedWithNothingToShow
    }

    func retry(using client: TRPCClient) async {
        await reload(using: client)
    }

    /// Expenses grouped into the sections the list shows, newest bucket first.
    var sections: [(group: ExpenseDateGroup, expenses: [ExpenseListItem])] {
        let buckets = Dictionary(grouping: expenses) {
            ExpenseDateGroup.containing($0.expenseDate)
        }
        return buckets
            .sorted { $0.key < $1.key }
            .map { (group: $0.key, expenses: $0.value) }
    }

    // MARK: - Loading

    func loadIfNeeded(using client: TRPCClient) async {
        guard group == nil else { return }
        await reload(using: client)
    }

    func reload(using client: TRPCClient) async {
        async let groupResult = loadGroup(using: client)
        async let expensesResult: Void = loadFirstPage(using: client)
        async let balancesResult: Void = loadBalances(using: client)
        async let categoriesResult: Void = loadCategories(using: client)
        _ = await (groupResult, expensesResult, balancesResult, categoriesResult)
    }

    /// Refreshes everything that an expense change can affect.
    func reloadAfterExpenseChange(using client: TRPCClient) async {
        async let expensesResult: Void = loadFirstPage(using: client)
        async let balancesResult: Void = loadBalances(using: client)
        _ = await (expensesResult, balancesResult)
    }

    private func loadGroup(using client: TRPCClient) async {
        groupLoad.begin()
        do {
            group = try await client.call(Spliit.group(id: groupID)).group
            if group == nil {
                groupLoad.failed(
                    String(localized: "This group no longer exists on this server.")
                )
            } else {
                groupLoad.succeeded()
            }
        } catch {
            groupLoad.failed(error.localizedDescription)
        }
    }

    private func loadFirstPage(using client: TRPCClient) async {
        expensesLoad.begin()
        do {
            let response = try await client.call(
                Spliit.expenses(groupId: groupID, cursor: 0, limit: Self.pageSize)
            )
            expenses = response.expenses
            hasMoreExpenses = response.hasMore
            nextCursor = response.nextCursor
            expensesLoad.succeeded()
        } catch {
            expensesLoad.failed(error.localizedDescription)
        }
    }

    func loadNextPage(using client: TRPCClient) async {
        guard hasMoreExpenses, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let response = try await client.call(
                Spliit.expenses(groupId: groupID, cursor: nextCursor, limit: Self.pageSize)
            )
            // Guard against a duplicate page if an expense was added while paging.
            let known = Set(expenses.map(\.id))
            expenses += response.expenses.filter { !known.contains($0.id) }
            hasMoreExpenses = response.hasMore
            nextCursor = response.nextCursor
        } catch {
            // Paging failures shouldn't replace what is already on screen.
            hasMoreExpenses = false
        }
    }

    private func loadBalances(using client: TRPCClient) async {
        balancesLoad.begin()
        do {
            let response = try await client.call(Spliit.balances(groupId: groupID))
            balances = response.balances
            reimbursements = response.reimbursements
            balancesLoad.succeeded()
        } catch {
            balancesLoad.failed(error.localizedDescription)
        }
    }

    private func loadCategories(using client: TRPCClient) async {
        guard categories.isEmpty else { return }
        categories = (try? await client.call(Spliit.categories()).categories) ?? []
    }

    // MARK: - Mutations

    func delete(expenseID: String, using client: TRPCClient) async {
        let removed = expenses
        expenses.removeAll { $0.id == expenseID }
        do {
            _ = try await client.call(
                Spliit.deleteExpense(groupId: groupID, expenseId: expenseID)
            )
            await reloadAfterExpenseChange(using: client)
        } catch {
            expenses = removed
            expensesLoad.failed(error.localizedDescription)
        }
    }

    func rename(to name: String) {
        guard let group else { return }
        self.group = Group(
            id: group.id,
            name: name,
            information: group.information,
            currency: group.currency,
            currencyCode: group.currencyCode,
            createdAt: group.createdAt,
            participants: group.participants
        )
    }
}
