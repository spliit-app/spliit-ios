import XCTest

/// Recording an expense that was paid in a currency the group is not counted in.
///
/// The rate itself is stubbed through a launch argument: it is the one number in the app that
/// comes from outside the Spliit instance under test, and a suite that asked the real service
/// for it would be as reliable as the runner's connection and as stable as the day's market.
final class ExpenseCurrencyTests: SpliitUITestCase {

    @MainActor
    func testAnExpensePaidInAnotherCurrencyIsStoredAtWhatItConvertsTo() async throws {
        // The test API makes dollar groups, so euros are the other currency here.
        let group = try await api.createGroup(name: "Trip", participants: ["Ana", "Bruno"])
        let app = launchApp(
            recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Trip")]),
            exchangeRate: "0.5"
        )

        app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)].tap()
        app.buttons[AccessibilityID.ExpenseList.emptyAddButton].tap()
        replaceText(in: app.textFields[AccessibilityID.ExpenseForm.titleField], with: "Dinner")

        app.buttons[AccessibilityID.ExpenseForm.currencyButton].tap()
        assertExists(
            app.buttons[AccessibilityID.CurrencyPicker.row("EUR")],
            "The picker should offer the currency the expense was paid in."
        )
        app.buttons[AccessibilityID.CurrencyPicker.row("EUR")].tap()

        let paid = app.textFields[AccessibilityID.ExpenseForm.originalAmountField]
        assertExists(paid, "Picking another currency should ask what was paid in it.")
        replaceText(in: paid, with: "40.00")

        // Filled in by the lookup, so this is the published rate arriving rather than a default.
        XCTAssertEqual(
            app.textFields[AccessibilityID.ExpenseForm.conversionRateField].value as? String,
            "0.5"
        )
        capture(app, "expense-currency")

        // €40.00 at 0.5 is $20.00, and the total is the conversion rather than anything typed.
        // The row reads as one element once the amount stops being a field, which is what a
        // screen reader should hear: the label and the value together.
        XCTAssertEqual(
            app.staticTexts[AccessibilityID.ExpenseForm.amountField].label, "Amount, $20.00"
        )

        app.buttons[AccessibilityID.ExpenseForm.saveButton].tap()
        assertExists(app.staticTexts["Dinner"], "The converted expense should save.")

        let expense = try await api.expense(inGroup: group.id, titled: "Dinner")
        XCTAssertEqual(expense["amount"] as? Int, 2000)
        XCTAssertEqual(expense["originalAmount"] as? Int, 4000)
        XCTAssertEqual(expense["originalCurrency"] as? String, "EUR")
    }

    /// The rate is a convenience, never a requirement — which is also the only way to record the
    /// rate a card was actually charged at.
    @MainActor
    func testARateCanBeEnteredWhenNoneCanBeFetched() async throws {
        let group = try await api.createGroup(name: "Offline trip", participants: ["Ana", "Bruno"])
        let app = launchApp(
            recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Offline trip")]),
            exchangeRate: "none"
        )

        app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)].tap()
        app.buttons[AccessibilityID.ExpenseList.emptyAddButton].tap()
        replaceText(in: app.textFields[AccessibilityID.ExpenseForm.titleField], with: "Taxi")

        app.buttons[AccessibilityID.ExpenseForm.currencyButton].tap()
        app.buttons[AccessibilityID.CurrencyPicker.row("EUR")].tap()

        replaceText(
            in: app.textFields[AccessibilityID.ExpenseForm.originalAmountField], with: "10.00"
        )

        // Saving now would be saving an expense with no total at all.
        app.buttons[AccessibilityID.ExpenseForm.saveButton].tap()
        assertExists(
            app.staticTexts[AccessibilityID.ExpenseForm.error],
            "An expense with no rate should be refused rather than sent."
        )

        replaceText(
            in: app.textFields[AccessibilityID.ExpenseForm.conversionRateField], with: "1.25"
        )
        app.buttons[AccessibilityID.ExpenseForm.saveButton].tap()

        assertExists(app.staticTexts["Taxi"], "A rate entered by hand should save.")

        let expense = try await api.expense(inGroup: group.id, titled: "Taxi")
        XCTAssertEqual(expense["amount"] as? Int, 1250)
    }
}
