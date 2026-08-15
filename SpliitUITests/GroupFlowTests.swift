import XCTest

/// The Milestone 1 flows, driven through the UI against a real server.
final class GroupFlowTests: SpliitUITestCase {

    // MARK: - Creating a group

    @MainActor
    func testCreateGroupOpensItAndRemembersIt() {
        let app = launchApp()

        app.buttons[AccessibilityID.GroupsList.createGroupButton].tap()
        assertExists(app.textFields[AccessibilityID.GroupForm.nameField], "The form should open.")

        replaceText(in: app.textFields[AccessibilityID.GroupForm.nameField], with: "Ski trip")
        capture(app, "create-group")
        app.buttons[AccessibilityID.GroupForm.saveButton].tap()

        // Creating a group navigates straight into it.
        assertExists(
            app.buttons[AccessibilityID.ExpenseList.emptyAddButton],
            "A new group should open on its empty expense list."
        )
        XCTAssertTrue(app.staticTexts["Ski trip"].exists)

        // And it is remembered when you come back out.
        app.navigationBars.buttons.firstMatch.tap()
        assertExists(app.staticTexts["Ski trip"], "The new group should be in the list.")
    }

    @MainActor
    func testGroupNameIsValidatedBeforeSaving() {
        let app = launchApp()

        app.buttons[AccessibilityID.GroupsList.createGroupButton].tap()
        replaceText(in: app.textFields[AccessibilityID.GroupForm.nameField], with: "A")
        app.buttons[AccessibilityID.GroupForm.saveButton].tap()

        assertExists(
            app.staticTexts[AccessibilityID.GroupForm.error],
            "A one-character name should be rejected in the form, not by the server."
        )
        XCTAssertTrue(
            app.textFields[AccessibilityID.GroupForm.nameField].exists,
            "The form should stay open."
        )
    }

    // MARK: - Adding a group by link

    @MainActor
    func testAddGroupByLink() async throws {
        let group = try await api.createGroup(name: "Shared trip", participants: ["Ana", "Bruno"])
        let app = launchApp()

        app.buttons[AccessibilityID.GroupsList.addByURLButton].tap()
        replaceText(
            in: app.textFields[AccessibilityID.AddByURL.field],
            with: "\(baseURL)groups/\(group.id)"
        )
        app.buttons[AccessibilityID.AddByURL.addButton].tap()

        assertExists(app.staticTexts["Shared trip"], "The linked group should join the list.")
    }

    @MainActor
    func testAddGroupByLinkRejectsAnUnknownGroup() {
        let app = launchApp()

        app.buttons[AccessibilityID.GroupsList.addByURLButton].tap()
        replaceText(
            in: app.textFields[AccessibilityID.AddByURL.field],
            with: "\(baseURL)groups/not-a-real-group"
        )
        app.buttons[AccessibilityID.AddByURL.addButton].tap()

        assertExists(
            app.staticTexts[AccessibilityID.AddByURL.error],
            "An unknown group should be reported, not silently added."
        )
    }

    // MARK: - Expenses

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

    /// The split-mode rules are the easiest thing to get subtly wrong, and the server would
    /// reject this too — the point is that the user finds out before the round trip.
    @MainActor
    func testAmountSplitMustAddUpToTheTotal() async throws {
        let group = try await api.createGroup(name: "Split test", participants: ["Ana", "Bruno"])
        let app = launchApp(
            recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Split test")])
        )

        app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)].tap()
        app.buttons[AccessibilityID.ExpenseList.emptyAddButton].tap()

        replaceText(in: app.textFields[AccessibilityID.ExpenseForm.titleField], with: "Taxi")
        replaceText(in: app.textFields[AccessibilityID.ExpenseForm.amountField], with: "30.00")

        app.buttons["Amount"].tap()

        let ana = try XCTUnwrap(group.participants["Ana"])
        let bruno = try XCTUnwrap(group.participants["Bruno"])
        replaceText(in: app.textFields[AccessibilityID.ExpenseForm.participantValue(ana)], with: "10")
        replaceText(in: app.textFields[AccessibilityID.ExpenseForm.participantValue(bruno)], with: "10")

        app.buttons[AccessibilityID.ExpenseForm.saveButton].tap()

        assertExists(
            app.staticTexts[AccessibilityID.ExpenseForm.error],
            "A split that doesn’t reach the total should be refused."
        )
        capture(app, "split-validation")

        // Fixing it lets the save through.
        replaceText(in: app.textFields[AccessibilityID.ExpenseForm.participantValue(bruno)], with: "20")
        app.buttons[AccessibilityID.ExpenseForm.saveButton].tap()

        assertExists(app.staticTexts["Taxi"], "A balanced split should save.")
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
        for _ in 0..<10 where !delete.isHittable { app.swipeUp() }
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
        try await api.createExpense(in: group, title: "Recent one", amount: 100, paidBy: "Ana", daysAgo: 1)
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

    // MARK: - Balances

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

    // MARK: - Group settings

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
}
