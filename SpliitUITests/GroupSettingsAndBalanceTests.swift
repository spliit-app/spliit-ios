import XCTest

/// Settling up, editing a group, and what happens when the server can't be reached.
final class GroupSettingsAndBalanceTests: SpliitUITestCase {

    @MainActor
    func testMarkAsPaidPrefillsAReimbursement() async throws {
        let group = try await api.createGroup(name: "Settling", participants: ["Ana", "Bruno"])
        try await api.createExpense(in: group, title: "Hotel", amount: 10000, paidBy: "Ana")
        let app = launchApp(recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Settling")]))

        app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)].tap()
        assertExists(app.staticTexts["Hotel"], "The seeded expense should load.")

        app.buttons["Balances"].tap()
        assertExists(
            app.buttons[AccessibilityID.Balances.markAsPaid(0)],
            "A group that isn’t settled should suggest a payment."
        )
        app.buttons[AccessibilityID.Balances.markAsPaid(0)].tap()

        let amount = app.textFields[AccessibilityID.ExpenseForm.amountField]
        assertExists(amount, "Marking as paid should open a prefilled expense.")
        XCTAssertEqual(amount.value as? String, "50.00", "Half of the hotel is owed back.")

        app.buttons[AccessibilityID.ExpenseForm.saveButton].tap()

        // Once the reimbursement is recorded, nothing is left to settle.
        assertExists(
            app.staticTexts[AccessibilityID.Balances.settled],
            "Recording the payment should settle the group."
        )
    }

    @MainActor
    func testRenameGroupUpdatesTheListToo() async throws {
        let group = try await api.createGroup(name: "Old name", participants: ["Ana", "Bruno"])
        let app = launchApp(recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Old name")]))

        app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)].tap()
        app.buttons[AccessibilityID.GroupDetail.menuButton].tap()
        app.buttons[AccessibilityID.GroupDetail.editGroupButton].tap()

        let name = app.textFields[AccessibilityID.GroupForm.nameField]
        assertExists(name, "Group settings should open.")
        replaceText(in: name, with: "New name")
        app.buttons[AccessibilityID.GroupForm.saveButton].tap()

        assertExists(app.staticTexts["New name"], "The group title should update.")

        app.navigationBars.buttons.firstMatch.tap()
        assertExists(
            app.staticTexts["New name"],
            "The remembered name should be updated too, not left stale."
        )
    }

    /// The server refuses to remove a participant who appears on an expense, so the app has to
    /// say so rather than let the save fail.
    @MainActor
    func testParticipantWithExpensesCannotBeRemoved() async throws {
        let group = try await api.createGroup(name: "Locked", participants: ["Ana", "Bruno"])
        try await api.createExpense(in: group, title: "Lunch", amount: 2000, paidBy: "Ana")
        let app = launchApp(recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Locked")]))

        app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)].tap()
        assertExists(app.staticTexts["Lunch"], "The seeded expense should load.")

        app.buttons[AccessibilityID.GroupDetail.menuButton].tap()
        app.buttons[AccessibilityID.GroupDetail.editGroupButton].tap()
        assertExists(
            app.textFields[AccessibilityID.GroupForm.participantField(0)],
            "Group settings should open with participants."
        )

        app.textFields[AccessibilityID.GroupForm.participantField(0)].swipeLeft()
        app.buttons["Remove"].firstMatch.tap()

        assertExists(
            app.alerts.firstMatch,
            "Removing a participant with expenses should be explained, not silently fail."
        )
    }

    /// A server that never answers used to leave a spinner on screen with no way out. It
    /// should give up in seconds and offer a retry.
    @MainActor
    func testUnreachableServerOffersRetryInsteadOfSpinning() async throws {
        let group = try await api.createGroup(name: "Offline", participants: ["Ana", "Bruno"])
        let app = launchApp(
            recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Offline")]),
            // Nothing is listening on this port, so every request fails.
            serverURL: "http://localhost:9/"
        )

        app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)].tap()

        assertExists(
            app.buttons[AccessibilityID.ExpenseList.retryButton],
            "An unreachable server should offer a retry rather than spin."
        )
        capture(app, "unreachable-server")
    }
}
