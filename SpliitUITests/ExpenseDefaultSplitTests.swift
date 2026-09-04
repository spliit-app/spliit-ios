import XCTest

/// Remembering how a group divides its expenses, so the next one starts there.
///
/// Which split is worth remembering, and what happens to one that has gone stale, is covered in
/// `make test`. What needs a simulator is the wiring: that the box is on the screen under the
/// split, that ticking it survives the save, and that the next expense form opens on what it
/// wrote — three separate places, none of which a unit test can see joined up.
final class ExpenseDefaultSplitTests: SpliitUITestCase {

    @MainActor
    func testASavedSplitPrefillsTheNextExpense() async throws {
        let group = try await api.createGroup(name: "Flat 3B", participants: ["Ana", "Bruno"])
        let app = launchApp(
            recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Flat 3B")])
        )
        let ana = try XCTUnwrap(group.participants["Ana"])
        let bruno = try XCTUnwrap(group.participants["Bruno"])

        app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)].tap()
        app.buttons[AccessibilityID.ExpenseList.emptyAddButton].tap()

        replaceText(in: app.textFields[AccessibilityID.ExpenseForm.titleField], with: "Rent")
        replaceText(in: app.textFields[AccessibilityID.ExpenseForm.amountField], with: "100.00")

        app.buttons["Percent"].tap()
        replaceText(
            in: app.textFields[AccessibilityID.ExpenseForm.participantValue(ana)], with: "70"
        )
        replaceText(
            in: app.textFields[AccessibilityID.ExpenseForm.participantValue(bruno)], with: "30"
        )

        // The switch, not the row: `tap()` takes the centre of the element, and the centre of a
        // `Toggle` row in a `Form` is empty space that swallows it. The first run of this test
        // saved an expense with the box still off and then failed two steps later, on the split
        // that had never been remembered — so the tick is asserted here, where it happens.
        let remember = app.switches[AccessibilityID.ExpenseForm.saveSplitToggle]
        scrollUntilHittable(remember, in: app)
        remember.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        capture(app, "expense-remember-split")
        XCTAssertEqual(remember.value as? String, "1", "The box should be ticked.")

        app.buttons[AccessibilityID.ExpenseForm.saveButton].tap()
        assertExists(app.staticTexts["Rent"], "The expense should save.")

        // The second expense is the whole point: nobody chooses "Percent" or types 70 again.
        app.buttons[AccessibilityID.ExpenseList.addButton].tap()
        let anasShare = app.textFields[AccessibilityID.ExpenseForm.participantValue(ana)]
        assertExists(anasShare, "A remembered split should bring the share fields back.")

        // A fresh form opens at the top, and a `Form` puts nothing below the fold in the
        // hierarchy at all — the second share row is not missing, it is not rendered yet.
        let brunosShare = app.textFields[AccessibilityID.ExpenseForm.participantValue(bruno)]
        scrollUntilHittable(brunosShare, in: app)
        capture(app, "expense-split-remembered")

        XCTAssertEqual(anasShare.value as? String, "70")
        XCTAssertEqual(brunosShare.value as? String, "30")
    }
}
