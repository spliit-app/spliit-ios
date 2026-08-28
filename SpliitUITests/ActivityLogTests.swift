import XCTest

/// The activity tab: what happened to a group, who did it, and which lines lead anywhere.
final class ActivityLogTests: SpliitUITestCase {

    @MainActor
    func testTheLogListsWhatHasHappenedToTheGroup() async throws {
        let group = try await api.createGroup(name: "History", participants: ["Ana", "Bruno"])
        try await api.createExpense(in: group, title: "Pizza night", amount: 3000, paidBy: "Ana")
        try await api.createExpense(in: group, title: "Museum tickets", amount: 2000, paidBy: "Bruno")
        let app = launchApp(recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "History")]))

        openActivity(app, group)

        // The harness writes straight to the API without saying who it is, which is exactly the
        // case the fallback exists for — and the case every expense written before this release
        // is in.
        assertExists(
            app.staticTexts["Someone added “Pizza night”."],
            "The log should say an expense was added."
        )
        assertExists(
            app.staticTexts["Someone added “Museum tickets”."],
            "Every expense should have its own line."
        )
        capture(app, "activity-log")
    }

    /// The log is only worth having if it can name people, and it can only name someone this
    /// phone has said it is. Nothing local proves the ID reaches the server — this does.
    @MainActor
    func testAnExpenseAddedInTheAppIsCreditedToWhoeverYouSaidYouAre() async throws {
        let group = try await api.createGroup(name: "Named", participants: ["Ana", "Bruno"])
        let ana = try XCTUnwrap(group.participants["Ana"], "The group should know Ana.")
        let app = launchApp(
            recentGroups: SpliitTestAPI.recentGroupsJSON(
                organised: [(id: group.id, name: "Named", isStarred: false, isArchived: false)],
                activeParticipants: [group.id: ana]
            )
        )

        app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)].tap()
        assertExists(app.buttons[AccessibilityID.ExpenseList.emptyAddButton], "Group should open.")

        app.buttons[AccessibilityID.ExpenseList.emptyAddButton].tap()
        replaceText(in: app.textFields[AccessibilityID.ExpenseForm.titleField], with: "Coffee")
        replaceText(in: app.textFields[AccessibilityID.ExpenseForm.amountField], with: "4.50")
        app.buttons[AccessibilityID.ExpenseForm.saveButton].tap()
        assertExists(app.staticTexts["Coffee"], "The expense should be saved.")

        openActivity(app)
        assertExists(
            app.staticTexts["Ana added “Coffee”."],
            "An expense added while identified as Ana should be credited to Ana."
        )
    }

    /// A line about an expense that is still there leads to it; a line about one that is gone
    /// keeps the title it had and leads nowhere.
    @MainActor
    func testAnEntryOpensTheExpenseItDescribes() async throws {
        let group = try await api.createGroup(name: "Tappable", participants: ["Ana", "Bruno"])
        try await api.createExpense(in: group, title: "Pizza night", amount: 3000, paidBy: "Ana")
        let app = launchApp(recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Tappable")]))

        openActivity(app, group)

        let entry = app.staticTexts["Someone added “Pizza night”."]
        assertExists(entry, "The log should list the expense being added.")
        entry.tap()

        let title = app.textFields[AccessibilityID.ExpenseForm.titleField]
        assertExists(title, "Tapping the entry should open the expense it describes.")
        XCTAssertEqual(title.value as? String, "Pizza night")
    }

    /// Deleting leaves the line behind — that is the whole point of a log — and the line has
    /// nowhere to lead once the expense is gone.
    @MainActor
    func testADeletedExpenseKeepsItsLineUnderTheTitleItHad() async throws {
        let group = try await api.createGroup(name: "Gone", participants: ["Ana", "Bruno"])
        try await api.createExpense(in: group, title: "Pizza night", amount: 3000, paidBy: "Ana")
        try await api.createExpense(in: group, title: "Museum tickets", amount: 2000, paidBy: "Ana")
        let app = launchApp(recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Gone")]))

        app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)].tap()
        let row = app.staticTexts["Pizza night"]
        assertExists(row, "The group’s expenses should load.")
        row.swipeLeft()
        assertExists(app.buttons["Delete"], "Swiping should reveal Delete.")
        app.buttons["Delete"].tap()

        // Out of the group and back in, which sends the delete rather than waiting out the
        // undo window, and gets a log the server has already written the deletion into.
        app.buttons["Groups"].tap()
        let listRow = app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)]
        assertExists(listRow, "Back on the groups list.")
        listRow.tap()

        openActivity(app)
        assertExists(
            app.staticTexts["Someone deleted “Pizza night”."],
            "A deleted expense should still be named on the line that describes deleting it."
        )
        assertExists(
            app.staticTexts["Someone added “Pizza night”."],
            "And the line that describes adding it should survive the delete too."
        )
    }

    @MainActor
    func testAGroupNothingHasHappenedInSaysSo() async throws {
        let group = try await api.createGroup(name: "Quiet", participants: ["Ana", "Bruno"])
        let app = launchApp(recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Quiet")]))

        app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)].tap()
        assertExists(app.buttons[AccessibilityID.ExpenseList.emptyAddButton], "Group should open.")

        openActivity(app)
        // Creating a group records nothing — only changing one does — so a brand-new group has
        // an empty log rather than a line about its own creation.
        assertExists(
            app.staticTexts["No activity yet"],
            "A group nothing has happened in should say so."
        )
    }

    /// Opens the group and then its activity tab. The group is optional because half of these
    /// are already inside it by the time they want the log.
    @MainActor
    private func openActivity(
        _ app: XCUIApplication,
        _ group: SpliitTestAPI.Group? = nil
    ) {
        if let group {
            app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)].tap()
        }
        let tab = app.buttons["Activity"]
        assertExists(tab, "The group should have an activity tab.")
        tab.tap()
    }
}
