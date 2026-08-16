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
/// shortcut taken. An expense needs a payer, and the app has no idea who its user is in any
/// given group — "who are you in this group?" is an M3 feature. Guessing would put someone
/// else's name against a payment in a ledger several people share and act on, and the guess
/// would be invisible until someone settled up on it. So the intent gets as far as it honestly
/// can and hands over.
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

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        Router.shared.go(
            to: .newExpense(groupID: group.id, title: title, amount: amount)
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
