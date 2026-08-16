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

    /// Every currency the app can name is in the picker, and the ones it can't are what the
    /// custom symbol is for. Moving a group onto one has to clear the ISO code it had: a group
    /// showing "kr" while still claiming to be in dollars would be a lie the server told.
    @MainActor
    func testSwitchingToACustomSymbolClearsTheCurrencyCode() async throws {
        let group = try await api.createGroup(name: "Off-list", participants: ["Ana", "Bruno"])
        let app = launchApp(recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Off-list")]))

        app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)].tap()
        app.buttons[AccessibilityID.GroupDetail.menuButton].tap()
        app.buttons[AccessibilityID.GroupDetail.editGroupButton].tap()

        let currency = app.buttons[AccessibilityID.GroupForm.currencyButton]
        assertExists(currency, "Group settings should open.")
        XCTAssertTrue(
            currency.label.contains("US Dollar"),
            "The seeded group is in dollars, and the form should say so."
        )

        currency.tap()
        let custom = app.buttons[AccessibilityID.CurrencyPicker.customOption]
        assertExists(custom, "The picker should open, with the custom symbol in reach of it.")
        custom.tap()

        let symbol = app.textFields[AccessibilityID.GroupForm.currencyField]
        assertExists(symbol, "Choosing a custom symbol should offer the field to type it in.")
        replaceText(in: symbol, with: "kr")
        app.buttons[AccessibilityID.GroupForm.saveButton].tap()

        app.buttons[AccessibilityID.GroupDetail.menuButton].tap()
        app.buttons[AccessibilityID.GroupDetail.editGroupButton].tap()

        let saved = app.buttons[AccessibilityID.GroupForm.currencyButton]
        assertExists(saved, "Group settings should open again.")
        XCTAssertTrue(saved.label.contains("kr"), "The symbol should have been saved.")
        XCTAssertFalse(
            saved.label.contains("Dollar"),
            "And the code should be gone, not left behind by a request that omitted it."
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
