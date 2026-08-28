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

        static func participant(_ id: String) -> String { "information.participant.\(id)" }
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
        static let selectAllButton = "expenseForm.paidFor.selectAll"

        static func splitModeOption(_ mode: String) -> String { "expenseForm.split.\(mode)" }
        static func participantToggle(_ id: String) -> String { "expenseForm.paidFor.\(id)" }
        static func participantValue(_ id: String) -> String { "expenseForm.share.\(id)" }
    }

    /// Saying who you are in a group, and what that then shows. The picker is one screen reached
    /// from two — the balances tab and the information tab — so the two entry points are named
    /// apart while everything inside the picker is named once.
    enum ActiveUser {
        static let balancesButton = "activeUser.balances"
        static let informationButton = "activeUser.information"
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

    enum Balances {
        static let settled = "balances.settled"

        static func participantName(_ id: String) -> String { "balances.row.\(id).name" }
        static func participantAmount(_ id: String) -> String { "balances.row.\(id).amount" }
        static func reimbursement(_ index: Int) -> String { "balances.reimbursement.\(index)" }
        static func markAsPaid(_ index: Int) -> String { "balances.markAsPaid.\(index)" }
    }
}
