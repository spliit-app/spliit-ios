import SpliitAPI
import SpliitCore
import SwiftUI

/// One expense, as it appears in a list of them.
///
/// Shared by the expenses tab and by search results, so a matched expense reads exactly as it
/// does in the list it came from — same columns, same money treatment, same category glyph.
struct ExpenseRow: View {
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

                HStack(spacing: 3) {
                    // The web app's paperclip, in the one place a row has left. It says a
                    // receipt is attached without saying anything about it, which is all a
                    // glance needs — the pictures are inside the expense.
                    if expense.documentCount > 0 {
                        Image(systemName: "paperclip")
                            .accessibilityLabel(
                                Text("\(expense.documentCount) documents attached")
                            )
                    }
                    Text(expense.expenseDate.formatted(date: .abbreviated, time: .omitted))
                }
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
        return Text(category.displayName)
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
