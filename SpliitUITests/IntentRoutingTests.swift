import XCTest

/// What happens after an App Intent has run.
///
/// The intents themselves cannot be driven from here — Siri and Spotlight run them, outside any
/// app a test controls. What these cover is the half on this side of the handover: a destination
/// left in the router has to survive a cold launch and open the right thing.
final class IntentRoutingTests: SpliitUITestCase {

    @MainActor
    func testOpeningAGroupGoesStraightIntoIt() async throws {
        let group = try await api.createGroup(name: "Lisbon", participants: ["Ana", "Bruno"])
        try await api.createExpense(in: group, title: "Pastéis", amount: 450, paidBy: "Ana")

        let app = launchApp(
            recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Lisbon")]),
            openGroup: group.id
        )

        // Straight past the list, which is the whole point of asking for a group by name.
        assertExists(app.staticTexts["Pastéis"], "The group should be open at launch.")
        assertExists(app.buttons["Balances"], "…and it should be the group screen, not the list.")
    }

    @MainActor
    func testAddingAnExpenseOpensTheFormWithWhatWasSaid() async throws {
        let group = try await api.createGroup(name: "Lisbon", participants: ["Ana", "Bruno"])

        let app = launchApp(
            recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Lisbon")]),
            addExpense: (groupID: group.id, title: "Taxi", amount: "23.50")
        )

        let title = app.textFields[AccessibilityID.ExpenseForm.titleField]
        assertExists(title, "The expense form should be open at launch.")
        XCTAssertEqual(title.value as? String, "Taxi", "The title should be filled in.")
        XCTAssertEqual(
            app.textFields[AccessibilityID.ExpenseForm.amountField].value as? String,
            "23.50",
            "The amount should be filled in."
        )
        capture(app, "intent-prefilled-form")

        // Nothing was saved on the user's behalf: this is a form, waiting.
        app.buttons[AccessibilityID.ExpenseForm.saveButton].tap()
        assertExists(app.staticTexts["Taxi"], "Saving should be the user’s doing, and should work.")
    }

    /// An intent naming a group this device has never been told about must not strand the app on
    /// a screen it cannot fill.
    @MainActor
    func testAnUnknownGroupLeavesTheListAlone() async throws {
        let app = launchApp(
            recentGroups: SpliitTestAPI.recentGroupsJSON([]),
            openGroup: "definitely-not-a-real-group"
        )

        assertExists(
            app.buttons[AccessibilityID.GroupsList.createGroupButton],
            "An unknown group should leave the welcome screen reachable."
        )
    }
}
