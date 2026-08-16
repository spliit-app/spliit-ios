import SpliitAPI
import SpliitCore
import SwiftUI

/// A single group: its expenses and its balances, with the group-level actions in the toolbar.
struct GroupDetailView: View {

    @Environment(AppModel.self) private var app
    @State private var model: GroupDetailModel
    @State private var tab: GroupTab = .expenses
    @State private var sheet: Sheet?
    @State private var query = ""

    init(groupID: String) {
        _model = State(initialValue: GroupDetailModel(groupID: groupID))
    }

    /// Named to stay clear of SwiftUI's own `Tab`, which `TabView` needs below.
    private enum GroupTab: Hashable {
        case expenses, balances, search
    }

    private enum Sheet: Identifiable {
        case createExpense
        case editExpense(String)
        case settle(Reimbursement)
        case settings

        var id: String {
            switch self {
            case .createExpense: "create"
            case .editExpense(let id): "edit-\(id)"
            case .settle(let reimbursement): "settle-\(reimbursement.from)-\(reimbursement.to)"
            case .settings: "settings"
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
                .trackScreen(.groupExpenses, properties: ["groupId": model.groupID])
            }

            Tab("Balances", systemImage: "arrow.left.arrow.right", value: GroupTab.balances) {
                BalancesView(model: model, onSettle: { sheet = .settle($0) })
                    .trackScreen(.groupBalances, properties: ["groupId": model.groupID])
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
        .onDisappear { model.flushPendingDeletion(using: app.client) }
        // Restarting on every keystroke cancels the run before it, which is what makes the wait
        // inside `search` a debounce rather than a delay.
        .task(id: query) { await model.search(query, using: app.client) }
        .toolbar { toolbarContent }
        .sheet(item: $sheet, content: sheetContent)
        .task { await model.loadIfNeeded(using: app.client) }
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

    /// The same link the web app shares, so it opens for anyone regardless of platform.
    private var shareURL: URL? {
        URL(string: "groups/\(model.groupID)", relativeTo: app.settings.baseURL)?.absoluteURL
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
                    draft: ExpenseFormDraft(creatingIn: group),
                    onFinished: { await model.reloadAfterExpenseChange(using: app.client) }
                )
            }

        case .editExpense(let expenseID):
            if let group = model.group {
                ExpenseFormView(
                    mode: .edit(expenseID),
                    group: group,
                    categories: model.categories,
                    draft: nil,
                    onFinished: { await model.reloadAfterExpenseChange(using: app.client) }
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
                    onFinished: { await model.reloadAfterExpenseChange(using: app.client) }
                )
            }

        case .settings:
            GroupSettingsView(groupID: model.groupID) { name in
                model.rename(to: name)
                app.recentGroups.remember(
                    RecentGroup(groupId: model.groupID, groupName: name)
                )
                Task { await model.reload(using: app.client) }
            }
        }
    }
}
