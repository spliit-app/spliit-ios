import XCTest

/// The totals tab: what the group has spent, and the two figures that only exist once somebody
/// has said who they are.
final class GroupStatsTests: SpliitUITestCase {

    /// Before anybody answers, the tab is one number — and it says so rather than showing two
    /// empty rows where the personal figures will go.
    @MainActor
    func testTotalsShowTheGroupSpendingBeforeAnybodyHasSaidWhoTheyAre() async throws {
        let group = try await seedTrip(named: "Anonymous")
        let app = launchApp(recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Anonymous")]))

        openTotals(of: group, in: app)

        let total = app.staticTexts[AccessibilityID.Stats.groupTotal]
        assertExists(total, "The group’s own total needs nobody’s permission.")
        XCTAssertEqual(total.label, "$200.00", "The hotel and the dinner together.")
        XCTAssertEqual(
            app.staticTexts[AccessibilityID.Stats.groupTotalLabel].label,
            "Total group spending"
        )

        XCTAssertFalse(
            app.staticTexts[AccessibilityID.Stats.yourSpending].exists,
            "Nobody has said who they are, so there is no “your” anything to show."
        )
        assertExists(
            app.buttons[AccessibilityID.ActiveUser.statsButton],
            "The tab should offer the question its missing figures depend on."
        )
        capture(app, "totals-anonymous")
    }

    /// The question is asked here as well as on the balances tab, because here it is worth two
    /// of the three numbers on screen.
    @MainActor
    func testSayingWhoYouAreAddsYourSpendingAndYourShare() async throws {
        let group = try await seedTrip(named: "Whose totals")
        let app = launchApp(
            recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Whose totals")])
        )

        openTotals(of: group, in: app)

        let ask = app.buttons[AccessibilityID.ActiveUser.statsButton]
        assertExists(ask, "A group nobody has answered for should ask the question.")
        ask.tap()

        let ana = try XCTUnwrap(group.participants["Ana"])
        let option = app.buttons[AccessibilityID.ActiveUser.option(ana)]
        assertExists(option, "The picker should list the group’s participants.")
        option.tap()

        let spending = app.staticTexts[AccessibilityID.Stats.yourSpending]
        assertExists(spending, "Answering should bring in what you paid.")
        XCTAssertEqual(spending.label, "$120.00", "Ana paid for the hotel and nothing else.")
        XCTAssertEqual(
            app.staticTexts[AccessibilityID.Stats.yourShare].label, "$100.00",
            "Half the hotel and half the dinner."
        )

        // The slice each figure is of the group's spending — which the amount alone cannot say
        // was measured against the right whole.
        XCTAssertEqual(
            app.staticTexts[AccessibilityID.Stats.yourSpendingFraction].label, "60% of the group"
        )
        XCTAssertEqual(
            app.staticTexts[AccessibilityID.Stats.yourShareFraction].label, "50% of the group"
        )
        capture(app, "totals-personal")
    }

    /// What the footer on that screen claims. Settling up moves money without spending any, and
    /// counting it would inflate all three figures.
    @MainActor
    func testReimbursementsAreLeftOutOfEveryTotal() async throws {
        let group = try await api.createGroup(name: "Settled", participants: ["Ana", "Bruno"])
        try await api.createExpense(in: group, title: "Hotel", amount: 10000, paidBy: "Ana")
        try await api.createExpense(
            in: group,
            title: "Paying Ana back",
            amount: 5000,
            paidBy: "Bruno",
            paidFor: ["Ana"],
            isReimbursement: true
        )
        let ana = try XCTUnwrap(group.participants["Ana"])
        let app = launchApp(
            recentGroups: SpliitTestAPI.recentGroupsJSON(
                organised: [(id: group.id, name: "Settled", isStarred: false, isArchived: false)],
                activeParticipants: [group.id: ana]
            )
        )

        openTotals(of: group, in: app)

        assertExists(app.staticTexts[AccessibilityID.Stats.groupTotal], "Totals should load.")
        XCTAssertEqual(
            app.staticTexts[AccessibilityID.Stats.groupTotal].label, "$100.00",
            "The 50 Bruno handed back is not another 50 the group spent."
        )
        XCTAssertEqual(
            app.staticTexts[AccessibilityID.Stats.yourSpending].label, "$100.00",
            "Ana paid for the hotel; being paid back is not spending either."
        )
        XCTAssertEqual(app.staticTexts[AccessibilityID.Stats.yourShare].label, "$50.00")
    }

    /// A group can take in more than it spends — a deposit returned, a refund split back. The
    /// caption is what carries that, because the amount below it is drawn unsigned.
    @MainActor
    func testAGroupThatHasTakenMoreInThanItSpentSaysEarnings() async throws {
        let group = try await api.createGroup(name: "Refunded", participants: ["Ana", "Bruno"])
        try await api.createExpense(in: group, title: "Deposit back", amount: -8000, paidBy: "Ana")
        let app = launchApp(recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Refunded")]))

        openTotals(of: group, in: app)

        let label = app.staticTexts[AccessibilityID.Stats.groupTotalLabel]
        assertExists(label, "Totals should load.")
        XCTAssertEqual(
            label.label, "Total group earnings",
            "The sentence is what says which way it goes."
        )
        XCTAssertEqual(
            app.staticTexts[AccessibilityID.Stats.groupTotal].label, "$80.00",
            "Unsigned, because the caption above already said it."
        )
        capture(app, "totals-earnings")
    }

    /// The totals are loaded lazily — nothing asks for them until this tab is opened — so the
    /// thing that can go wrong is them never being asked again.
    @MainActor
    func testTotalsFollowAnExpenseAddedFromAnotherTab() async throws {
        let group = try await api.createGroup(name: "Growing", participants: ["Ana", "Bruno"])
        try await api.createExpense(in: group, title: "Hotel", amount: 10000, paidBy: "Ana")
        let app = launchApp(recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Growing")]))

        openTotals(of: group, in: app)
        assertExists(app.staticTexts[AccessibilityID.Stats.groupTotal], "Totals should load.")
        XCTAssertEqual(app.staticTexts[AccessibilityID.Stats.groupTotal].label, "$100.00")

        app.buttons["Expenses"].tap()
        app.buttons[AccessibilityID.ExpenseList.addButton].tap()
        replaceText(in: app.textFields[AccessibilityID.ExpenseForm.titleField], with: "Museum")
        replaceText(in: app.textFields[AccessibilityID.ExpenseForm.amountField], with: "50.00")
        app.buttons[AccessibilityID.ExpenseForm.saveButton].tap()
        assertExists(app.staticTexts["Museum"], "The new expense should reach the list.")

        app.buttons["Totals"].tap()
        let total = app.staticTexts[AccessibilityID.Stats.groupTotal]
        assertExists(total, "The totals tab should still be there.")
        XCTAssertEqual(
            total.label, "$150.00",
            "An expense added elsewhere should have refreshed the totals behind it."
        )
    }

    /// The breakdown is folded on the client from every expense in the group, because
    /// `groups.stats.get` answers three totals and no more. What that has to get right is the
    /// arithmetic, the order, and leaving settling up out of it.
    @MainActor
    func testTheBreakdownByCategoryAddsUpToTheGroupTotal() async throws {
        let group = try await api.createGroup(name: "Categorised", participants: ["Ana", "Bruno"])
        // Category IDs are the server's own seeded table: 9 is Groceries, 35 is Taxi.
        try await api.createExpense(
            in: group, title: "Market", amount: 3000, paidBy: "Ana", category: 9
        )
        try await api.createExpense(
            in: group, title: "Corner shop", amount: 1000, paidBy: "Bruno", category: 9
        )
        try await api.createExpense(
            in: group, title: "Airport", amount: 6000, paidBy: "Ana", category: 35
        )
        try await api.createExpense(
            in: group,
            title: "Paying Ana back",
            amount: 2500,
            paidBy: "Bruno",
            paidFor: ["Ana"],
            category: 35,
            isReimbursement: true
        )
        let app = launchApp(
            recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Categorised")])
        )

        openTotals(of: group, in: app)

        let taxi = app.staticTexts[AccessibilityID.Stats.categoryAmount(35)]
        assertExists(taxi, "The breakdown should list the categories the group used.")
        XCTAssertEqual(
            taxi.label, "$60.00",
            "The 25 handed back was settling up, so it is not another taxi fare."
        )
        XCTAssertEqual(
            app.staticTexts[AccessibilityID.Stats.categoryAmount(9)].label, "$40.00",
            "Two shopping trips, added together."
        )
        XCTAssertEqual(
            app.staticTexts[AccessibilityID.Stats.groupTotal].label, "$100.00",
            "And the two categories are the whole of what the group spent."
        )

        // Biggest first, which is the only reason the order is worth asserting at all.
        let names = app.staticTexts.matching(
            NSPredicate(format: "identifier BEGINSWITH 'stats.category.' AND identifier ENDSWITH '.name'")
        )
        XCTAssertEqual(
            names.element(boundBy: 0).identifier, AccessibilityID.Stats.categoryName(35),
            "Taxi outspent groceries, so it leads."
        )
        capture(app, "totals-by-category")
    }

    // MARK: - Helpers

    /// $200.00 spent, $120.00 of it by Ana, whose share comes to $100.00 — amounts chosen so the
    /// two slices land on whole percentages.
    @MainActor
    private func seedTrip(named name: String) async throws -> SpliitTestAPI.Group {
        let group = try await api.createGroup(name: name, participants: ["Ana", "Bruno"])
        try await api.createExpense(in: group, title: "Hotel", amount: 12000, paidBy: "Ana")
        try await api.createExpense(in: group, title: "Dinner", amount: 8000, paidBy: "Bruno")
        return group
    }

    @MainActor
    private func openTotals(of group: SpliitTestAPI.Group, in app: XCUIApplication) {
        let row = app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)]
        assertExists(row, "The seeded group should be on the home screen.")
        row.tap()
        assertExists(app.buttons["Totals"], "The group should have a totals tab.")
        app.buttons["Totals"].tap()
    }
}
