import XCTest

/// Saying who you are in a group, and the two things that then change: the balance the tab
/// leads with, and who a new expense is paid by.
final class ActiveUserTests: SpliitUITestCase {

    @MainActor
    func testSayingWhoYouAreShowsYourOwnBalance() async throws {
        let group = try await api.createGroup(name: "Whose", participants: ["Ana", "Bruno"])
        try await api.createExpense(in: group, title: "Hotel", amount: 10000, paidBy: "Ana")
        let app = launchApp(recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Whose")]))

        openBalances(of: group, in: app)

        let ask = app.buttons[AccessibilityID.ActiveUser.balancesButton]
        assertExists(ask, "A group nobody has answered for should ask the question.")
        ask.tap()

        let ana = try XCTUnwrap(group.participants["Ana"])
        let option = app.buttons[AccessibilityID.ActiveUser.option(ana)]
        assertExists(option, "The picker should list the group’s participants.")
        option.tap()

        let total = app.staticTexts[AccessibilityID.ActiveUser.total]
        assertExists(total, "Answering should replace the question with your own balance.")
        XCTAssertEqual(
            total.label, "$50.00",
            "Ana paid the whole hotel and owes half of it, so half is owed back to her."
        )
        XCTAssertEqual(
            app.staticTexts[AccessibilityID.ActiveUser.direction].label, "You are owed",
            "The direction is a sentence, because the amount above is unsigned."
        )
        XCTAssertTrue(
            app.staticTexts[AccessibilityID.ActiveUser.badge(ana)].exists,
            "Your own row in the list below should say which one it is."
        )
        capture(app, "personal-balance")
    }

    /// The question is answered once and read back on every launch — it lives in the same file
    /// as the group list, which is the thing an upgrading user must never lose.
    @MainActor
    func testWhoYouAreSurvivesARelaunch() async throws {
        let group = try await api.createGroup(name: "Again", participants: ["Ana", "Bruno"])
        try await api.createExpense(in: group, title: "Hotel", amount: 10000, paidBy: "Ana")
        let app = launchApp(recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Again")]))

        openBalances(of: group, in: app)
        let ask = app.buttons[AccessibilityID.ActiveUser.balancesButton]
        assertExists(ask, "A group nobody has answered for should ask the question.")
        ask.tap()

        let bruno = try XCTUnwrap(group.participants["Bruno"])
        let option = app.buttons[AccessibilityID.ActiveUser.option(bruno)]
        assertExists(option, "The picker should list the group’s participants.")
        option.tap()
        assertExists(
            app.staticTexts[AccessibilityID.ActiveUser.total],
            "Answering should show a balance."
        )

        app.terminate()
        // Nothing seeded and nothing reset: what the app starts from is what it wrote last time.
        let relaunched = launchApp(recentGroups: nil, resetState: false)
        openBalances(of: group, in: relaunched)

        let total = relaunched.staticTexts[AccessibilityID.ActiveUser.total]
        assertExists(total, "The answer should still be there on the next launch.")
        XCTAssertEqual(
            total.label, "$50.00",
            "Bruno’s half of the hotel is what he owes for it."
        )
        XCTAssertEqual(
            relaunched.staticTexts[AccessibilityID.ActiveUser.direction].label, "You owe",
            "And he is the one owing it."
        )
    }

    @MainActor
    func testANewExpenseIsPaidByWhoeverYouSaidYouAre() async throws {
        let group = try await api.createGroup(name: "Payer", participants: ["Ana", "Bruno"])
        let app = launchApp(recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Payer")]))

        openBalances(of: group, in: app)
        let ask = app.buttons[AccessibilityID.ActiveUser.balancesButton]
        assertExists(ask, "A group nobody has answered for should ask the question.")
        ask.tap()

        let bruno = try XCTUnwrap(group.participants["Bruno"])
        let option = app.buttons[AccessibilityID.ActiveUser.option(bruno)]
        assertExists(option, "The picker should list the group’s participants.")
        option.tap()

        // Bruno is second in the list, so the form's old default — the first participant — is
        // the wrong answer and this cannot pass by accident.
        app.buttons["Expenses"].tap()
        app.buttons[AccessibilityID.ExpenseList.addButton].tap()

        let title = app.textFields[AccessibilityID.ExpenseForm.titleField]
        assertExists(title, "The expense form should open.")
        replaceText(in: title, with: "Coffee")
        replaceText(in: app.textFields[AccessibilityID.ExpenseForm.amountField], with: "10.00")
        app.buttons[AccessibilityID.ExpenseForm.saveButton].tap()

        let row = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Paid by Bruno")
        ).firstMatch
        assertExists(row, "The expense should have been paid by whoever you said you are.")
    }

    @MainActor
    private func openBalances(of group: SpliitTestAPI.Group, in app: XCUIApplication) {
        let row = app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)]
        assertExists(row, "The seeded group should be on the home screen.")
        row.tap()
        app.buttons["Balances"].tap()
    }
}
