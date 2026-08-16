import XCTest

/// Swipe-to-delete and the few seconds afterwards in which it can be taken back.
///
/// The interesting cases are all about *when* the request is sent, so these check the server's
/// answer by leaving the group and coming back rather than by reading the screen it was deleted
/// from.
final class ExpenseDeletionTests: SpliitUITestCase {

    @MainActor
    func testUndoPutsTheExpenseBack() async throws {
        let group = try await api.createGroup(name: "Undo", participants: ["Ana", "Bruno"])
        try await api.createExpense(in: group, title: "Pizza night", amount: 3000, paidBy: "Ana")
        let app = launchApp(recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Undo")]))

        openGroup(app, group)
        swipeToDelete(app, "Pizza night")

        assertExists(app.buttons[AccessibilityID.ExpenseList.undoButton], "Undo should be offered.")
        capture(app, "undo-bar")
        app.buttons[AccessibilityID.ExpenseList.undoButton].tap()

        assertExists(app.staticTexts["Pizza night"], "Undo should put the row back.")

        // And it was never sent: the expense is still there after a fresh look at the group.
        reopenGroup(app, group)
        assertExists(app.staticTexts["Pizza night"], "The server should still have the expense.")
    }

    @MainActor
    func testTheDeleteLandsOnceTheWindowCloses() async throws {
        let group = try await api.createGroup(name: "Window", participants: ["Ana", "Bruno"])
        try await api.createExpense(in: group, title: "Pizza night", amount: 3000, paidBy: "Ana")
        try await api.createExpense(in: group, title: "Museum tickets", amount: 2000, paidBy: "Ana")
        let app = launchApp(recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Window")]))

        openGroup(app, group)
        swipeToDelete(app, "Pizza night")

        // The undo window is five seconds; wait it out and the bar should go with it.
        let undo = app.buttons[AccessibilityID.ExpenseList.undoButton]
        XCTAssertTrue(
            waitForDisappearance(of: undo, timeout: 20),
            "The undo bar should leave when the window closes."
        )

        reopenGroup(app, group)
        assertExists(app.staticTexts["Museum tickets"], "The other expense should still be there.")
        XCTAssertFalse(
            app.staticTexts["Pizza night"].exists,
            "The delete should have been sent once the window closed."
        )
    }

    /// The one that would lose data if it were wrong: the model goes away with the screen, and a
    /// delete still waiting on it has to go out rather than be forgotten.
    @MainActor
    func testLeavingTheScreenSendsTheDeleteRatherThanDroppingIt() async throws {
        let group = try await api.createGroup(name: "Leaving", participants: ["Ana", "Bruno"])
        try await api.createExpense(in: group, title: "Pizza night", amount: 3000, paidBy: "Ana")
        try await api.createExpense(in: group, title: "Museum tickets", amount: 2000, paidBy: "Ana")
        let app = launchApp(recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Leaving")]))

        openGroup(app, group)
        swipeToDelete(app, "Pizza night")
        assertExists(app.buttons[AccessibilityID.ExpenseList.undoButton], "Undo should be offered.")

        // Straight out of the group, well inside the undo window.
        app.buttons["Groups"].tap()
        assertExists(
            app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)],
            "Back on the groups list."
        )

        app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)].tap()
        assertExists(app.staticTexts["Museum tickets"], "The group should reload.")
        XCTAssertFalse(
            app.staticTexts["Pizza night"].exists,
            "Leaving the screen should have sent the delete, not dropped it."
        )
    }

    @MainActor
    private func openGroup(_ app: XCUIApplication, _ group: SpliitTestAPI.Group) {
        app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)].tap()
        assertExists(app.staticTexts["Pizza night"], "The group’s expenses should load.")
    }

    /// Out of the group and back in, which is the cheapest way to ask the server what it thinks.
    @MainActor
    private func reopenGroup(_ app: XCUIApplication, _ group: SpliitTestAPI.Group) {
        app.buttons["Groups"].tap()
        let row = app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)]
        assertExists(row, "Back on the groups list.")
        row.tap()
    }

    @MainActor
    private func swipeToDelete(_ app: XCUIApplication, _ title: String) {
        let row = app.staticTexts[title]
        assertExists(row, "The row to delete should be listed.")
        row.swipeLeft()

        let delete = app.buttons["Delete"]
        assertExists(delete, "Swiping should reveal Delete.")
        delete.tap()
    }

    /// `waitForExistence` has no opposite, and polling by hand is how a test ends up asserting on
    /// a screen that simply had not caught up yet.
    @MainActor
    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: element
        )
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }
}
