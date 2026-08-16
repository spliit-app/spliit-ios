import XCTest

/// Getting a group onto the device: creating one, and adding one someone shared.
///
/// Suites are kept small and roughly equal in size on purpose — XCUITest parallelises by
/// class, so one large class is one long pole no number of workers can shorten.
final class GroupCreationTests: SpliitUITestCase {

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

    /// The currency is the one thing on this form that outlives the form: every amount in the
    /// group is shown with it, and the ISO code behind it is what the web app reads.
    @MainActor
    func testPickingACurrencyIsSavedWithTheGroup() {
        let app = launchApp()

        app.buttons[AccessibilityID.GroupsList.createGroupButton].tap()
        replaceText(in: app.textFields[AccessibilityID.GroupForm.nameField], with: "Alpine trip")

        app.buttons[AccessibilityID.GroupForm.currencyButton].tap()
        assertExists(
            app.buttons[AccessibilityID.CurrencyPicker.row("USD")],
            "The picker should open on the suggestions."
        )
        capture(app, "currency-picker")

        // A search with nothing behind it still has to offer a way forward.
        replaceText(in: app.searchFields.firstMatch, with: "zzzz")
        assertExists(
            app.staticTexts["No matching currency"],
            "A search that matches nothing should say so rather than show an empty list."
        )
        XCTAssertTrue(
            app.buttons[AccessibilityID.CurrencyPicker.customOption].exists,
            "And it should still offer the custom symbol."
        )

        replaceText(in: app.searchFields.firstMatch, with: "Swiss")
        let swissFranc = app.buttons[AccessibilityID.CurrencyPicker.row("CHF")]
        assertExists(swissFranc, "Searching for the currency by name should find it.")
        swissFranc.tap()

        let currency = app.buttons[AccessibilityID.GroupForm.currencyButton]
        assertExists(currency, "Choosing a currency should come back to the form.")
        capture(app, "group-form-currency")
        XCTAssertTrue(
            currency.label.contains("Swiss Franc"),
            "The form should show what was picked, not what it started with."
        )

        app.buttons[AccessibilityID.GroupForm.saveButton].tap()
        assertExists(
            app.buttons[AccessibilityID.ExpenseList.emptyAddButton],
            "Saving should open the new group."
        )

        // Reopened from the server rather than from the form's own state: this is what proves
        // the ISO code was sent and stored, not just displayed.
        app.buttons[AccessibilityID.GroupDetail.menuButton].tap()
        app.buttons[AccessibilityID.GroupDetail.editGroupButton].tap()

        let saved = app.buttons[AccessibilityID.GroupForm.currencyButton]
        assertExists(saved, "Group settings should open.")
        XCTAssertTrue(
            saved.label.contains("Swiss Franc"),
            "The group should still be in francs when it comes back from the server."
        )
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
}
