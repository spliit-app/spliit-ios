import XCTest

/// Starring and archiving, from the home screen.
///
/// Nothing here needs the server: the list, and now the order it is in, are entirely local. What
/// these cover is the part that isn't — that the gesture reaches the store, that the row lands in
/// the right section, and that it is still there after the app is closed.
final class GroupOrganizationTests: SpliitUITestCase {

    private let lisbon = "lisbon-id"
    private let flat = "flat-id"

    private let twoGroups = """
        [{"groupId":"lisbon-id","groupName":"Weekend in Lisbon"},\
        {"groupId":"flat-id","groupName":"Flat 3B"}]
        """

    @MainActor
    func testStarringAGroupLiftsItAboveTheRest() {
        let app = launchApp(recentGroups: twoGroups)

        // Seeded second, so it starts below — which is the point of starring it.
        star(app, flat)

        assertExists(sectionHeader(app, "Starred"), "Starring should open a Starred section.")
        XCTAssertLessThan(
            rowTitle(app, flat).frame.minY,
            rowTitle(app, lisbon).frame.minY,
            "A starred group belongs above the unstarred ones."
        )
    }

    /// Through the long-press menu rather than a swipe: a swipe action nobody can see is only
    /// half the feature, and this is the half that has to be discoverable.
    @MainActor
    func testArchivingAGroupPutsItAtTheBottom() {
        let app = launchApp(recentGroups: twoGroups)

        let row = rowTitle(app, lisbon)
        assertExists(row, "Both seeded groups should be listed.")
        row.press(forDuration: 1.2)

        let archive = menuItem(app, AccessibilityID.GroupsList.rowArchiveButton(lisbon))
        assertExists(archive, "The long-press menu should offer Archive.")
        archive.tap()

        assertExists(sectionHeader(app, "Archived"), "Archiving should open an Archived section.")
        XCTAssertGreaterThan(
            rowTitle(app, lisbon).frame.minY,
            rowTitle(app, flat).frame.minY,
            "An archived group belongs below the rest."
        )
    }

    @MainActor
    func testAStarSurvivesARelaunch() {
        let app = launchApp(recentGroups: twoGroups)
        star(app, flat)
        assertExists(sectionHeader(app, "Starred"), "The group should be starred to begin with.")

        app.terminate()
        // No reset and no seed: whatever the first launch wrote is what this one has to read.
        let relaunched = launchApp(resetState: false)

        assertExists(
            sectionHeader(relaunched, "Starred"),
            "A star is stored with the group, so it should still be there."
        )
        XCTAssertLessThan(
            rowTitle(relaunched, flat).frame.minY,
            rowTitle(relaunched, lisbon).frame.minY,
            "And it should still be the group at the top."
        )
    }

    // MARK: - Helpers

    @MainActor
    private func star(_ app: XCUIApplication, _ groupID: String) {
        let row = rowTitle(app, groupID)
        assertExists(row, "The row to star should be listed.")
        row.swipeRight()

        let button = app.buttons[AccessibilityID.GroupsList.rowStarButton(groupID)]
        assertExists(button, "Swiping from the leading edge should reveal Star.")
        button.tap()
    }

    @MainActor
    private func rowTitle(_ app: XCUIApplication, _ groupID: String) -> XCUIElement {
        app.staticTexts[AccessibilityID.GroupsList.rowTitle(groupID)]
    }

    /// Matched case-insensitively: a section header's case belongs to the list style, and this
    /// test is about which section a row is in, not how iOS chose to set the word.
    @MainActor
    private func sectionHeader(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.staticTexts
            .matching(NSPredicate(format: "label ==[c] %@", title))
            .firstMatch
    }

    /// A long-press menu's items are buttons in some iOS versions and menu items in others, and
    /// the identifier is the part that doesn't move.
    @MainActor
    private func menuItem(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
