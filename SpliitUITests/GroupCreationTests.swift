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
