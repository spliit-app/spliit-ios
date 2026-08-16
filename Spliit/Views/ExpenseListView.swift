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
            EmptyState(
                art: .icon("wifi.exclamationmark"),
                title: Text(errorTitle),
                description: Text(model.loadFailure ?? String(localized: "The server didn’t respond."))
            ) {
                Button("Try again") {
                    Task { await model.retry(using: app.client) }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(AccessibilityID.ExpenseList.retryButton)
            }
        } else if model.expenses.isEmpty {
            EmptyState(
                art: .icon("list.bullet"),
                title: Text("No expenses yet"),
                description: Text("Add the first expense and Spliit will work out who owes what.")
            ) {
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
                Section {
                    ForEach(section.expenses) { expense in
                        Button {
                            onEdit(expense.id)
                        } label: {
                            ExpenseRow(
                                expense: expense,
                                payerPosition: model.participantPosition(expense.paidBy.id),
                                formatter: model.moneyFormatter
                            )
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                Task { await model.delete(expenseID: expense.id, using: app.client) }
                            }
                        }
                    }
                } header: {
                    DateBucketHeader(title: section.group.title)
                }
            }

            if model.hasMoreExpenses {
                HStack {
                    Spacer()
                    ProgressView()
                        .accessibilityLabel(Text("Loading more expenses"))
                    Spacer()
                }
                .task { await model.loadNextPage(using: app.client) }
            }
        }
        .refreshable { await model.reloadAfterExpenseChange(using: app.client) }
        // A deleted expense should leave rather than vanish. Bound to the count, so editing an
        // expense in place does not animate the whole list along with it.
        .animation(Motion.base, value: model.expenses.count)
    }
}


extension ExpenseDateGroup {
    /// Section headings, matching the wording of the React Native app.
    ///
    /// A `String` rather than a `LocalizedStringKey` so `DateBucketHeader` can hand the words
    /// themselves to VoiceOver while the capitals stay on screen — see the note there.
    var title: String {
        switch self {
        case .upcoming: String(localized: "Upcoming")
        case .thisWeek: String(localized: "This week")
        case .earlierThisMonth: String(localized: "Earlier this month")
        case .lastMonth: String(localized: "Last month")
        case .earlierThisYear: String(localized: "Earlier this year")
        case .lastYear: String(localized: "Last year")
        case .older: String(localized: "Older")
        }
    }
}
