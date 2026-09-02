import XCTest

/// Takes the screenshots the App Store listing ships, one run per language.
///
/// This is not an assertion suite, and `make e2e` skips it — `make screenshots` is what runs it,
/// once per language, with `-testLanguage`. What it *does* assert is that the screen it is about
/// to photograph has actually arrived: a photograph of a spinner looks like a working app right
/// up until someone opens the file.
///
/// The pictures leave as attachments on the result bundle, named `01-groups` and so on;
/// `Scripts/screenshots.sh` exports them and names the files after them, which is what puts them
/// in order in App Store Connect.
final class ScreenshotTests: SpliitUITestCase {

    /// The tabs of the group screen, named by the SF Symbol each one carries.
    ///
    /// Their labels are localised, and an identifier of our own would be stamped over every
    /// element inside the tab — the trap `AccessibilityID` is written around. What is left is
    /// the symbol name, which SwiftUI puts on the tab button itself: the same in every language,
    /// and the same on both devices. Position is not: iPhone puts these in a tab bar at the
    /// bottom, iPad puts them in the navigation bar as plain buttons, and `app.tabBars` is empty
    /// there. Every tap is still confirmed by waiting on something only that tab's content
    /// carries.
    private enum GroupTab: String {
        case expenses = "list.bullet"
        case balances = "arrow.left.arrow.right"
        case stats = "chart.pie"
    }

    @MainActor
    func testCaptureListingScreenshots() async throws {
        let content = ScreenshotContent.forCurrentLanguage()
        let seeded = try await seed(content)
        let hero = try XCTUnwrap(seeded.first)

        // Who the listing's screenshots are taken as: the hero group's first participant, who
        // is also the one who paid for the flat — so the balances shot leads with a number
        // worth photographing rather than with the question that offers to find it.
        let you = hero.group.participants[content.hero.participants[0]]

        let app = launchApp(
            recentGroups: SpliitTestAPI.recentGroupsJSON(
                organised: seeded.map {
                    (
                        id: $0.group.id,
                        name: $0.spec.name,
                        isStarred: $0.spec.isStarred,
                        isArchived: $0.spec.isArchived
                    )
                },
                activeParticipants: you.map { [hero.group.id: $0] } ?? [:]
            )
        )

        // 1 — the home screen: what this device remembers, starred group first.
        for entry in seeded {
            assertExists(
                app.staticTexts[AccessibilityID.GroupsList.rowTitle(entry.group.id)],
                "Every seeded group should be listed."
            )
        }
        // The participant counts arrive from the server after the list has already drawn, and a
        // row still showing "…" is the one thing on this screen that looks broken.
        assertExists(
            app.staticTexts[AccessibilityID.GroupsList.rowParticipants(hero.group.id)],
            "The group details should have loaded."
        )
        try await photograph("01-groups")

        // 2 — a group's expenses, in their date buckets, each with its category.
        app.staticTexts[AccessibilityID.GroupsList.rowTitle(hero.group.id)].tap()
        assertExists(
            app.staticTexts[content.hero.expenses[0].title],
            "The group's expenses should load."
        )
        try await photograph("02-expenses")

        // 3 — one expense, split unevenly. Opened rather than typed: a form filled in by hand
        // photographs with a keyboard over the half of it worth showing.
        let showcase = try XCTUnwrap(
            content.hero.expenses.first { $0.title == content.showcaseExpense },
            "The showcase expense should be one of the seeded ones."
        )
        XCTAssertNotNil(
            showcase.shares,
            "The showcase expense is the one with named shares — that is what it is for."
        )

        // The *last* participant, so scrolling stops with the whole split list on screen rather
        // than with the first row of it. Asking `shares` for a participant would not do: it is a
        // dictionary, so it hands back an arbitrary one, and the shot ends up framed differently
        // from run to run — which is how the French iPad screenshot came to show one name where
        // the English one showed four.
        let lastSharer = try XCTUnwrap(
            content.hero.participants.last.flatMap { hero.group.participants[$0] },
            "The hero group should have participants."
        )

        app.staticTexts[content.showcaseExpense].tap()
        assertExists(
            app.textFields[AccessibilityID.ExpenseForm.titleField],
            "Tapping the expense should open it."
        )
        try await scroll(
            app,
            until: app.textFields[AccessibilityID.ExpenseForm.participantValue(lastSharer)]
        )
        try await photograph("03-split")
        app.buttons[AccessibilityID.ExpenseForm.cancelButton].tap()

        // 4 — who is up, who is down, and the fewest payments that end it.
        let anyone = try XCTUnwrap(hero.group.participants[content.hero.participants[0]])
        open(.balances, in: app)
        assertExists(
            app.staticTexts[AccessibilityID.Balances.participantName(anyone)],
            "The balances tab should show the participants."
        )
        assertExists(
            app.staticTexts[AccessibilityID.ActiveUser.total],
            "And it should lead with the balance of whoever the screenshots are taken as."
        )
        try await photograph("04-balances")

        // 5 — what the group actually spent, and how much of it is yours. Beside the balances
        // for the reason the tab sits beside them: that screen says where the group will end
        // up, this one says where it has been.
        open(.stats, in: app)
        assertExists(
            app.staticTexts[AccessibilityID.Stats.groupTotal],
            "The totals tab should show what the group spent."
        )
        assertExists(
            app.staticTexts[AccessibilityID.Stats.yourShare],
            "And the share belonging to whoever the screenshots are taken as."
        )
        try await photograph("05-totals")
    }

    // MARK: - Seeding

    private struct Seeded {
        let spec: ScreenshotContent.GroupSpec
        let group: SpliitTestAPI.Group
    }

    /// Creates the demo data on the instance from `make e2e-up`, hero group first.
    ///
    /// Expenses go in oldest first so that "most recently added" and "most recent date" agree,
    /// which is the order the list would be in for a group anyone actually used.
    @MainActor
    private func seed(_ content: ScreenshotContent) async throws -> [Seeded] {
        var seeded: [Seeded] = []
        for spec in content.groups {
            let group = try await api.createGroup(
                name: spec.name,
                participants: spec.participants,
                information: spec.information,
                currency: spec.currency,
                currencyCode: spec.currencyCode
            )
            for expense in spec.expenses.sorted(by: { $0.daysAgo > $1.daysAgo }) {
                try await api.createExpense(
                    in: group,
                    title: expense.title,
                    amount: expense.amount,
                    paidBy: expense.paidBy,
                    daysAgo: expense.daysAgo,
                    category: expense.category,
                    splitMode: expense.splitMode,
                    shares: expense.shares,
                    notes: expense.notes,
                    // Credited to whoever paid, so the activity log photographs as a group of
                    // people rather than as a column of "Someone" — which is what an
                    // unattributed write leaves behind, permanently.
                    by: group.participants[expense.paidBy]
                )
            }
            seeded.append(Seeded(spec: spec, group: group))
        }
        return seeded
    }

    // MARK: - Driving

    @MainActor
    private func open(_ tab: GroupTab, in app: XCUIApplication) {
        // `firstMatch`: iPad nests the button inside a second one carrying the same identifier.
        let button = app.buttons[tab.rawValue].firstMatch
        if !button.waitForExistence(timeout: 15) {
            // The hierarchy, not just the miss. A tab that cannot be found is nearly always a
            // tab bar that lives somewhere else on this device, and the only way to know where
            // is to look.
            let dump = XCTAttachment(string: app.debugDescription)
            dump.name = "hierarchy-\(tab)"
            dump.lifetime = .keepAlways
            add(dump)
            XCTFail("The group screen has no “\(tab.rawValue)” tab.")
            return
        }
        button.tap()
    }

    /// Scrolls until the element is on screen, or gives up and says so.
    ///
    /// Bounded, deliberately: an unbounded `while !element.isHittable { swipeUp() }` is what once
    /// turned a missing element into a CI job that swiped for forty minutes.
    ///
    /// A short drag rather than `swipeUp`, which throws the list a whole screen at a time and
    /// overshoots whatever it was aiming for. That is not a nicety here: on the iPad, where the
    /// expense form is a sheet in the middle of the screen rather than the whole of it, one
    /// swipe carried the unevenly split share off the top, and the shot meant to show a split
    /// that isn't equal showed three identical numbers.
    @MainActor
    private func scroll(_ app: XCUIApplication, until element: XCUIElement) async throws {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.70))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.50))
        for _ in 0..<8 {
            if element.exists, element.isHittable { return }
            from.press(forDuration: 0.05, thenDragTo: to)
            try await settle(seconds: 0.4)
        }
        XCTAssertTrue(element.isHittable, "Scrolling never brought the element into view.")
    }

    // MARK: - Capturing

    /// Photographs the whole screen — status bar included, which is where the 9:41 the script
    /// pins comes from — and attaches it under a name the export step turns into a file name.
    ///
    /// Deliberately not the base class's `capture`, which photographs the *app* so a failing run
    /// can be read later. Here the status bar is part of the picture, so the screen is.
    @MainActor
    private func photograph(_ name: String) async throws {
        // Long enough for a list to finish its arrival animation and for the glass to settle.
        // Everything worth photographing here is already asserted to exist; what is left is
        // motion, and motion is only ever caught halfway.
        try await settle(seconds: 0.9)

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func settle(seconds: Double) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }
}
