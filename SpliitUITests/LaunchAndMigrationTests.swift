import XCTest

/// The Milestone 0 end-to-end coverage: the app launches, and — the one that really matters —
/// an install upgrading from the React Native app still has its groups.
final class LaunchAndMigrationTests: SpliitUITestCase {

    @MainActor
    func testFreshInstallShowsTheWelcomeScreen() {
        let app = launchApp()

        assertExists(
            app.buttons[AccessibilityID.GroupsList.createGroupButton],
            "A fresh install should land on the welcome screen."
        )
        XCTAssertTrue(app.staticTexts["Welcome to Spliit"].exists)
    }

    @MainActor
    func testRememberedGroupsAppearInTheList() {
        let app = launchApp(
            recentGroups: #"[{"groupId":"abc","groupName":"Weekend in Lisbon"}]"#
        )

        assertExists(
            app.staticTexts["Weekend in Lisbon"],
            "A remembered group should be listed by name."
        )
    }

    /// The migration is unattended and one-shot, and a group is only reachable by its ID — so
    /// if this ever regresses, upgrading users lose their groups with no way back.
    @MainActor
    func testUpgradeFromReactNativeKeepsRecentGroups() {
        let app = launchApp(
            legacyStore: [
                "recent-groups":
                    #"[{"groupId":"abc","groupName":"Weekend in Lisbon"},{"groupId":"def","groupName":"Flat 3B"}]"#,
                "spliit-settings": #"{"baseUrl":"https://spliit.app/"}"#,
            ]
        )

        assertExists(
            app.staticTexts["Weekend in Lisbon"],
            "Groups from the React Native app should survive the update."
        )
        XCTAssertTrue(app.staticTexts["Flat 3B"].exists)
    }

    /// A user with roughly fifteen or more groups had their list spilled into an MD5-named
    /// sidecar file rather than kept inline in the manifest.
    @MainActor
    func testUpgradeKeepsALongGroupListFromItsSidecarFile() throws {
        let groups = (1...40).map { ["groupId": "id-\($0)", "groupName": "Group number \($0)"] }
        let encoded = String(
            decoding: try JSONSerialization.data(withJSONObject: groups), as: UTF8.self
        )
        XCTAssertGreaterThan(encoded.count, 1024, "This test is pointless if the value fits inline.")

        let app = launchApp(legacyStore: ["recent-groups": encoded])

        assertExists(
            app.staticTexts["Group number 1"],
            "A spilled group list should still be migrated."
        )
    }

    @MainActor
    func testSelfHostedAddressCarriesOverFromTheOldApp() {
        let app = launchApp(
            legacyStore: ["spliit-settings": #"{"baseUrl":"https://spliit.example.com/"}"#],
            resetState: true,
            overrideBaseURL: false
        )

        app.buttons[AccessibilityID.GroupsList.settingsButton].tap()

        let field = app.textFields[AccessibilityID.Settings.baseURLField]
        assertExists(field, "Settings should open.")
        XCTAssertEqual(field.value as? String, "https://spliit.example.com/")
    }

    @MainActor
    func testSettingsOpensAndDismisses() {
        let app = launchApp()

        app.buttons[AccessibilityID.GroupsList.settingsButton].tap()
        assertExists(app.buttons[AccessibilityID.Settings.doneButton], "Settings should open.")
        XCTAssertTrue(app.textFields[AccessibilityID.Settings.baseURLField].exists)

        app.buttons[AccessibilityID.Settings.doneButton].tap()
        assertExists(
            app.buttons[AccessibilityID.GroupsList.createGroupButton],
            "Dismissing settings should return to the group list."
        )
    }
}
