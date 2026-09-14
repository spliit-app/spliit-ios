import AppIntents
import Foundation

/// Opens a group.
struct OpenGroupIntent: AppIntent {

    static let title: LocalizedStringResource = "Open Group"
    static let description = IntentDescription("Opens one of your groups in Spliit.")
    static let openAppWhenRun = true

    @Parameter(title: "Group")
    var group: GroupEntity

    init() {}

    init(group: GroupEntity) {
        self.group = group
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        Router.shared.go(to: .group(id: group.id))
        return .result()
    }
}

/// Starts an expense in a group, with whatever is already known filled in.
///
/// This opens the form rather than posting the expense, and that is the point rather than a
/// shortcut taken. An expense needs a payer, and the app only knows who its user is in the
/// groups they have said so in; guessing would put someone else's name against a payment in a
/// ledger several people share and act on, and the guess would be invisible until someone
/// settled up on it. So the intent gets as far as it honestly can — which is now everything the
/// form has a field for — and hands over.
struct AddExpenseIntent: AppIntent {

    static let title: LocalizedStringResource = "Add Expense"
    static let description = IntentDescription(
        "Starts a new expense in one of your groups, ready to check and save."
    )
    static let openAppWhenRun = true

    @Parameter(title: "Group")
    var group: GroupEntity

    @Parameter(title: "What was it for?", requestValueDialog: "What was it for?")
    var title: String?

    /// A string rather than a number: it is typed straight into the amount field, which parses
    /// it in the user's locale — the one place in the app that knows whether a comma is a
    /// decimal separator or a thousands one.
    @Parameter(title: "Amount")
    var amount: String?

    /// Offered from the list the group's own instance returns — see `CategoryEntityQuery`.
    @Parameter(title: "Category")
    var category: CategoryEntity?

    @Parameter(title: "Notes")
    var notes: String?

    /// Images only, which is what a document is in Spliit: the web app attaches nothing else,
    /// and the size stored beside one is a picture's. Shortcuts converts what it can and refuses
    /// the rest before this runs, so what arrives here is an image file or nothing.
    @Parameter(title: "Documents", supportedContentTypes: [.image])
    var documents: [IntentFile]?

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        Router.shared.go(
            to: .newExpense(
                groupID: group.id,
                prefill: ExpensePrefill(
                    title: title,
                    amount: amount,
                    categoryID: category?.id,
                    notes: notes,
                    // A file this device cannot decode is left out rather than failing the whole
                    // intent: throwing here would discard the title and amount with it, and a
                    // card-tap automation does not get run again. Shortcuts has already checked
                    // that each one is an image, so this is a corrupt file, not a wrong kind.
                    photos: (documents ?? []).compactMap { ReceiptPhoto(data: $0.data) }
                )
            )
        )
        return .result()
    }
}

/// What Siri and Spotlight offer without the user building a shortcut first.
struct SpliitShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddExpenseIntent(),
            phrases: [
                "Add an expense to \(\.$group) in \(.applicationName)",
                "New \(.applicationName) expense in \(\.$group)",
            ],
            shortTitle: "Add Expense",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: OpenGroupIntent(),
            phrases: [
                "Open \(\.$group) in \(.applicationName)",
                "Show \(\.$group) in \(.applicationName)",
            ],
            shortTitle: "Open Group",
            systemImageName: "person.2"
        )
    }
}
