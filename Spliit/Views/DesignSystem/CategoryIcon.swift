import SpliitAPI
import SwiftUI

/// A category's glyph in the rounded slot that leads an expense row.
///
/// The category is the one thing the expense list already knew and never showed — it has been
/// fetched since the first version and spent its life populating a picker.
///
/// The slot is a neutral fill rather than a tinted one on purpose: the amount is the only
/// saturated thing in the row, and a coloured tile beside it would compete for the glance.
struct CategoryIcon: View {

    let category: ExpenseCategory?
    var size: CGFloat = 34

    @ScaledMetric private var textScale: CGFloat = 1

    var body: some View {
        Image(systemName: ExpenseCategoryIcon.symbol(grouping: category?.grouping, name: category?.name))
            .font(.system(size: side * 0.55))
            .foregroundStyle(.secondary)
            .frame(width: side, height: side)
            .background(
                Color(.tertiarySystemFill),
                in: RoundedRectangle(cornerRadius: side * 0.24, style: .continuous)
            )
            // The category is named on the row's title instead — see `ExpenseRow`. Left to itself
            // this would be one more element to swipe past on every row.
            .accessibilityHidden(true)
    }

    private var side: CGFloat {
        size * min(textScale, 1.5)
    }
}

extension ExpenseCategory {
    /// What to put on screen: the translated name where this build knows the category, and
    /// whatever the server sent where it does not — see `ExpenseCategoryName`.
    nonisolated var displayName: String {
        ExpenseCategoryName.name(grouping: grouping, name: name) ?? name
    }

    /// The translated heading for a grouping, falling back the same way.
    nonisolated static func displayHeading(_ grouping: String) -> String {
        ExpenseCategoryName.heading(grouping) ?? grouping
    }

    /// The order a person picks from: headings, and the categories under each, both sorted on
    /// their translated names with the locale's own collation — otherwise a French picker runs in
    /// English alphabetical order and "Épicerie" sorts after "Vêtements" on the strength of its
    /// accent. The form's picker and the one in the Shortcuts app both read this, so a category
    /// is found in the same place whichever is open.
    nonisolated static func grouped(_ categories: [ExpenseCategory]) -> [(name: String, categories: [ExpenseCategory])] {
        Dictionary(grouping: categories, by: \.grouping)
            .map { grouping, categories in
                (
                    name: displayHeading(grouping),
                    categories: categories.sorted {
                        $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
                    }
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

#Preview {
    let samples = [
        ("Food and Drink", "Groceries"),
        ("Transportation", "Taxi"),
        ("Home", "Rent"),
        ("Utilities", "Water"),
        ("Entertainment", "Movies"),
    ]
    return VStack(alignment: .leading, spacing: 12) {
        ForEach(samples, id: \.1) { grouping, name in
            HStack(spacing: 12) {
                CategoryIcon(
                    category: ExpenseCategory(id: 0, grouping: grouping, name: name)
                )
                Text("\(grouping) / \(name)")
            }
        }
    }
    .padding()
}
