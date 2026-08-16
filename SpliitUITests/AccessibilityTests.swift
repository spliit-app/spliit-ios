import UIKit
import XCTest

/// The app at the largest accessibility text size, and the controls a screen reader has to be
/// able to describe.
///
/// Both of these fail silently. Dynamic Type never crashes: a row grows past the width it had,
/// a two-column layout collapses to a few characters each, and the app merely becomes unusable.
/// A control built out of the wrong primitive is worse — it looks right and simply never
/// announces its state.
final class AccessibilityTests: SpliitUITestCase {

    private let largestSize = UIContentSizeCategory.accessibilityExtraExtraExtraLarge

    @MainActor
    func testGroupsListOpensAGroupAtTheLargestTextSize() async throws {
        let group = try await api.createGroup(name: "Big text", participants: ["Ana", "Bruno"])
        let app = launchApp(
            recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Big text")]),
            textSize: largestSize
        )

        let row = app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)]
        assertExists(row, "The group row should survive the largest text size.")
        capture(app, "groups-list-ax5")

        XCTAssertTrue(row.isHittable, "A row that has grown off its own cell can't be tapped.")
        row.tap()

        assertExists(
            app.buttons[AccessibilityID.ExpenseList.emptyAddButton],
            "Tapping the row should still open the group."
        )
    }

    /// The balances row puts a name against an amount. That is the layout large text breaks
    /// first, and the one where a truncated amount is worse than no amount at all.
    @MainActor
    func testBalancesKeepBothColumnsAtTheLargestTextSize() async throws {
        let group = try await api.createGroup(name: "Wide", participants: ["Ana", "Bruno"])
        try await api.createExpense(in: group, title: "Hotel", amount: 10000, paidBy: "Ana")
        let app = launchApp(
            recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Wide")]),
            textSize: largestSize
        )

        app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)].tap()
        assertExists(app.staticTexts["Hotel"], "The seeded expense should load.")

        app.buttons["Balances"].tap()

        let ana = try XCTUnwrap(group.participants["Ana"])
        let bruno = try XCTUnwrap(group.participants["Bruno"])
        assertExists(
            app.staticTexts[AccessibilityID.Balances.participantAmount(ana)],
            "Balances should list the payer at any text size."
        )
        capture(app, "balances-ax5")

        // Both halves of the row have to be intact: stacking them must not cost the amount.
        XCTAssertEqual(
            app.staticTexts[AccessibilityID.Balances.participantAmount(ana)].label, "$50.00"
        )
        XCTAssertEqual(
            app.staticTexts[AccessibilityID.Balances.participantAmount(bruno)].label, "-$50.00"
        )
        XCTAssertTrue(
            app.staticTexts[AccessibilityID.Balances.participantName(ana)].exists,
            "The name should not be dropped to make room for the amount."
        )

        // The list is lazy, and at this text size two balance rows fill the screen — the
        // suggested payments below them are not built until they are scrolled towards, so this
        // has to scroll before asking whether they exist.
        let settle = app.buttons[AccessibilityID.Balances.markAsPaid(0)]
        for _ in 0..<10 where !settle.isHittable { app.swipeUp() }
        XCTAssertTrue(
            settle.isHittable,
            "The suggested payment should be reachable by scrolling at the largest text size."
        )
    }

    /// The welcome screen is the first thing a new install shows, and at this text size its
    /// description on its own is taller than the phone. The empty state scrolls for that reason —
    /// what has to hold is that neither action ends up stranded below the fold with no way down.
    @MainActor
    func testWelcomeActionsAreReachableAtTheLargestTextSize() {
        let app = launchApp(textSize: largestSize)

        assertExists(
            app.buttons[AccessibilityID.GroupsList.createGroupButton],
            "A fresh install should show the welcome screen at any text size."
        )
        capture(app, "welcome-ax5")

        // The second action sits below the first, so it is the one that falls off the bottom.
        let addByLink = app.buttons[AccessibilityID.GroupsList.addByURLButton]
        for _ in 0..<10 where !addByLink.isHittable { app.swipeUp() }
        XCTAssertTrue(
            addByLink.isHittable,
            "Both welcome actions have to be reachable by scrolling at the largest text size."
        )
    }

    /// The paid-for checkboxes are a custom `ToggleStyle` drawn out of a `Button`. Without an
    /// accessibility representation they announce as buttons and never say whether the
    /// participant is in the split — the checkmark is the only cue, and it is purely visual.
    ///
    /// Run at the default text size: this is about what the control reports, not about layout.
    @MainActor
    func testParticipantCheckboxesAnnounceWhetherTheyAreOn() async throws {
        let group = try await api.createGroup(name: "Splits", participants: ["Ana", "Bruno"])
        let app = launchApp(recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Splits")]))

        app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)].tap()
        app.buttons[AccessibilityID.ExpenseList.emptyAddButton].tap()
        assertExists(
            app.textFields[AccessibilityID.ExpenseForm.titleField], "The form should open."
        )

        let ana = try XCTUnwrap(group.participants["Ana"])
        let checkbox = app.descendants(matching: .any)[
            AccessibilityID.ExpenseForm.participantToggle(ana)
        ]
        assertExists(checkbox, "The paid-for list should include every participant.")

        // A plain button reports no value at all; a toggle reports its state. Asserting on the
        // value rather than the element type keeps this honest without pinning down which
        // control SwiftUI builds underneath.
        XCTAssertEqual(
            checkbox.value as? String,
            "1",
            "An included participant has to announce that it is on, not read as a bare button."
        )

        checkbox.tap()
        XCTAssertEqual(
            checkbox.value as? String,
            "0",
            "Excluding a participant has to announce the new state too."
        )
    }
}
