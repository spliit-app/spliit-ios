import SpliitAPI
import SpliitCore
import SwiftUI

/// A group's expenses, newest first, grouped into the same date buckets the old app used so an
/// upgrading user sees a familiar list.
struct ExpenseListView: View {

    @Environment(AppModel.self) private var app
    let model: GroupDetailModel
    let onAdd: () -> Void
    let onEdit: (String) -> Void

    var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoadingExpenses {
            ProgressView().controlSize(.large)
        } else if model.didFailToLoad || model.didFailToLoadExpenses {
            ContentUnavailableView {
                Label(errorTitle, systemImage: "wifi.exclamationmark")
            } description: {
                Text(model.loadFailure ?? String(localized: "The server didn’t respond."))
            } actions: {
                Button("Try again") {
                    Task { await model.retry(using: app.client) }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(AccessibilityID.ExpenseList.retryButton)
            }
        } else if model.expenses.isEmpty {
            ContentUnavailableView {
                Label("No expenses yet", systemImage: "list.bullet")
            } description: {
                Text("Add the first expense and Spliit will work out who owes what.")
            } actions: {
                Button("Add expense", action: onAdd)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(AccessibilityID.ExpenseList.emptyAddButton)
            }
        } else {
            list
        }
    }

    /// The group can arrive and its expenses still fail, so name whichever one is missing.
    private var errorTitle: LocalizedStringKey {
        model.didFailToLoad ? "Couldn’t load this group" : "Couldn’t load the expenses"
    }

    private var list: some View {
        List {
            if let failure = model.loadFailure {
                Section {
                    Label(failure, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(AccessibilityID.ExpenseList.loadFailed)
                }
            }

            ForEach(model.sections, id: \.group) { section in
                Section(section.group.title) {
                    ForEach(section.expenses) { expense in
                        Button {
                            onEdit(expense.id)
                        } label: {
                            ExpenseRow(expense: expense, formatter: model.moneyFormatter)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                Task { await model.delete(expenseID: expense.id, using: app.client) }
                            }
                        }
                    }
                }
            }

            if model.hasMoreExpenses {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .task { await model.loadNextPage(using: app.client) }
            }
        }
        .refreshable { await model.reloadAfterExpenseChange(using: app.client) }
    }
}

private struct ExpenseRow: View {
    let expense: ExpenseListItem
    let formatter: MoneyFormatter

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(expense.title)
                    .italic(expense.isReimbursement)
                    .accessibilityIdentifier(AccessibilityID.ExpenseList.rowTitle(expense.id))

                Text(paidByDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .accessibilityIdentifier(AccessibilityID.ExpenseList.rowPaidBy(expense.id))
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 4) {
                Text(formatter.string(minorUnits: expense.amount))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .accessibilityIdentifier(AccessibilityID.ExpenseList.rowAmount(expense.id))

                Text(expense.expenseDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
    }

    private var paidByDescription: String {
        let names = expense.paidFor.map(\.participant.name).formatted(.list(type: .and))
        return String(localized: "Paid by \(expense.paidBy.name) for \(names)")
    }
}

extension ExpenseDateGroup {
    /// Section headings, matching the wording of the React Native app.
    var title: LocalizedStringKey {
        switch self {
        case .upcoming: "Upcoming"
        case .thisWeek: "This week"
        case .earlierThisMonth: "Earlier this month"
        case .lastMonth: "Last month"
        case .earlierThisYear: "Earlier this year"
        case .lastYear: "Last year"
        case .older: "Older"
        }
    }
}
