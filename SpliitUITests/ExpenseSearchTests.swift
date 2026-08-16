import XCTest

/// Searching a group's expenses. The matching happens on the server, so these cover the round
/// trip: what is typed, what comes back, and what the screen says when nothing does.
final class ExpenseSearchTests: SpliitUITestCase {

    @MainActor
    func testSearchNarrowsTheListToMatchingTitles() async throws {
        let group = try await api.createGroup(name: "Trip", participants: ["Ana", "Bruno"])
        try await api.createExpense(in: group, title: "Pizza night", amount: 3000, paidBy: "Ana")
        try await api.createExpense(in: group, title: "Museum tickets", amount: 2000, paidBy: "Ana")
        let app = launchApp(recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Trip")]))

        openGroup(app, group)
        assertExists(app.staticTexts["Museum tickets"], "Both expenses should load.")

        // Lowercase on purpose: the server matches case-insensitively, and someone searching
        // their own expenses does not capitalise.
        search(app, for: "pizza")

        assertExists(app.staticTexts["Pizza night"], "The match should be listed.")
        XCTAssertFalse(
            app.staticTexts["Museum tickets"].exists,
            "An expense that doesn’t match should not be in the results."
        )
        capture(app, "search-results")

        // A result is the expense itself, not a copy of it: opening one edits it.
        app.staticTexts["Pizza night"].tap()
        assertExists(
            app.textFields[AccessibilityID.ExpenseForm.titleField],
            "A result should open the expense for editing."
        )
    }

    /// A search matching nothing must not read as a group with no expenses — different sentence,
    /// different way out.
    @MainActor
    func testASearchThatMatchesNothingSaysSo() async throws {
        let group = try await api.createGroup(name: "Trip", participants: ["Ana", "Bruno"])
        try await api.createExpense(in: group, title: "Pizza night", amount: 3000, paidBy: "Ana")
        let app = launchApp(recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Trip")]))

        openGroup(app, group)
        search(app, for: "helicopter")

        assertExists(
            app.staticTexts["No matching expenses"],
            "An empty result should say so rather than show an empty list."
        )
        XCTAssertFalse(
            app.staticTexts["No expenses yet"].exists,
            "A group with expenses must never be described as having none."
        )
        capture(app, "search-no-matches")
    }

    /// Clearing empties the field; cancelling puts the tabs back. The expense list is untouched
    /// by either — the search never narrowed it.
    @MainActor
    func testClearingAndCancellingASearch() async throws {
        let group = try await api.createGroup(name: "Trip", participants: ["Ana", "Bruno"])
        try await api.createExpense(in: group, title: "Pizza night", amount: 3000, paidBy: "Ana")
        try await api.createExpense(in: group, title: "Museum tickets", amount: 2000, paidBy: "Ana")
        let app = launchApp(recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Trip")]))

        openGroup(app, group)
        search(app, for: "pizza")
        assertExists(app.staticTexts["Pizza night"], "The match should be listed.")

        app.buttons[AccessibilityID.ExpenseSearch.clearButton].tap()
        assertExists(app.staticTexts["Search this group"], "Clearing should return to the prompt.")

        app.buttons[AccessibilityID.ExpenseSearch.cancelButton].tap()

        assertExists(app.buttons["Balances"], "Cancelling should bring the tabs back.")
        assertExists(
            app.staticTexts["Museum tickets"],
            "The expense list should still hold everything the search filtered out."
        )
    }

    @MainActor
    private func openGroup(_ app: XCUIApplication, _ group: SpliitTestAPI.Group) {
        app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)].tap()
        assertExists(app.staticTexts["Pizza night"], "The group’s expenses should load.")
    }

    /// Opens the search tab from the tab bar and types into the field it docks at the bottom.
    @MainActor
    private func search(_ app: XCUIApplication, for text: String) {
        let searchTab = app.buttons["Search"]
        assertExists(searchTab, "The tab bar should offer search.")
        searchTab.tap()

        let field = app.textFields[AccessibilityID.ExpenseSearch.field]
        assertExists(field, "The search field should open with the tab.")
        field.tap()
        field.typeText(text)
    }
}
