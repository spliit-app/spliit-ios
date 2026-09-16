import XCTest

/// How an expense is divided: the paid-for list, the split-mode rules, and what each share comes
/// to.
///
/// The apportionment itself — who gets the odd cent — is covered in `make test`, against the web
/// app's own cases. What needs a simulator is that the number on the screen is the number the
/// server charges, which only the balances tab can confirm.
final class ExpenseSplitTests: SpliitUITestCase {

    /// $95 three ways is 31.67, 31.67 and 31.66: the amounts are whole cents, they add up to the
    /// total, and the one shown for a participant is the one the balances tab charges them.
    @MainActor
    func testEachShareIsShownAndMatchesTheBalances() async throws {
        let group = try await api.createGroup(
            name: "Odd cents", participants: ["Ana", "Bruno", "Chloé"]
        )
        try await api.createExpense(in: group, title: "Brunch", amount: 9500, paidBy: "Ana")
        let app = launchApp(
            recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Odd cents")])
        )
        let ana = try XCTUnwrap(group.participants["Ana"])
        let bruno = try XCTUnwrap(group.participants["Bruno"])
        let chloe = try XCTUnwrap(group.participants["Chloé"])

        app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)].tap()
        assertExists(app.staticTexts["Brunch"], "The seeded expense should be listed.")
        app.staticTexts["Brunch"].tap()

        // Scroll before looking: a `Form` puts nothing below the fold in the hierarchy at all,
        // and at the larger text sizes the paid-for list is well below it.
        assertExists(app.textFields[AccessibilityID.ExpenseForm.titleField], "The editor should open.")
        let shares = [ana, bruno, chloe].map {
            app.staticTexts[AccessibilityID.ExpenseForm.participantShareAmount($0)]
        }
        scrollUntilHittable(shares[2], in: app)
        for share in shares {
            XCTAssertTrue(share.exists, "Each participant in the split should show their share.")
        }
        capture(app, "expense-shares-evenly")

        XCTAssertEqual(
            shares.map(\.label).sorted(), ["$31.66", "$31.67", "$31.67"],
            "Three whole-cent shares that add up to the total."
        )
        let brunosShare = shares[1].label
        let chloesShare = shares[2].label

        // Neither of them paid anything, so what the server says they owe is exactly their
        // share of this one expense — and it must be the same number the form just showed.
        app.buttons[AccessibilityID.ExpenseForm.cancelButton].tap()
        app.buttons["Balances"].tap()
        assertExists(
            app.staticTexts[AccessibilityID.Balances.participantAmount(bruno)],
            "Balances should list everyone."
        )
        XCTAssertEqual(
            app.staticTexts[AccessibilityID.Balances.participantAmount(bruno)].label,
            "-\(brunosShare)"
        )
        XCTAssertEqual(
            app.staticTexts[AccessibilityID.Balances.participantAmount(chloe)].label,
            "-\(chloesShare)"
        )
    }

    /// The cent lands where the form said it would. $16.57 over two people is 8.28 and 8.29, and
    /// which of them gets the 8.29 is decided by a hash of the expense's ID — so the form mints
    /// the ID before saving and sends it with the create, rather than previewing with none and
    /// letting the server's own ID move the cent to the other person (spliit#646). This needs an
    /// instance that creates the expense under the ID it is given, which is what CI's server
    /// pin guarantees; against one older than spliit#647 it is a coin toss.
    @MainActor
    func testTheOddCentStaysWhereItWasPreviewed() async throws {
        let group = try await api.createGroup(name: "Odd cent", participants: ["Ana", "Bruno"])
        let app = launchApp(
            recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Odd cent")])
        )
        let ana = try XCTUnwrap(group.participants["Ana"])
        let bruno = try XCTUnwrap(group.participants["Bruno"])

        app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)].tap()
        app.buttons[AccessibilityID.ExpenseList.emptyAddButton].tap()
        replaceText(in: app.textFields[AccessibilityID.ExpenseForm.titleField], with: "Dinner")
        replaceText(in: app.textFields[AccessibilityID.ExpenseForm.amountField], with: "16.57")

        let anasShare = app.staticTexts[AccessibilityID.ExpenseForm.participantShareAmount(ana)]
        let brunosShare = app.staticTexts[AccessibilityID.ExpenseForm.participantShareAmount(bruno)]
        scrollUntilHittable(brunosShare, in: app)
        XCTAssertEqual(
            [anasShare, brunosShare].map(\.label).sorted(), ["$8.28", "$8.29"],
            "Two whole-cent shares that add up to the total."
        )
        let previewed = brunosShare.label

        app.buttons[AccessibilityID.ExpenseForm.saveButton].tap()
        assertExists(app.staticTexts["Dinner"], "The expense should save.")

        // Reopened, the expense has the ID it was saved under — and the same cent in the same
        // place, or the two would be two different splits of the same dinner.
        app.staticTexts["Dinner"].tap()
        assertExists(app.textFields[AccessibilityID.ExpenseForm.titleField], "The editor should open.")
        scrollUntilHittable(brunosShare, in: app)
        XCTAssertEqual(brunosShare.label, previewed, "The saved split should be the previewed one.")

        // And the balances tab is the server's own arithmetic over that ID: Bruno paid nothing,
        // so what he owes is exactly the share the form showed him before it was saved.
        app.buttons[AccessibilityID.ExpenseForm.cancelButton].tap()
        app.buttons["Balances"].tap()
        assertExists(
            app.staticTexts[AccessibilityID.Balances.participantAmount(bruno)],
            "Balances should list everyone."
        )
        XCTAssertEqual(
            app.staticTexts[AccessibilityID.Balances.participantAmount(bruno)].label,
            "-\(previewed)"
        )
    }

    /// The amounts follow the split as it is typed, and step aside where the field beside the
    /// name already is the amount.
    @MainActor
    func testSharesFollowTheSplitAsItIsTyped() async throws {
        let group = try await api.createGroup(
            name: "Live shares", participants: ["Ana", "Bruno", "Chloé"]
        )
        let app = launchApp(
            recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Live shares")])
        )
        let ana = try XCTUnwrap(group.participants["Ana"])
        let bruno = try XCTUnwrap(group.participants["Bruno"])
        let chloe = try XCTUnwrap(group.participants["Chloé"])

        app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)].tap()
        app.buttons[AccessibilityID.ExpenseList.emptyAddButton].tap()
        replaceText(in: app.textFields[AccessibilityID.ExpenseForm.titleField], with: "Wine")
        replaceText(in: app.textFields[AccessibilityID.ExpenseForm.amountField], with: "95.00")

        let anasShare = app.staticTexts[AccessibilityID.ExpenseForm.participantShareAmount(ana)]
        let brunosShare = app.staticTexts[AccessibilityID.ExpenseForm.participantShareAmount(bruno)]
        scrollUntilHittable(brunosShare, in: app)
        XCTAssertTrue(brunosShare.isHittable, "An even split should show what each share is.")
        // Who gets the odd cents is decided by a hash of the ID the form minted for this
        // expense, which is different every time, so the three are checked together rather
        // than each on its own.
        let chloesShare = app.staticTexts[AccessibilityID.ExpenseForm.participantShareAmount(chloe)]
        XCTAssertEqual(
            [anasShare, brunosShare, chloesShare].map(\.label).sorted(),
            ["$31.66", "$31.67", "$31.67"],
            "An even split of $95 is 31.67, 31.67 and 31.66."
        )

        // Two shares against one and one: 47.50 and 23.75 twice, with nothing left to round.
        // Waited for rather than read straight after the keystroke: the label is a snapshot,
        // and a slow runner can take it before the row has been redrawn.
        app.buttons["Shares"].tap()
        replaceText(in: app.textFields[AccessibilityID.ExpenseForm.participantValue(ana)], with: "2")
        waitForLabel(of: anasShare, toBe: "$47.50")
        capture(app, "expense-shares-by-shares")
        XCTAssertEqual(anasShare.label, "$47.50")
        XCTAssertEqual(brunosShare.label, "$23.75")

        // Under a split by amount the field is the amount, so there is nothing to add beside it.
        app.buttons["Amount"].tap()
        XCTAssertTrue(
            anasShare.waitForNonExistence(timeout: 5),
            "A split by amount should not repeat the field beside it."
        )
    }

    /// The split-mode rules are the easiest thing to get subtly wrong, and the server would
    /// reject this too — the point is that the user finds out before the round trip.
    @MainActor
    func testAmountSplitMustAddUpToTheTotal() async throws {
        let group = try await api.createGroup(name: "Split test", participants: ["Ana", "Bruno"])
        let app = launchApp(
            recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Split test")])
        )

        app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)].tap()
        app.buttons[AccessibilityID.ExpenseList.emptyAddButton].tap()

        replaceText(in: app.textFields[AccessibilityID.ExpenseForm.titleField], with: "Taxi")
        replaceText(in: app.textFields[AccessibilityID.ExpenseForm.amountField], with: "30.00")

        app.buttons["Amount"].tap()

        let ana = try XCTUnwrap(group.participants["Ana"])
        let bruno = try XCTUnwrap(group.participants["Bruno"])
        replaceText(in: app.textFields[AccessibilityID.ExpenseForm.participantValue(ana)], with: "10")
        replaceText(in: app.textFields[AccessibilityID.ExpenseForm.participantValue(bruno)], with: "10")

        app.buttons[AccessibilityID.ExpenseForm.saveButton].tap()

        assertExists(
            app.staticTexts[AccessibilityID.ExpenseForm.error],
            "A split that doesn’t reach the total should be refused."
        )
        capture(app, "split-validation")

        // Fixing it lets the save through.
        replaceText(in: app.textFields[AccessibilityID.ExpenseForm.participantValue(bruno)], with: "20")
        app.buttons[AccessibilityID.ExpenseForm.saveButton].tap()

        assertExists(app.staticTexts["Taxi"], "A balanced split should save.")
    }

    /// One control that flips the whole paid-for list, for the group where an expense covers
    /// nearly nobody and unchecking everyone by hand is the slow way round.
    @MainActor
    func testSelectAllAndNoneFlipTheWholePaidForList() async throws {
        let group = try await api.createGroup(
            name: "Select test", participants: ["Ana", "Bruno", "Chloé"]
        )
        let app = launchApp(
            recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Select test")])
        )

        app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)].tap()
        app.buttons[AccessibilityID.ExpenseList.emptyAddButton].tap()
        replaceText(in: app.textFields[AccessibilityID.ExpenseForm.titleField], with: "Groceries")
        replaceText(in: app.textFields[AccessibilityID.ExpenseForm.amountField], with: "30.00")

        let selectAll = app.buttons[AccessibilityID.ExpenseForm.selectAllButton]
        scrollUntilHittable(selectAll, in: app)
        XCTAssertTrue(selectAll.isHittable, "The paid-for header should offer a select control.")

        // A new expense starts with everyone in it, so the only thing left to offer is the way out.
        XCTAssertEqual(selectAll.label.lowercased(), "select none")

        let ana = try XCTUnwrap(group.participants["Ana"])
        let anaCheckbox = app.descendants(matching: .any)[
            AccessibilityID.ExpenseForm.participantToggle(ana)
        ]
        XCTAssertEqual(anaCheckbox.value as? String, "1", "Everyone starts in the split.")

        selectAll.tap()
        XCTAssertEqual(anaCheckbox.value as? String, "0", "Select none should clear the list.")
        XCTAssertEqual(selectAll.label.lowercased(), "select all")

        // An expense paid for nobody is not one the server would take either.
        app.buttons[AccessibilityID.ExpenseForm.saveButton].tap()
        assertExists(
            app.staticTexts[AccessibilityID.ExpenseForm.error],
            "An expense with nobody in the split should be refused."
        )

        scrollUntilHittable(selectAll, in: app)
        selectAll.tap()
        XCTAssertEqual(anaCheckbox.value as? String, "1", "Select all should bring everyone back.")

        app.buttons[AccessibilityID.ExpenseForm.saveButton].tap()
        assertExists(app.staticTexts["Groceries"], "The restored split should save.")
    }
}
