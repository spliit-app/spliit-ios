import XCTest

/// Opening the app with a group link, which is how somebody is let into a group in the first
/// place.
///
/// Which links count is unit-tested in `IncomingLinkTests`, in a suite that needs no simulator.
/// What these cover is what happens after one is accepted.
final class GroupLinkTests: SpliitUITestCase {

    @MainActor
    func testALinkToAnUnknownGroupJoinsItAndOpensIt() async throws {
        let group = try await api.createGroup(name: "Shared trip", participants: ["Ana", "Bruno"])
        try await api.createExpense(in: group, title: "Ferry", amount: 1200, paidBy: "Ana")

        // Nothing remembered: this device is being let into the group by the link alone.
        let app = launchApp(
            recentGroups: SpliitTestAPI.recentGroupsJSON([]),
            openURL: "\(baseURL)groups/\(group.id)"
        )

        assertExists(app.staticTexts["Ferry"], "The link should open the group.")
        capture(app, "opened-from-link")

        // And it is remembered, so the next launch does not need the link again.
        app.buttons["Groups"].tap()
        assertExists(
            app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)],
            "The group should have been added to the list."
        )
    }

    @MainActor
    func testALinkToAGroupAlreadyOnTheListJustOpensIt() async throws {
        let group = try await api.createGroup(name: "Known", participants: ["Ana", "Bruno"])
        try await api.createExpense(in: group, title: "Ferry", amount: 1200, paidBy: "Ana")

        let app = launchApp(
            recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Known")]),
            openURL: "\(baseURL)groups/\(group.id)"
        )

        assertExists(app.staticTexts["Ferry"], "The link should open the group.")

        app.buttons["Groups"].tap()
        XCTAssertEqual(
            app.staticTexts.matching(
                identifier: AccessibilityID.GroupsList.rowTitle(group.id)
            ).count,
            1,
            "Opening a group by link should not add a second copy of it."
        )
    }

    /// A link naming a group the server has never heard of says so, rather than opening an
    /// empty screen or adding a group that does not exist.
    @MainActor
    func testALinkToANonexistentGroupSaysSo() {
        let app = launchApp(
            recentGroups: SpliitTestAPI.recentGroupsJSON([]),
            openURL: "\(baseURL)groups/not-a-real-group"
        )

        assertExists(app.staticTexts["Couldn’t open that link"], "The failure should be shown.")
        capture(app, "bad-link")
    }
}
