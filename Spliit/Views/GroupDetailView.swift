import SpliitAPI
import SpliitCore
import SwiftUI

/// A single group: its expenses and its balances, with the group-level actions in the toolbar.
struct GroupDetailView: View {

    @Environment(AppModel.self) private var app

    /// The instance this group is on. Every request from this screen goes through it: a group ID
    /// only means anything to the server that issued it.
    private var client: TRPCClient { app.client(forGroup: model.groupID) }
    @State private var model: GroupDetailModel
    @State private var tab: GroupTab = .expenses
    @State private var sheet: Sheet?
    @State private var query = ""
    /// What an intent knew about the expense before the form opened. Held apart from `Sheet` so
    /// the sheet's identity stays a plain string and it does not reopen when this changes.
    @State private var prefill: (title: String?, amount: String?)?

    init(groupID: String) {
        _model = State(initialValue: GroupDetailModel(groupID: groupID))
    }

    /// Named to stay clear of SwiftUI's own `Tab`, which `TabView` needs below.
    private enum GroupTab: Hashable {
        case expenses, balances, stats, information, search
    }

    private enum Sheet: Identifiable {
        case createExpense
        case editExpense(String)
        case settle(Reimbursement)
        case settings
        case identity

        var id: String {
            switch self {
            case .createExpense: "create"
            case .editExpense(let id): "edit-\(id)"
            case .settle(let reimbursement): "settle-\(reimbursement.from)-\(reimbursement.to)"
            case .settings: "settings"
            case .identity: "identity"
            }
        }
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Expenses", systemImage: "list.bullet", value: GroupTab.expenses) {
                ExpenseListView(
                    model: model,
                    onAdd: { sheet = .createExpense },
                    onEdit: { sheet = .editExpense($0) }
                )
                .trackScreen(.groupExpenses)
            }

            Tab("Balances", systemImage: "arrow.left.arrow.right", value: GroupTab.balances) {
                BalancesView(
                    model: model,
                    onSettle: { sheet = .settle($0) },
                    onIdentify: { sheet = .identity }
                )
                .trackScreen(.groupBalances)
            }

            // Beside the balances rather than beside the information, because it answers the
            // same question from the other end: that tab says where the group will settle, this
            // one says what it has actually spent.
            Tab("Totals", systemImage: "chart.pie", value: GroupTab.stats) {
                StatsView(model: model, onIdentify: { sheet = .identity })
                    .trackScreen(.groupStats)
            }

            Tab("Information", systemImage: "info.circle", value: GroupTab.information) {
                GroupInformationView(
                    model: model,
                    onEdit: { sheet = .settings },
                    onIdentify: { sheet = .identity }
                )
                .trackScreen(.groupInformation)
            }

            // The search role is what puts the magnifying glass in its own capsule beside the
            // tab bar, and what docks the field at the bottom of the screen — above the
            // keyboard, where the thumb already is — instead of in the navigation bar.
            Tab(value: GroupTab.search, role: .search) {
                ExpenseSearchView(
                    model: model,
                    query: $query,
                    isActive: tab == .search,
                    onEdit: { sheet = .editExpense($0) },
                    onCancel: {
                        query = ""
                        tab = .expenses
                    }
                )
            }
        }
        // Reading a long list of expenses is the one thing this screen is for, and the tab bar is
        // not needed while it happens. ROADMAP §4 asked for this at the start; nothing had
        // applied it.
        .tabBarMinimizeBehavior(.onScrollDown)
        .navigationTitle(model.group?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        // Leaving the screen closes the undo window rather than dropping the delete: this model
        // goes away with the view, and with it the request that was still waiting.
        .onDisappear { model.flushPendingDeletion(using: client) }
        // Restarting on every keystroke cancels the run before it, which is what makes the wait
        // inside `search` a debounce rather than a delay.
        .task(id: query) { await model.search(query, using: client) }
        .toolbar { toolbarContent }
        .sheet(item: $sheet, content: sheetContent)
        .task { await model.loadIfNeeded(using: client) }
        // The store belongs to the view layer, so the model is told who the user is rather than
        // asking. It is what attributes the delete that waits out its undo window, and it has to
        // survive both the group arriving — which is what makes an identity resolvable — and the
        // user answering the picker.
        .onAppear { model.actorID = activeParticipant?.participantID }
        .onChange(of: activeParticipant) { model.actorID = activeParticipant?.participantID }
        // The list pushed this screen because an intent asked for it; whatever else that intent
        // wanted is still waiting to be collected.
        .onAppear { collectRoutedIntent() }
        .onChange(of: Router.shared.destination) { collectRoutedIntent() }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if tab == .expenses {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add expense", systemImage: "plus") { sheet = .createExpense }
                    .accessibilityIdentifier(AccessibilityID.ExpenseList.addButton)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Edit group", systemImage: "pencil") { sheet = .settings }
                    .accessibilityIdentifier(AccessibilityID.GroupDetail.editGroupButton)

                if let url = shareURL {
                    ShareLink(item: url) {
                        Label("Share group", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier(AccessibilityID.GroupDetail.shareButton)
                }
            } label: {
                Label("Group actions", systemImage: "ellipsis")
            }
            .accessibilityIdentifier(AccessibilityID.GroupDetail.menuButton)
        }
    }

    /// A blank expense — divided however this group's expenses were last said to be divided —
    /// plus whatever an intent already knew.
    ///
    /// The amount arrives as text and stays text: `amountText` is parsed by the same code that
    /// reads the field, in the user's locale, so "12,50" means the same thing spoken as typed.
    private func prefilledDraft(for group: SpliitAPI.Group) -> ExpenseFormDraft {
        var draft = ExpenseFormDraft(
            creatingIn: group,
            paidBy: activeParticipant?.participantID,
            defaultSplit: app.recentGroups.defaultSplit(
                inGroup: model.groupID, participants: group.participants
            )
        )
        if let title = prefill?.title, !title.isEmpty { draft.title = title }
        if let amount = prefill?.amount, !amount.isEmpty { draft.amountText = amount }
        return draft
    }

    private func collectRoutedIntent() {
        switch Router.shared.takeDestination(for: model.groupID) {
        case .newExpense(_, let title, let amount):
            prefill = (title: title, amount: amount)
            sheet = .createExpense
        case .group, .none:
            break
        }
    }

    /// Who the user said they are in this group, resolved against the participants the group
    /// still has — someone who was removed is nobody in particular again.
    private var activeParticipant: ActiveParticipant? {
        ActiveParticipant.resolve(
            app.recentGroups.activeParticipant(inGroup: model.groupID),
            in: model.group?.participants ?? []
        )
    }

    /// The same link the web app shares, so it opens for anyone regardless of platform — and on
    /// the instance this group is actually on, which is the only one it can be opened from.
    private var shareURL: URL? {
        URL(
            string: "groups/\(model.groupID)",
            relativeTo: app.instanceURL(forGroup: model.groupID)
        )?.absoluteURL
    }

    @ViewBuilder
    private func sheetContent(_ sheet: Sheet) -> some View {
        switch sheet {
        case .createExpense:
            if let group = model.group {
                ExpenseFormView(
                    mode: .create,
                    group: group,
                    categories: model.categories,
                    draft: prefilledDraft(for: group),
                    onFinished: { await model.reloadAfterExpenseChange(using: client) }
                )
            }

        case .editExpense(let expenseID):
            if let group = model.group {
                ExpenseFormView(
                    mode: .edit(expenseID),
                    group: group,
                    categories: model.categories,
                    draft: nil,
                    onFinished: { await model.reloadAfterExpenseChange(using: client) }
                )
            }

        case .settle(let reimbursement):
            if let group = model.group {
                ExpenseFormView(
                    mode: .create,
                    group: group,
                    categories: model.categories,
                    draft: ExpenseFormDraft(
                        settling: reimbursement,
                        group: group,
                        title: String(localized: "Reimbursement")
                    ),
                    onFinished: { await noteSettlement() }
                )
            }

        case .identity:
            if let group = model.group {
                ActiveUserPickerView(
                    group: group,
                    selection: activeParticipant,
                    onSelect: {
                        app.recentGroups.setActiveParticipant($0, groupId: model.groupID)
                    }
                )
            }

        case .settings:
            GroupSettingsView(groupID: model.groupID) { name in
                model.rename(to: name)
                app.recentGroups.remember(
                    RecentGroup(groupId: model.groupID, groupName: name)
                )
                Task { await model.reload(using: client) }
            }
        }
    }

    /// A payment has just been recorded. Reload as any expense change does, and then see where
    /// the group stands: nothing left to pay is the app having finished the job it exists for,
    /// and the one moment in Spliit worth asking a person about.
    ///
    /// Read after the reload, and only when the reload worked. A failed balance load leaves the
    /// previous reimbursements in place rather than clearing them, so this cannot mistake an
    /// unanswered server for a settled group — but it would happily mistake one for the other
    /// if it stopped checking.
    private func noteSettlement() async {
        await model.reloadAfterExpenseChange(using: client)
        guard !model.didFailToLoadBalances, model.reimbursements.isEmpty else { return }
        app.reviewPrompt.record(.groupSettledUp)
    }
}
