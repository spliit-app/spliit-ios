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

    /// Search keeps its own results rather than narrowing `expenses`, because the search tab and
    /// the expense tab are both on screen in the same breath — filtering the shared array would
    /// empty the list behind the search field.
    private(set) var searchResults: [ExpenseListItem] = []
    private(set) var searchLoad = LoadState()
    private(set) var hasMoreSearchResults = false
    private(set) var isLoadingMoreSearchResults = false

    /// What the results currently answer to, or `nil` when nothing has been asked. The server
    /// does the matching — `groups.expenses.list` takes a `filter`, matching titles
    /// case-insensitively — so a search covers the whole group, not just the pages paged in.
    private(set) var filter: String?

    /// The activity log, newest first. Loaded when its tab is first opened rather than with the
    /// rest of the group — see `loadActivitiesIfNeeded`.
    private(set) var activities: [Activity] = []
    private(set) var activitiesLoad = LoadState()
    private(set) var hasMoreActivities = false
    private(set) var isLoadingMoreActivities = false

    /// Who the person holding this phone has said they are in this group, as the four mutating
    /// procedures want it: a participant ID, or nil for a phone that has not said.
    ///
    /// The store this comes from belongs to the view layer, so the model is told rather than
    /// asking. `GroupDetailView` keeps it current, and it is what attributes the one write this
    /// model makes on its own — a delete waiting out its undo window.
    var actorID: String?

    private var nextCursor = 0
    private var nextSearchCursor = 0
    private var nextActivityCursor = 0
    private static let pageSize = 20

    /// How long a pause in typing counts as "done typing". `.task(id:)` cancels the previous
    /// search when the text changes again, so this sleep is what stops a request per keystroke.
    private static let searchDebounce = Duration.milliseconds(250)

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

    var isSearching: Bool {
        filter != nil
    }

    /// Nothing has been typed yet, so there is no result to report either way.
    var hasNoQuery: Bool {
        filter == nil
    }

    /// The search came back empty, which is a different sentence from "this group has no
    /// expenses" and has a different way out of it.
    var hasNoMatches: Bool {
        isSearching && searchResults.isEmpty && searchLoad.hasLoaded && !searchLoad.isLoading
    }

    var didFailToSearch: Bool {
        searchLoad.failedWithNothingToShow
    }

    /// Until the balances arrive, "everyone is settled up" would be a guess.
    var isLoadingBalances: Bool {
        balancesLoad.isAwaitingFirstResult
    }

    var didFailToLoadBalances: Bool {
        balancesLoad.failedWithNothingToShow
    }

    /// The group counts here as it does for the expenses: the log names participants, and until
    /// the group has arrived there is nobody to name.
    var isLoadingActivities: Bool {
        activities.isEmpty && (activitiesLoad.isAwaitingFirstResult || isLoadingGroup)
    }

    var didFailToLoadActivities: Bool {
        activitiesLoad.failedWithNothingToShow
    }

    /// What to put under "Couldn't load the activity", preferring the request that actually
    /// failed. Kept out of `loadFailure`, which the expense list shows inline: a log that
    /// wouldn't load is no reason to put a warning above somebody's expenses.
    var activitiesFailure: String? {
        activitiesLoad.failure ?? groupLoad.failure
    }

    func retry(using client: TRPCClient) async {
        await reload(using: client)
    }

    /// Expenses grouped into the sections the list shows, newest bucket first.
    var sections: [(group: ExpenseDateGroup, expenses: [ExpenseListItem])] {
        Self.sections(of: expenses)
    }

    /// Search results in the same buckets, so a result sits under the heading it would have had
    /// in the list it came from.
    var searchSections: [(group: ExpenseDateGroup, expenses: [ExpenseListItem])] {
        Self.sections(of: searchResults)
    }

    private static func sections(
        of items: [ExpenseListItem]
    ) -> [(group: ExpenseDateGroup, expenses: [ExpenseListItem])] {
        let buckets = Dictionary(grouping: items) {
            ExpenseDateGroup.containing($0.expenseDate)
        }
        return buckets
            .sorted { $0.key < $1.key }
            .map { (group: $0.key, expenses: $0.value) }
    }

    /// The log in its own buckets, newest first. `Dictionary(grouping:)` keeps the order it was
    /// given inside each bucket, and the server already sorted by time descending.
    var activitySections: [(group: ActivityDateGroup, activities: [Activity])] {
        // An activity of a kind this version does not know is dropped rather than drawn: there
        // is no honest sentence to put on the row, and a log missing a line it cannot describe
        // still reads correctly where a line reading "something happened" does not.
        let describable = activities.filter { $0.activityType.isRecognised }
        let buckets = Dictionary(grouping: describable) {
            ActivityDateGroup.containing($0.time)
        }
        return buckets
            .sorted { $0.key < $1.key }
            .map { (group: $0.key, activities: $0.value) }
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

    /// Refreshes everything that an expense change can affect — including an open search, whose
    /// results are a view of the same expenses and would otherwise still show the old title, and
    /// the activity log, which has just gained the line describing the change.
    func reloadAfterExpenseChange(using client: TRPCClient) async {
        async let expensesResult: Void = loadFirstPage(using: client)
        async let balancesResult: Void = loadBalances(using: client)
        async let searchResult: Void = reloadSearch(using: client)
        async let activitiesResult: Void = reloadActivities(using: client)
        _ = await (expensesResult, balancesResult, searchResult, activitiesResult)
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
            expenses = withoutPendingDeletion(response.expenses)
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
            expenses += withoutPendingDeletion(response.expenses).filter { !known.contains($0.id) }
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

    // MARK: - Activity

    /// Fetches the log the first time its tab is looked at.
    ///
    /// Deliberately not part of `reload`: the log is one tab of four and the only one nothing
    /// else on the screen needs, so loading it with the rest would put a request every group
    /// open pays for behind the three that draw the screen. A failure is not retried from here
    /// — the tab offers a button for that — and an empty log that loaded is left alone.
    func loadActivitiesIfNeeded(using client: TRPCClient) async {
        guard activities.isEmpty, activitiesLoad.isAwaitingFirstResult, !activitiesLoad.isLoading
        else { return }
        await loadFirstActivityPage(using: client)
    }

    func retryActivities(using client: TRPCClient) async {
        // The group may be what failed, and the log cannot name anybody without it.
        if group == nil { await loadGroup(using: client) }
        await loadFirstActivityPage(using: client)
    }

    func refreshActivities(using client: TRPCClient) async {
        await loadFirstActivityPage(using: client)
    }

    private func loadFirstActivityPage(using client: TRPCClient) async {
        activitiesLoad.begin()
        do {
            let response = try await client.call(
                Spliit.activities(groupId: groupID, cursor: 0, limit: Self.pageSize)
            )
            activities = response.activities
            hasMoreActivities = response.hasMore
            nextActivityCursor = response.nextCursor
            activitiesLoad.succeeded()
        } catch {
            activitiesLoad.failed(error.localizedDescription)
        }
    }

    func loadNextActivityPage(using client: TRPCClient) async {
        guard hasMoreActivities, !isLoadingMoreActivities else { return }
        isLoadingMoreActivities = true
        defer { isLoadingMoreActivities = false }

        do {
            let response = try await client.call(
                Spliit.activities(
                    groupId: groupID, cursor: nextActivityCursor, limit: Self.pageSize
                )
            )
            // The log grows at the top, so a page fetched after something new was recorded
            // repeats a row rather than skipping one. Same guard as the expense list.
            let known = Set(activities.map(\.id))
            activities += response.activities.filter { !known.contains($0.id) }
            hasMoreActivities = response.hasMore
            nextActivityCursor = response.nextCursor
        } catch {
            hasMoreActivities = false
        }
    }

    /// Re-reads the log after a change that wrote to it — but only if it has been read once.
    /// Fetching a log for a tab nobody has opened is a request for something nobody is looking
    /// at, and the tab will fetch it for itself the moment they do.
    private func reloadActivities(using client: TRPCClient) async {
        guard activitiesLoad.hasLoaded else { return }
        await loadFirstActivityPage(using: client)
    }

    // MARK: - Search

    /// Answers `text`, after a pause long enough to mean the typing has stopped.
    ///
    /// Driven by `.task(id:)`, which cancels the previous call on every keystroke — so the sleep
    /// below is only ever reached by the last one. Cancellation lands in `Task.sleep`, before any
    /// request goes out and before `filter` moves, which keeps a half-typed word from ever being
    /// the state the results are showing.
    func search(_ text: String, using client: TRPCClient) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let newFilter = trimmed.isEmpty ? nil : trimmed
        guard newFilter != filter else { return }

        do {
            try await Task.sleep(for: Self.searchDebounce)
        } catch {
            return
        }

        filter = newFilter
        guard let newFilter else {
            // An emptied field is not a search for nothing: drop the results and go back to
            // the prompt rather than asking the server for the whole group again.
            searchResults = []
            hasMoreSearchResults = false
            searchLoad = LoadState()
            return
        }
        await loadFirstSearchPage(matching: newFilter, using: client)
    }

    private func loadFirstSearchPage(
        matching query: String,
        using client: TRPCClient
    ) async {
        searchLoad.begin()
        do {
            let response = try await client.call(
                Spliit.expenses(groupId: groupID, cursor: 0, limit: Self.pageSize, filter: query)
            )
            // The field may have moved on while this was in flight; a stale page must not
            // become the answer to a question nobody asked.
            guard filter == query else { return }
            searchResults = withoutPendingDeletion(response.expenses)
            hasMoreSearchResults = response.hasMore
            nextSearchCursor = response.nextCursor
            searchLoad.succeeded()
        } catch {
            // A keystroke cancels the request the keystroke before it started, and a cancelled
            // request is not a failed one. Reporting it put "Couldn't search" on screen between
            // characters for anyone typing slower than the debounce.
            // Belt and braces with the client, which now rethrows a cancelled request as
            // `CancellationError` rather than dressing it up as a network failure: this task is
            // the cancelled one, so it has nothing to report either way.
            guard !Task.isCancelled, filter == query else { return }
            searchLoad.failed(error.localizedDescription)
        }
    }

    func loadNextSearchPage(using client: TRPCClient) async {
        guard let filter, hasMoreSearchResults, !isLoadingMoreSearchResults else { return }
        isLoadingMoreSearchResults = true
        defer { isLoadingMoreSearchResults = false }

        do {
            let response = try await client.call(
                Spliit.expenses(
                    groupId: groupID,
                    cursor: nextSearchCursor,
                    limit: Self.pageSize,
                    filter: filter
                )
            )
            guard self.filter == filter else { return }
            let known = Set(searchResults.map(\.id))
            searchResults += withoutPendingDeletion(response.expenses)
                .filter { !known.contains($0.id) }
            hasMoreSearchResults = response.hasMore
            nextSearchCursor = response.nextCursor
        } catch {
            hasMoreSearchResults = false
        }
    }

    /// Re-runs the current search, for when an expense has been edited or deleted underneath it.
    private func reloadSearch(using client: TRPCClient) async {
        guard let filter else { return }
        await loadFirstSearchPage(matching: filter, using: client)
    }

    // MARK: - Deleting, with a way back

    /// An expense that has left the screen but not yet the server.
    ///
    /// The row goes immediately, because a delete that waits five seconds to look deleted is a
    /// delete that gets tapped twice. The request is what waits — until the window closes, the
    /// screen is left, or another expense is deleted behind it.
    struct PendingDeletion: Equatable {
        let expense: ExpenseListItem
        /// Where the row was, so undo puts it back where it was rather than at the top.
        let listIndex: Int?
        let searchIndex: Int?
        /// Who the activity log should credit. Captured when the row was swiped rather than
        /// read when the request goes out, five seconds and possibly an identity change later.
        let actorID: String?
    }

    private(set) var pendingDeletion: PendingDeletion?
    private var deletionTask: Task<Void, Never>?

    /// Long enough to notice the row has gone and reach the button, short enough that leaving the
    /// screen is not the usual way the delete happens.
    private static let undoWindow = Duration.seconds(5)

    /// Takes the expense off the screen and starts the undo window.
    func requestDelete(_ expense: ExpenseListItem, using client: TRPCClient) async {
        // One at a time: deleting a second expense settles the first rather than queueing it,
        // which keeps "Undo" meaning the thing that just disappeared.
        await commitPendingDeletion(using: client)

        pendingDeletion = PendingDeletion(
            expense: expense,
            listIndex: expenses.firstIndex { $0.id == expense.id },
            searchIndex: searchResults.firstIndex { $0.id == expense.id },
            actorID: actorID
        )
        expenses.removeAll { $0.id == expense.id }
        searchResults.removeAll { $0.id == expense.id }

        deletionTask = Task { [weak self] in
            try? await Task.sleep(for: Self.undoWindow)
            guard !Task.isCancelled else { return }
            // Forget the handle before committing. `commitPendingDeletion` cancels whatever is
            // in `deletionTask`, which at this point is *this* task — and a cancelled task
            // carries the cancellation into the delete request, so the expense came back.
            self?.deletionTask = nil
            await self?.commitPendingDeletion(using: client)
        }
    }

    /// Puts the row back where it was. Nothing was ever sent, so there is nothing to undo on the
    /// server.
    func undoDelete() {
        deletionTask?.cancel()
        deletionTask = nil
        guard let pending = pendingDeletion else { return }
        pendingDeletion = nil

        if let index = pending.listIndex, index <= expenses.count {
            expenses.insert(pending.expense, at: index)
        }
        if let index = pending.searchIndex, index <= searchResults.count {
            searchResults.insert(pending.expense, at: index)
        }
    }

    /// Sends the delete the undo window was holding back.
    func commitPendingDeletion(using client: TRPCClient) async {
        guard let pending = pendingDeletion else { return }
        deletionTask?.cancel()
        deletionTask = nil
        pendingDeletion = nil

        do {
            _ = try await client.call(
                Spliit.deleteExpense(
                    groupId: groupID, expenseId: pending.expense.id, by: pending.actorID
                )
            )
            await reloadAfterExpenseChange(using: client)
        } catch {
            // The server still has it, so the screen should too.
            if let index = pending.listIndex, index <= expenses.count {
                expenses.insert(pending.expense, at: index)
            }
            if let index = pending.searchIndex, index <= searchResults.count {
                searchResults.insert(pending.expense, at: index)
            }
            expensesLoad.failed(error.localizedDescription)
        }
    }

    /// Closes the window on the way out of the screen.
    ///
    /// Detached, because this model is about to be torn down with the view and a delete the user
    /// has already asked for must not be lost to that. Nothing is left to report to, so a failure
    /// here leaves the expense in place — which is the safe direction to fail in.
    func flushPendingDeletion(using client: TRPCClient) {
        guard let pending = pendingDeletion else { return }
        deletionTask?.cancel()
        deletionTask = nil
        pendingDeletion = nil

        let groupID = groupID
        Task.detached {
            _ = try? await client.call(
                Spliit.deleteExpense(
                    groupId: groupID, expenseId: pending.expense.id, by: pending.actorID
                )
            )
        }
    }

    /// Drops anything waiting to be deleted out of a freshly loaded page: the server still has it,
    /// and a reload for some other reason must not put it back on screen.
    private func withoutPendingDeletion(_ items: [ExpenseListItem]) -> [ExpenseListItem] {
        guard let id = pendingDeletion?.expense.id else { return items }
        return items.filter { $0.id != id }
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
