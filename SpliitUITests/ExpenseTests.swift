import XCTest

/// Adding, editing and deleting expenses, and how they're grouped in the list.
final class ExpenseTests: SpliitUITestCase {

    @MainActor
    func testAddExpenseAppearsInTheListAndMovesTheBalances() async throws {
        let group = try await api.createGroup(name: "Dinner club", participants: ["Ana", "Bruno"])
        let app = launchApp(
            recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Dinner club")])
        )

        app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)].tap()
        assertExists(app.buttons[AccessibilityID.ExpenseList.emptyAddButton], "Group should open.")

        app.buttons[AccessibilityID.ExpenseList.emptyAddButton].tap()
        replaceText(in: app.textFields[AccessibilityID.ExpenseForm.titleField], with: "Pizza")
        replaceText(in: app.textFields[AccessibilityID.ExpenseForm.amountField], with: "40.00")
        capture(app, "expense-form")
        app.buttons[AccessibilityID.ExpenseForm.saveButton].tap()

        assertExists(app.staticTexts["Pizza"], "The new expense should appear in the list.")
        capture(app, "expense-list")

        // Ana paid 40 for two people, so she is owed half.
        app.buttons["Balances"].tap()
        let ana = try XCTUnwrap(group.participants["Ana"])
        let bruno = try XCTUnwrap(group.participants["Bruno"])
        assertExists(
            app.staticTexts[AccessibilityID.Balances.participantAmount(ana)],
            "Balances should list the payer."
        )
        XCTAssertEqual(
            app.staticTexts[AccessibilityID.Balances.participantAmount(ana)].label, "$20.00"
        )
        XCTAssertEqual(
            app.staticTexts[AccessibilityID.Balances.participantAmount(bruno)].label, "-$20.00"
        )
        capture(app, "balances")
    }

    @MainActor
    func testEditAnExpense() async throws {
        let group = try await api.createGroup(name: "Edits", participants: ["Ana", "Bruno"])
        try await api.createExpense(in: group, title: "Coffee", amount: 500, paidBy: "Ana")
        let app = launchApp(recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Edits")]))

        app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)].tap()
        assertExists(app.staticTexts["Coffee"], "The seeded expense should be listed.")

        app.staticTexts["Coffee"].tap()
        assertExists(
            app.textFields[AccessibilityID.ExpenseForm.titleField], "The editor should open."
        )
        XCTAssertEqual(
            app.textFields[AccessibilityID.ExpenseForm.amountField].value as? String,
            "5.00",
            "The editor should load the stored amount."
        )

        replaceText(in: app.textFields[AccessibilityID.ExpenseForm.titleField], with: "Coffee and cake")
        app.buttons[AccessibilityID.ExpenseForm.saveButton].tap()

        assertExists(app.staticTexts["Coffee and cake"], "The edit should show in the list.")
    }

    @MainActor
    func testDeleteAnExpense() async throws {
        let group = try await api.createGroup(name: "Deletes", participants: ["Ana", "Bruno"])
        try await api.createExpense(in: group, title: "Mistake", amount: 500, paidBy: "Ana")
        let app = launchApp(recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Deletes")]))

        app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)].tap()
        assertExists(app.staticTexts["Mistake"], "The expense should be listed.")

        app.staticTexts["Mistake"].tap()
        let delete = app.buttons[AccessibilityID.ExpenseForm.deleteButton]
        assertExists(app.textFields[AccessibilityID.ExpenseForm.titleField], "The editor should open.")
        scrollUntilHittable(delete, in: app)
        XCTAssertTrue(delete.isHittable, "Delete should be reachable by scrolling the form.")
        delete.tap()

        assertExists(
            app.buttons[AccessibilityID.ExpenseList.emptyAddButton],
            "Deleting the only expense should leave the empty state."
        )
    }

    /// Expenses are bucketed by age, exactly as the React Native app did it.
    @MainActor
    func testExpensesAreGroupedByDate() async throws {
        let group = try await api.createGroup(name: "History", participants: ["Ana", "Bruno"])
        // Today, not yesterday. "This week" is the same *calendar* week, not the last seven days,
        // so yesterday belongs to the previous week whenever this runs on the first day of one —
        // which is how this passed for months and then failed at 00:08 UTC on a Sunday, with
        // yesterday's expense filed under "Earlier this month". Today is always in its own week.
        try await api.createExpense(in: group, title: "Recent one", amount: 100, paidBy: "Ana", daysAgo: 0)
        try await api.createExpense(in: group, title: "Ancient one", amount: 100, paidBy: "Ana", daysAgo: 800)
        let app = launchApp(recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "History")]))

        app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)].tap()

        assertExists(app.staticTexts["Recent one"], "Both expenses should load.")
        XCTAssertTrue(app.staticTexts["Ancient one"].exists)
        XCTAssertTrue(
            app.staticTexts["This week"].exists || app.staticTexts["Upcoming"].exists,
            "A recent expense needs a recent section heading."
        )
        XCTAssertTrue(app.staticTexts["Older"].exists, "A two-year-old expense belongs in Older.")
    }
}
