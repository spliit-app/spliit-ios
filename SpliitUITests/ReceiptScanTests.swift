import XCTest

/// Filling in an expense from a photograph of the receipt.
///
/// The photo is one the app draws for itself — a simulator has no camera and an empty photo
/// library — but everything downstream of it is real: `RecognizeDocumentsRequest` transcribes it
/// and `ReceiptText` reads the transcript. That pair is the half of this feature that can break
/// without anyone noticing, since a receipt read wrongly still produces a perfectly valid expense.
///
/// The on-device model is deliberately out of the loop here. It is not on every phone, its answer
/// is not the same twice, and a suite that asserted on one would be asserting on the weather.
final class ReceiptScanTests: SpliitUITestCase {

    @MainActor
    func testAReceiptFillsInTheExpense() async throws {
        let group = try await api.createGroup(name: "Lunch club", participants: ["Ana", "Bruno"])
        let app = launchApp(
            recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Lunch club")]),
            receiptSample: true
        )

        app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)].tap()
        app.buttons[AccessibilityID.ExpenseList.emptyAddButton].tap()

        let scan = app.buttons[AccessibilityID.ExpenseForm.scanButton]
        assertExists(scan, "A new expense should offer to read the receipt.")
        scan.tap()

        // Recognition takes a moment, and the fields are what says it finished.
        let title = app.textFields[AccessibilityID.ExpenseForm.titleField]
        XCTAssertTrue(
            waitForValue(SampleReceipt.merchant, in: title),
            "The shop’s name should become the title of the expense, not the address under it."
        )

        // 15.95, and not the 14.50 subtotal, the 1.45 of tax or the 8.60 sandwich.
        XCTAssertEqual(
            app.textFields[AccessibilityID.ExpenseForm.amountField].value as? String,
            SampleReceipt.total,
            "The total on the receipt should be the amount of the expense."
        )
        capture(app, "expense-receipt")

        app.buttons[AccessibilityID.ExpenseForm.saveButton].tap()
        assertExists(app.staticTexts[SampleReceipt.merchant], "The expense should save.")

        let expense = try await api.expense(inGroup: group.id, titled: SampleReceipt.merchant)
        XCTAssertEqual(expense["amount"] as? Int, 1595)
        XCTAssertEqual(
            (expense["expenseDate"] as? String)?.prefix(10).description,
            SampleReceipt.dayText,
            "The expense should be dated the day printed on the receipt, not the day it was read."
        )
        // Asserted on the server rather than on the picker: the category row is below the fold
        // on a small phone, and what it was saved as is the thing that matters anyway.
        XCTAssertEqual(
            (expense["category"] as? [String: Any])?["name"] as? String,
            SampleReceipt.category,
            "A café should be categorised as dining out."
        )
    }

    /// Nothing here is authoritative: it lands in a form, and the form is the point of scanning
    /// into it rather than into a preview that has to be accepted first.
    @MainActor
    func testWhatTheReceiptFilledInCanBeChanged() async throws {
        let group = try await api.createGroup(name: "Lunch club", participants: ["Ana", "Bruno"])
        let app = launchApp(
            recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Lunch club")]),
            receiptSample: true
        )

        app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)].tap()
        app.buttons[AccessibilityID.ExpenseList.emptyAddButton].tap()
        app.buttons[AccessibilityID.ExpenseForm.scanButton].tap()

        let title = app.textFields[AccessibilityID.ExpenseForm.titleField]
        XCTAssertTrue(waitForValue(SampleReceipt.merchant, in: title))

        replaceText(in: title, with: "Team lunch")
        replaceText(in: app.textFields[AccessibilityID.ExpenseForm.amountField], with: "20.00")
        app.buttons[AccessibilityID.ExpenseForm.saveButton].tap()

        assertExists(app.staticTexts["Team lunch"], "The corrected expense should save.")
        let expense = try await api.expense(inGroup: group.id, titled: "Team lunch")
        XCTAssertEqual(expense["amount"] as? Int, 2000)
    }

    /// A second scan has to work as well as the first. This is as close as a simulator can get to
    /// the bug that shipped: photographing a receipt and then reopening the camera closed it
    /// immediately, because the row swapped itself for a progress indicator mid-dismissal and
    /// stranded a dismissal on the next presentation. The camera cannot be reached here, but the
    /// phases it churned through can.
    @MainActor
    func testScanningTwiceLeavesTheRowWorking() async throws {
        let group = try await api.createGroup(name: "Lunch club", participants: ["Ana", "Bruno"])
        let app = launchApp(
            recentGroups: SpliitTestAPI.recentGroupsJSON([(group.id, "Lunch club")]),
            receiptSample: true
        )

        app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)].tap()
        app.buttons[AccessibilityID.ExpenseList.emptyAddButton].tap()

        let scan = app.buttons[AccessibilityID.ExpenseForm.scanButton]
        let title = app.textFields[AccessibilityID.ExpenseForm.titleField]

        scan.tap()
        XCTAssertTrue(waitForValue(SampleReceipt.merchant, in: title))

        // Typed over, so the second scan has something to put back and the assertion cannot pass
        // on the first scan's leftovers.
        replaceText(in: title, with: "Something else")
        assertExists(scan, "The row should still offer a scan once the first one has finished.")
        scan.tap()

        XCTAssertTrue(
            waitForValue(SampleReceipt.merchant, in: title),
            "A second scan should fill the form in exactly as the first did."
        )
    }

    /// Text recognition runs for a second or two, and the field filling in is what says it is
    /// done — there is nothing else to wait on.
    @MainActor
    private func waitForValue(
        _ expected: String, in element: XCUIElement, timeout: TimeInterval = 30
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.value as? String == expected { return true }
            _ = element.waitForExistence(timeout: 0.5)
        }
        XCTFail("\(element) never held “\(expected)”; it holds “\(element.value ?? "")”")
        return false
    }
}
