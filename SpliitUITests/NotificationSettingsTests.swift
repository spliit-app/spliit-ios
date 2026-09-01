import XCTest

/// What the app interrupts for: the default on the settings sheet, and each group's own answer.
///
/// The delivery half cannot be driven from here. A background refresh is scheduled by iOS and
/// never runs on a simulator, and the permission prompt is a Springboard alert that blocks the
/// app until somebody answers it — every launch here suppresses it. What this suite covers is
/// everything on this side of that: that the two settings are stored, that a group's own answer
/// outranks the default, and that the screen says so when the narrow level has nobody to filter
/// against. The rules themselves are `ActivityNotificationTests`, in a couple of milliseconds.
final class NotificationSettingsTests: SpliitUITestCase {

    @MainActor
    func testTheDefaultIsRememberedAcrossLaunches() async throws {
        let app = launchApp()

        openSettings(in: app)
        let level = app.buttons[AccessibilityID.Notifications.defaultLevel]
        assertExists(level, "Settings should offer a default notification level.")
        XCTAssertEqual(
            level.value as? String, "Only what involves me",
            "A fresh install should start on the useful middle, not on silence."
        )

        level.tap()
        choose("Everything", in: app)
        app.buttons[AccessibilityID.Settings.doneButton].tap()

        app.terminate()
        // Nothing reset: what the app starts from is what it wrote last time.
        let relaunched = launchApp(resetState: false)
        openSettings(in: relaunched)

        let reopened = relaunched.buttons[AccessibilityID.Notifications.defaultLevel]
        assertExists(reopened, "Settings should still offer the level after a relaunch.")
        XCTAssertEqual(
            reopened.value as? String, "Everything",
            "The default should have survived the relaunch."
        )
    }

    /// The point of having a default: a group that has said what it wants keeps it, and the
    /// default goes on meaning what it meant for every group that never said.
    @MainActor
    func testAGroupCanDisagreeWithTheDefault() async throws {
        let group = try await api.createGroup(name: "Quiet", participants: ["Ana", "Bruno"])
        let app = launchApp(recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Quiet")]))

        let level = openGroupNotifications(of: group, in: app)
        XCTAssertEqual(
            level.value as? String, "Same as default (Only what involves me)",
            "A group nobody has set should follow the default, and say which one that is."
        )

        level.tap()
        choose("Nothing", in: app)

        let changed = app.buttons[AccessibilityID.Notifications.groupLevel]
        assertExists(changed, "The row should still be there after choosing.")
        XCTAssertEqual(
            changed.value as? String, "Nothing",
            "The group should now hold an answer of its own."
        )

        // And the default it stopped following is untouched.
        app.buttons["Groups"].tap()
        openSettings(in: app)
        let fallback = app.buttons[AccessibilityID.Notifications.defaultLevel]
        assertExists(fallback, "Settings should still offer the default.")
        XCTAssertEqual(
            fallback.value as? String, "Only what involves me",
            "One group going quiet should not have moved the default."
        )
    }

    /// "Only what involves me" is a filter, and a filter needs something to match against. A
    /// group whose "You" has never been answered has nothing, so it widens — and says so, rather
    /// than leaving the widening to be discovered on a busy evening.
    @MainActor
    func testTheNarrowLevelSaysWhenItHasNobodyToMatchAgainst() async throws {
        let group = try await api.createGroup(name: "Nameless", participants: ["Ana", "Bruno"])
        let app = launchApp(recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Nameless")]))

        let level = openGroupNotifications(of: group, in: app)
        assertExists(
            app.staticTexts[AccessibilityID.Notifications.identityNeeded],
            "A group that does not know who you are cannot narrow anything down, and should say so."
        )

        let you = app.buttons[AccessibilityID.ActiveUser.informationButton]
        scrollUntilHittable(you, in: app)
        you.tap()

        let ana = try XCTUnwrap(group.participants["Ana"])
        let option = app.buttons[AccessibilityID.ActiveUser.option(ana)]
        assertExists(option, "The picker should list the group’s participants.")
        option.tap()

        // The row is what says the section is still drawn, so the absence below is an absence
        // rather than a screen that has scrolled away from the answer.
        scrollUntilHittable(level, in: app)
        assertExists(level, "The notification row should still be on the information tab.")
        XCTAssertFalse(
            app.staticTexts[AccessibilityID.Notifications.identityNeeded].exists,
            "Once you have said who you are, there is nothing left to warn about."
        )
    }

    // MARK: - Getting there

    @MainActor
    private func openSettings(in app: XCUIApplication) {
        let button = app.buttons[AccessibilityID.GroupsList.settingsButton]
        assertExists(button, "The home screen should offer settings.")
        button.tap()
    }

    /// Opens the group's information tab and scrolls to the notification row, which sits at the
    /// bottom with the other setting that belongs to this phone rather than to the group.
    ///
    /// Scrolled to *before* it is asserted on, deliberately: a `List` is a collection view, and a
    /// row it has not yet had reason to build does not exist to be waited for — the wait would
    /// spend its whole timeout and then fail about a row that is only off screen.
    @MainActor
    private func openGroupNotifications(
        of group: SpliitTestAPI.Group, in app: XCUIApplication
    ) -> XCUIElement {
        let row = app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)]
        assertExists(row, "The seeded group should be on the home screen.")
        row.tap()

        assertExists(app.buttons["Information"], "The group should have an information tab.")
        app.buttons["Information"].tap()

        let level = app.buttons[AccessibilityID.Notifications.groupLevel]
        scrollUntilHittable(level, in: app)
        assertExists(level, "The information tab should offer this group’s notification level.")
        return level
    }

    /// Picks an option off the list the level row pushes. Matched by its own words rather than by
    /// an identifier: an identifier on the picker is stamped onto every row it opens, so all four
    /// would be indistinguishable from each other and from the row that opened them.
    @MainActor
    private func choose(_ option: String, in app: XCUIApplication) {
        let choice = app.buttons[option]
        assertExists(choice, "The level list should offer “\(option)”.")
        choice.tap()
    }
}
