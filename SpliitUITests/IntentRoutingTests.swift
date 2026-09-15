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
            addExpense: IntentExpense(groupID: group.id, title: "Taxi", amount: "23.50")
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

    /// A shortcut built around a card tapped at a till knows more than the merchant and the
    /// amount: the category, a note, and the receipt it photographed all come with it.
    ///
    /// Asserted on the server, as `ReceiptScanTests` does: the category row is below the fold on
    /// a small phone, and what was saved is what matters. The photograph is the one the app
    /// draws for itself, uploaded for real to the harness's bucket. This first ran against a
    /// version that only started the upload once the documents grid had scrolled into view, and
    /// it caught that only because it saves without scrolling — see the note in CLAUDE.md.
    @MainActor
    func testAddingAnExpenseCarriesTheCategoryNotesAndReceipt() async throws {
        let group = try await api.createGroup(name: "Lisbon", participants: ["Ana", "Bruno"])

        let app = launchApp(
            recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Lisbon")]),
            addExpense: IntentExpense(
                groupID: group.id,
                title: "Pingo Doce",
                amount: "42.10",
                categoryID: 9,  // Groceries, in every instance's seed
                notes: "Rua Augusta",
                documents: 1
            )
        )

        let title = app.textFields[AccessibilityID.ExpenseForm.titleField]
        assertExists(title, "The expense form should be open at launch.")
        XCTAssertEqual(title.value as? String, "Pingo Doce", "The title should be filled in.")

        // Deliberately not scrolled to the documents grid first. The upload has to start as the
        // form opens, wherever the grid sits on this phone's screen, and Save has to wait for
        // it: a handover that only happened once the grid came into view would pass a test
        // that scrolled there, and drop the receipt for anybody who saved without looking.
        let save = app.buttons[AccessibilityID.ExpenseForm.saveButton]
        let enabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isEnabled == true"), object: save
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [enabled], timeout: 30), .completed,
            "Save should come back once the receipt has landed."
        )
        save.tap()
        assertExists(app.staticTexts["Pingo Doce"], "The expense should save.")

        let expense = try await api.expense(inGroup: group.id, titled: "Pingo Doce")
        XCTAssertEqual(expense["amount"] as? Int, 4210)
        XCTAssertEqual(
            (expense["category"] as? [String: Any])?["name"] as? String, "Groceries",
            "The category the shortcut chose should be the one saved."
        )
        XCTAssertEqual(expense["notes"] as? String, "Rua Augusta", "The note should be saved.")
        XCTAssertEqual(
            (expense["documents"] as? [[String: Any]])?.count, 1,
            "The photograph the shortcut was given should be kept with the expense."
        )
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
