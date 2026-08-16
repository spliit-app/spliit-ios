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
    }
}

private struct ExpenseRow: View {
    let expense: ExpenseListItem
    let payerPosition: Int
    let formatter: MoneyFormatter

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        AdaptiveHStack(verticalAlignment: .top, spacing: 12) {
            CategoryIcon(category: expense.category)

            VStack(alignment: .leading, spacing: 2) {
                Text(expense.title)
                    .font(.callout)
                    .italic(expense.isReimbursement)
                    .accessibilityIdentifier(AccessibilityID.ExpenseList.rowTitle(expense.id))
                    // The glyph beside the title is the only place the category appears, and a
                    // picture cannot be read out. Hanging it here rather than on the icon keeps
                    // it to one element per row, and leaves the title's own label alone.
                    .accessibilityValue(categoryDescription)
                    .accessibilityHint(Text("Opens this expense for editing"))

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    // Who paid, in the colour they have on the balances screen. The names are
                    // spelled out beside it, so this is the glanceable half of the same fact.
                    ParticipantDot(position: payerPosition, size: 7)

                    Text(paidByDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        // One line, so a run of expenses stays a list you can scan rather than a
                        // stack of paragraphs — the full split is one tap away. Accessibility
                        // sizes get more room, where a single line would be three words.
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                        .accessibilityIdentifier(AccessibilityID.ExpenseList.rowPaidBy(expense.id))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: detailAlignment, spacing: 2) {
                Money(
                    value: formatter.string(minorUnits: expense.amount),
                    isReimbursement: expense.isReimbursement
                )
                .accessibilityIdentifier(AccessibilityID.ExpenseList.rowAmount(expense.id))

                Text(expense.expenseDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(.rect)
    }

    /// Empty rather than "Uncategorized" when the server sends no category: an accessibility
    /// value that says nothing is quieter than one that says nothing useful.
    private var categoryDescription: Text {
        guard let category = expense.category else { return Text(verbatim: "") }
        return Text(category.name)
    }

    /// Right-aligned against the amount column, until the row stacks and there is no column to
    /// align against.
    private var detailAlignment: HorizontalAlignment {
        dynamicTypeSize.isAccessibilitySize ? .leading : .trailing
    }

    private var paidByDescription: String {
        let names = expense.paidFor.map(\.participant.name).formatted(.list(type: .and))
        return String(localized: "Paid by \(expense.paidBy.name) for \(names)")
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
