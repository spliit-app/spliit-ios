import Foundation

/// Identifiers the UI tests look for.
///
/// Kept in one place, and applied in the same commit that adds the view. Retrofitting
/// identifiers across a grown app is the thing that makes UI suites get abandoned.
///
/// **Put these on leaves, never on containers.** SwiftUI's `.accessibilityIdentifier` applies
/// to every descendant of the view it modifies, and an outer one silently replaces the
/// identifiers set inside it — so a screen-level identifier on a `NavigationStack` erases the
/// identifiers of every button beneath it. That is why there is no `screen` entry here:
/// to assert a screen is showing, look for something only that screen has.
enum AccessibilityID {

    enum GroupsList {
        static let createGroupButton = "groups.create"
        static let addByURLButton = "groups.addByURL"
        static let settingsButton = "groups.settings"
        static let loadFailed = "groups.loadFailed"

        static func rowTitle(_ groupID: String) -> String { "groups.row.\(groupID).title" }
        static func rowParticipants(_ groupID: String) -> String {
            "groups.row.\(groupID).participants"
        }

        // The row's three actions. Each appears twice — in a swipe and in the long-press menu —
        // but never at the same time, and the group ID keeps one row's buttons apart from the
        // next one's.
        static func rowStarButton(_ groupID: String) -> String { "groups.row.\(groupID).star" }
        static func rowArchiveButton(_ groupID: String) -> String {
            "groups.row.\(groupID).archive"
        }
        static func rowRemoveButton(_ groupID: String) -> String { "groups.row.\(groupID).remove" }
    }

    enum Settings {
        static let baseURLField = "settings.baseURL"
        static let resetButton = "settings.reset"
        static let doneButton = "settings.done"
        static let version = "settings.version"
    }

    enum AddByURL {
        static let field = "addByURL.field"
        static let addButton = "addByURL.add"
        static let cancelButton = "addByURL.cancel"
        static let error = "addByURL.error"
    }

    enum GroupForm {
        static let nameField = "groupForm.name"
        /// The row that opens the picker. The free-text symbol field below it only exists once
        /// "Custom symbol" has been chosen.
        static let currencyButton = "groupForm.currencyButton"
        static let currencyField = "groupForm.currency"
        static let informationField = "groupForm.information"
        static let addParticipantButton = "groupForm.addParticipant"
        static let saveButton = "groupForm.save"
        static let cancelButton = "groupForm.cancel"
        static let error = "groupForm.error"

        static func participantField(_ index: Int) -> String { "groupForm.participant.\(index)" }
    }

    enum CurrencyPicker {
        /// Carried by the row in the list and by the button the no-results state offers. The two
        /// are never on screen together — one needs an empty search field, the other a full one.
        static let customOption = "currencyPicker.custom"

        static func row(_ code: String) -> String { "currencyPicker.row.\(code)" }
    }

    enum GroupDetail {
        static let menuButton = "group.menu"
        static let editGroupButton = "group.edit"
        static let shareButton = "group.share"
        // No identifiers for the tabs themselves: anything applied to a tab's content would
        // be stamped over every element inside it. The tab bar buttons carry their labels.
    }

    enum GroupInformation {
        static let note = "information.note"
        static let empty = "information.empty"
        static let editButton = "information.edit"
        static let retryButton = "information.retry"
        static let currency = "information.currency"
        /// The way to the activity log, which is pushed from this tab rather than being one.
        static let activityButton = "information.activity"

        static func participant(_ id: String) -> String { "information.participant.\(id)" }
    }

    enum ActivityLog {
        static let retryButton = "activity.retry"

        /// The sentence on a row, and the timestamp under it. Keyed by the activity's own ID:
        /// a group can hold several lines that read identically — the same expense edited
        /// twice — and only the ID tells them apart.
        static func entry(_ activityID: String) -> String { "activity.row.\(activityID).summary" }
        static func time(_ activityID: String) -> String { "activity.row.\(activityID).time" }
    }

    enum ExpenseList {
        static let addButton = "expenses.add"
        static let emptyAddButton = "expenses.emptyAdd"
        static let loadFailed = "expenses.loadFailed"
        static let retryButton = "expenses.retry"
        static let undoButton = "expenses.undoDelete"

        static func rowTitle(_ expenseID: String) -> String { "expenses.row.\(expenseID).title" }
        static func rowAmount(_ expenseID: String) -> String { "expenses.row.\(expenseID).amount" }
        static func rowPaidBy(_ expenseID: String) -> String { "expenses.row.\(expenseID).paidBy" }
    }

    enum ExpenseSearch {
        static let field = "search.field"
        static let clearButton = "search.clear"
        static let cancelButton = "search.cancel"
    }

    enum ExpenseForm {
        static let titleField = "expenseForm.title"
        static let amountField = "expenseForm.amount"
        static let dateField = "expenseForm.date"
        static let categoryPicker = "expenseForm.category"
        static let paidByPicker = "expenseForm.paidBy"
        static let notesField = "expenseForm.notes"
        static let reimbursementToggle = "expenseForm.isReimbursement"
        static let saveButton = "expenseForm.save"
        static let cancelButton = "expenseForm.cancel"
        static let deleteButton = "expenseForm.delete"
        static let error = "expenseForm.error"
        static let remainder = "expenseForm.remainder"
        static let currencyButton = "expenseForm.currency"
        static let originalAmountField = "expenseForm.originalAmount"
        static let conversionRateField = "expenseForm.conversionRate"
        static let conversionRateStatus = "expenseForm.conversionRate.status"
        static let refreshRateButton = "expenseForm.conversionRate.refresh"
        static let selectAllButton = "expenseForm.paidFor.selectAll"

        /// Reading the expense off a photo of the receipt. One identifier for the row whichever
        /// it is: a menu where there is a camera to choose with, a plain button where there is
        /// not. The two menu items have none of their own — an identifier on the menu stamps
        /// every item inside it regardless, which is the trap at the top of this file.
        static let scanButton = "expenseForm.scanReceipt"
        static let scanStatus = "expenseForm.scanReceipt.status"

        static func splitModeOption(_ mode: String) -> String { "expenseForm.split.\(mode)" }
        static func participantToggle(_ id: String) -> String { "expenseForm.paidFor.\(id)" }
        static func participantValue(_ id: String) -> String { "expenseForm.share.\(id)" }
    }

    /// Saying who you are in a group, and what that then shows. The picker is one screen reached
    /// from three — the balances tab, the stats tab and the information tab — so the entry
    /// points are named apart while everything inside the picker is named once.
    enum ActiveUser {
        static let balancesButton = "activeUser.balances"
        static let informationButton = "activeUser.information"
        static let statsButton = "activeUser.stats"
        static let direction = "activeUser.direction"
        static let total = "activeUser.total"
        static let nobodyOption = "activeUser.option.nobody"

        static func option(_ participantID: String) -> String {
            "activeUser.option.\(participantID)"
        }
        /// The "You" marker on your own row in the balances list.
        static func badge(_ participantID: String) -> String {
            "activeUser.badge.\(participantID)"
        }
    }

    enum Stats {
        /// The one number the tab has before anybody says who they are.
        static let groupTotal = "stats.groupTotal"
        static let yourSpending = "stats.yourSpending"
        static let yourShare = "stats.yourShare"
        /// The caption above each amount. Two of the three flip between spending and earnings
        /// with the sign, and a test that only read the numbers could not tell which it got.
        static let groupTotalLabel = "stats.groupTotal.label"
        static let yourSpendingLabel = "stats.yourSpending.label"
        static let yourShareLabel = "stats.yourShare.label"
        /// The "X% of the group" caption under each personal figure. Named because the amount
        /// alone cannot say whether the slice was measured against the right whole.
        static let yourSpendingFraction = "stats.yourSpending.fraction"
        static let yourShareFraction = "stats.yourShare.fraction"
        static let retryButton = "stats.retry"
        /// The breakdown by category, keyed by the server's category ID — 0 being both
        /// "General" and an expense filed under nothing, which the server conflates too.
        static func categoryName(_ categoryID: Int) -> String {
            "stats.category.\(categoryID).name"
        }
        static func categoryAmount(_ categoryID: Int) -> String {
            "stats.category.\(categoryID).amount"
        }
        static let categoryFailed = "stats.category.failed"
        // Nothing for the "no totals on this server" state: it is a title and a paragraph with
        // no action under them, and an identifier would have to go on the container.
    }

    enum Balances {
        static let settled = "balances.settled"

        static func participantName(_ id: String) -> String { "balances.row.\(id).name" }
        static func participantAmount(_ id: String) -> String { "balances.row.\(id).amount" }
        static func reimbursement(_ index: Int) -> String { "balances.reimbursement.\(index)" }
        static func markAsPaid(_ index: Int) -> String { "balances.markAsPaid.\(index)" }
    }
}
