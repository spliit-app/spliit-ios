import XCTest

/// The information tab: the group's note, who is in the group, and the way from an empty note to
/// a written one.
final class GroupInformationTests: SpliitUITestCase {

    @MainActor
    func testInformationTabShowsTheNoteAndTheParticipants() async throws {
        let note = "Beach house, 12–19 July. Ana has the keys."
        let group = try await api.createGroup(
            name: "Holiday",
            participants: ["Ana", "Bruno"],
            information: note
        )
        let app = launchApp(recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Holiday")]))

        app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)].tap()
        assertExists(app.buttons["Information"], "The group should have an information tab.")
        app.buttons["Information"].tap()

        let shown = app.staticTexts[AccessibilityID.GroupInformation.note]
        assertExists(shown, "The group's note should be on the information tab.")
        XCTAssertEqual(shown.label, note, "The note should be shown as it was written.")

        for name in ["Ana", "Bruno"] {
            let id = try XCTUnwrap(group.participants[name], "The group should know \(name).")
            assertExists(
                app.staticTexts[AccessibilityID.GroupInformation.participant(id)],
                "\(name) should be listed as a participant."
            )
        }

        assertExists(
            app.staticTexts[AccessibilityID.GroupInformation.currency],
            "The group's currency should be listed."
        )
        capture(app, "information-tab")
    }

    /// The note is a field on the group, so the tab sends you to the group editor rather than
    /// growing an editor of its own — and what comes back has to land on the tab.
    @MainActor
    func testAGroupWithoutANoteOffersToAddOne() async throws {
        let group = try await api.createGroup(name: "Blank", participants: ["Ana", "Bruno"])
        let app = launchApp(recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Blank")]))

        app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)].tap()
        assertExists(app.buttons["Information"], "The group should have an information tab.")
        app.buttons["Information"].tap()

        assertExists(
            app.staticTexts[AccessibilityID.GroupInformation.empty],
            "A group with no note should say so rather than show an empty row."
        )

        app.buttons[AccessibilityID.GroupInformation.editButton].tap()
        let field = informationField(in: app)
        assertExists(field, "Group settings should open on the note.")

        replaceText(in: field, with: "Split the villa evenly.")
        app.buttons[AccessibilityID.GroupForm.saveButton].tap()

        let shown = app.staticTexts[AccessibilityID.GroupInformation.note]
        assertExists(shown, "The saved note should replace the empty state.")
        XCTAssertEqual(shown.label, "Split the villa evenly.")
    }

    /// The note field is a `TextField(axis: .vertical)`, which XCUITest reports as a text view on
    /// some iOS versions and a text field on others. Ask for whichever one is actually there
    /// rather than betting on one and failing with "element does not exist".
    @MainActor
    private func informationField(in app: XCUIApplication) -> XCUIElement {
        let id = AccessibilityID.GroupForm.informationField
        let field = app.textFields[id]
        return field.waitForExistence(timeout: 10) ? field : app.textViews[id]
    }
}
