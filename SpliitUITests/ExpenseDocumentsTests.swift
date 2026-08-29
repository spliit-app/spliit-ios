import XCTest

/// Keeping the receipt with the expense.
///
/// This is the one feature of the app whose data does not live in Spliit's database: the instance
/// signs an upload, the picture goes straight to its bucket, and the expense stores nothing but
/// the address it landed at. So these tests are pointed at a real bucket — `make e2e-up` brings
/// one up beside the server, and CI starts the same thing — because a stubbed upload would prove
/// only that this app can talk to itself.
///
/// The photograph is the receipt the app draws for itself, as in `ReceiptScanTests`: a simulator
/// has no camera and an empty photo library. Everything downstream of the picture is real.
final class ExpenseDocumentsTests: SpliitUITestCase {

    @MainActor
    func testAReceiptIsAttachedAndKeptWithTheExpense() async throws {
        let group = try await api.createGroup(name: "Trip", participants: ["Ana", "Bruno"])
        let app = launchApp(
            recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Trip")]),
            receiptSample: true
        )

        app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)].tap()
        app.buttons[AccessibilityID.ExpenseList.emptyAddButton].tap()

        replaceText(in: app.textFields[AccessibilityID.ExpenseForm.titleField], with: "Hotel")
        replaceText(in: app.textFields[AccessibilityID.ExpenseForm.amountField], with: "80.00")

        let add = app.buttons[AccessibilityID.Documents.addButton]
        scrollUntilHittable(add, in: app)
        assertExists(add, "A new expense should offer to attach a document.")
        add.tap()

        // The thumbnail appearing is what says the upload finished — it is added to the grid
        // only once the instance has answered with an address.
        let thumbnail = app.buttons[AccessibilityID.Documents.thumbnail(0)]
        assertExists(thumbnail, "The receipt should appear in the grid once it is stored.")
        capture(app, "expense-documents")

        app.buttons[AccessibilityID.ExpenseForm.saveButton].tap()
        assertExists(app.staticTexts["Hotel"], "The expense should save.")

        let expense = try await api.expense(inGroup: group.id, titled: "Hotel")
        let documents = try XCTUnwrap(
            expense["documents"] as? [[String: Any]], "the expense should carry its documents"
        )
        XCTAssertEqual(documents.count, 1, "One photograph should have become one document.")

        let document = try XCTUnwrap(documents.first)
        let address = try XCTUnwrap(document["url"] as? String)

        // The size is stored alongside, and it describes the file rather than the photograph:
        // the picture is re-encoded on the way out, so this is what came back down from the cap
        // rather than whatever the camera produced.
        let width = try XCTUnwrap(document["width"] as? Int)
        let height = try XCTUnwrap(document["height"] as? Int)
        XCTAssertGreaterThan(width, 0)
        XCTAssertLessThanOrEqual(max(width, height), 2048, "A stored document should be resized.")

        // And the address has to be one anyone can open, because nothing signs it when it is
        // rendered — not this app, and not the web app either.
        let (data, response) = try await URLSession.shared.data(
            from: try XCTUnwrap(URL(string: address))
        )
        XCTAssertEqual(
            (response as? HTTPURLResponse)?.statusCode, 200,
            "The stored address should serve the picture to anybody who asks for it."
        )
        XCTAssertFalse(data.isEmpty)
    }

    /// Reopening is the half that has nothing left in memory: the picture has to come back down
    /// from the bucket at the address the expense stored, which is the whole of what the web app
    /// does with one too.
    @MainActor
    func testAnAttachedReceiptComesBackWhenTheExpenseIsReopened() async throws {
        let group = try await api.createGroup(name: "Trip", participants: ["Ana", "Bruno"])
        let app = launchApp(
            recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Trip")]),
            receiptSample: true
        )

        app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)].tap()
        app.buttons[AccessibilityID.ExpenseList.emptyAddButton].tap()
        replaceText(in: app.textFields[AccessibilityID.ExpenseForm.titleField], with: "Taxi")
        replaceText(in: app.textFields[AccessibilityID.ExpenseForm.amountField], with: "24.00")

        let add = app.buttons[AccessibilityID.Documents.addButton]
        scrollUntilHittable(add, in: app)
        add.tap()
        assertExists(
            app.buttons[AccessibilityID.Documents.thumbnail(0)],
            "The receipt should be stored before the expense is saved."
        )
        app.buttons[AccessibilityID.ExpenseForm.saveButton].tap()

        assertExists(app.staticTexts["Taxi"], "The expense should save.")
        app.staticTexts["Taxi"].tap()

        let reopened = app.buttons[AccessibilityID.Documents.thumbnail(0)]
        scrollUntilHittable(reopened, in: app)
        assertExists(reopened, "The document should be on the expense when it is opened again.")

        // Removing it forgets the address; the object stays in the bucket, which is what the web
        // app does as well — neither of them has credentials to delete anything.
        reopened.tap()
        let remove = app.buttons[AccessibilityID.Documents.removeButton]
        assertExists(remove, "The viewer should offer to remove the document.")
        remove.tap()

        // The viewer closes itself once there is nothing left in it, and the grid it came from
        // has to have lost the tile — otherwise the save below would write the document back.
        XCTAssertTrue(
            app.buttons[AccessibilityID.Documents.doneButton].waitForNonExistence(timeout: 15),
            "The viewer should close when its last document is removed."
        )
        XCTAssertTrue(
            reopened.waitForNonExistence(timeout: 15),
            "The removed document should be gone from the grid."
        )

        let save = app.buttons[AccessibilityID.ExpenseForm.saveButton]
        save.tap()
        XCTAssertTrue(
            save.waitForNonExistence(timeout: 30), "The expense should save and the form close."
        )

        let expense = try await api.expense(inGroup: group.id, titled: "Taxi")
        XCTAssertEqual(
            (expense["documents"] as? [[String: Any]])?.count, 0,
            "A removed document should be gone from the expense."
        )
    }
}
