import XCTest

/// Expenses that make more of themselves.
///
/// The copies are the server's work and it does them lazily — on the next listing of the group —
/// so these check what was actually stored rather than waiting for anything to appear. What the
/// server does with a schedule once it has acted on one is pinned down in `make test` and
/// `make test-live`, where it costs seconds instead of a simulator.
final class ExpenseRecurrenceTests: SpliitUITestCase {

    @MainActor
    func testSettingARecurrenceStoresItAndMarksTheRow() async throws {
        let group = try await api.createGroup(name: "Flat share", participants: ["Ana", "Bruno"])
        let app = launchApp(
            recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Flat share")])
        )

        app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)].tap()
        app.buttons[AccessibilityID.ExpenseList.emptyAddButton].tap()

        replaceText(in: app.textFields[AccessibilityID.ExpenseForm.titleField], with: "Rent")
        replaceText(in: app.textFields[AccessibilityID.ExpenseForm.amountField], with: "900.00")

        chooseRecurrence(app, "Monthly")

        // The picker's whole purpose is the consequence, so the screen has to state it.
        assertExists(
            app.staticTexts[AccessibilityID.ExpenseForm.recurrenceFooter],
            "Setting a recurrence should say when the next one lands."
        )
        capture(app, "expense-recurrence")

        app.buttons[AccessibilityID.ExpenseForm.saveButton].tap()
        assertExists(app.staticTexts["Rent"], "The recurring expense should save.")

        let expense = try await api.expense(inGroup: group.id, titled: "Rent")
        XCTAssertEqual(expense["recurrenceRule"] as? String, "MONTHLY")
        XCTAssertNotNil(
            expense["recurringExpenseLink"] as? [String: Any],
            "The server should have scheduled the next one."
        )

        let id = try XCTUnwrap(expense["id"] as? String)
        assertExists(
            app.images[AccessibilityID.ExpenseList.rowRecurrence(id)],
            "The list should show that the expense repeats."
        )
    }

    /// The other half: an expense that already repeats can be read back and switched off. The
    /// server only honours that while it has not yet acted on the schedule, which is why this
    /// one is dated today — nothing has fallen due.
    @MainActor
    func testAnExistingRecurrenceIsShownAndCanBeTurnedOff() async throws {
        let group = try await api.createGroup(name: "Gym", participants: ["Ana", "Bruno"])
        try await api.createExpense(
            in: group, title: "Membership", amount: 4000, paidBy: "Ana",
            recurrenceRule: "WEEKLY"
        )
        let app = launchApp(recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Gym")]))

        app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)].tap()
        let row = app.staticTexts["Membership"]
        assertExists(row, "The group’s expenses should load.")
        row.tap()

        let picker = app.buttons[AccessibilityID.ExpenseForm.recurrencePicker]
        assertExists(picker, "Editing should show the recurrence the expense was saved with.")
        XCTAssertTrue(
            picker.value as? String == "Weekly" || picker.label.contains("Weekly"),
            "The picker should read back Weekly, not the default."
        )

        chooseRecurrence(app, "Never")
        app.buttons[AccessibilityID.ExpenseForm.saveButton].tap()
        assertExists(app.staticTexts["Membership"], "Turning the recurrence off should save.")

        let expense = try await api.expense(inGroup: group.id, titled: "Membership")
        XCTAssertEqual(expense["recurrenceRule"] as? String, "NONE")
    }

    /// The picker is a menu: the row opens it, and the frequency is a button inside.
    @MainActor
    private func chooseRecurrence(_ app: XCUIApplication, _ frequency: String) {
        let picker = app.buttons[AccessibilityID.ExpenseForm.recurrencePicker]
        assertExists(picker, "The form should offer a recurrence.")
        picker.tap()

        let option = app.buttons[frequency]
        assertExists(option, "The menu should offer \(frequency).")
        option.tap()
    }
}
