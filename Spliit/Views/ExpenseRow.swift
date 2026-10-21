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
    /// Who the person holding the phone said they are in this group. Nil until they have, and
    /// then the row has no "you" to speak for.
    let activeParticipantID: String?

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

                    paidByLine
                        .font(.footnote)
                        .accessibilityIdentifier(AccessibilityID.ExpenseList.rowPaidBy(expense.id))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: dynamicTypeSize.detailAlignment, spacing: 2) {
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

    /// Who paid, and — once you have said who you are — what the expense does to your balance.
    ///
    /// The balance takes the place of the "for …" names rather than a line of its own, so a row
    /// keeps its height. VoiceOver still reads the whole sentence.
    @ViewBuilder
    private var paidByLine: some View {
        if let you = activeParticipantID, let summary = yourSummary(you) {
            let withPayer = Text("\(expense.paidBy.name) paid · \(summary)")
            Group {
                if expense.paidBy.id == you {
                    summary
                } else if dynamicTypeSize.isAccessibilitySize {
                    // `ViewThatFits` measures each option on one line, where this never fits at
                    // these sizes; wrapping is what keeps who paid.
                    withPayer
                } else {
                    // The payer's name goes whole or not at all; a truncated name says less than
                    // the dot beside it, which is already in their colour.
                    ViewThatFits(in: .horizontal) {
                        withPayer
                        summary
                    }
                }
            }
            .foregroundStyle(.secondary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                Text("Paid by \(expense.paidBy.name) for \(paidForNames). \(summary)")
            )
        } else {
            Text("Paid by \(expense.paidBy.name) for \(paidForNames)")
                .foregroundStyle(.secondary)
                // One line, so a run of expenses stays a list you can scan rather than a
                // stack of paragraphs — the full split is one tap away. Accessibility
                // sizes get more room, where a single line would be three words.
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
        }
    }

    /// What this expense does to your balance, tinted like a balance because it has a direction.
    /// Nil when it leaves you even — your own share paid, or a share that came to nothing — which
    /// says nothing "Paid by … for …", naming you, does not.
    private func yourSummary(_ you: String) -> Text? {
        guard let balance = ExpenseBalance.of(you, in: expense) else {
            return Text("Not involved").foregroundStyle(.tertiary)
        }
        guard balance != 0 else { return nil }
        return Text(balanceDescription(balance))
            .fontWeight(.medium)
            .foregroundStyle(Money.Sign(balance: balance).tint)
    }

    /// The amount set in the money face, inside the sentence rather than beside it, so the
    /// currency symbol stays in one element with its digits.
    private func balanceDescription(_ balance: Int) -> LocalizedStringKey {
        let amount = Text(formatter.string(minorUnits: abs(balance)))
            .font(.system(.footnote, design: .rounded, weight: .semibold).monospacedDigit())
        return switch ExpenseBalance.Reading(balance: balance, of: expense) {
        case .lent: "You lent \(amount)"
        case .borrowed: "You borrowed \(amount)"
        case .paidBack: "You paid back \(amount)"
        case .wasPaidBack: "You were paid back \(amount)"
        case .isOwed: "You are owed \(amount)"
        case .owes: "You owe \(amount)"
        }
    }

    /// Empty rather than "Uncategorized" when the server sends no category: an accessibility
    /// value that says nothing is quieter than one that says nothing useful.
    private var categoryDescription: Text {
        guard let category = expense.category else { return Text(verbatim: "") }
        return Text(category.displayName)
    }

    private var paidForNames: String {
        expense.paidFor.map(\.participant.name).formatted(.list(type: .and))
    }
}
