import XCTest

/// Adding a group from the QR code the web app's share dialog draws.
///
/// A simulator has no camera, so what these drive is everything on this side of one: the code is
/// handed over as if it had just been read, and the parsing, the lookup and the group landing in
/// the list are all real. Which payloads count is unit-tested in `GroupLinkTests`.
final class GroupQRCodeTests: SpliitUITestCase {

    /// The payload verbatim as the web app encodes it: a link into the expenses tab, with the
    /// query string its share dialog adds.
    @MainActor
    func testScanningAGroupsQRCodeAddsItToTheList() async throws {
        let group = try await api.createGroup(
            name: "Cabin weekend", participants: ["Ana", "Bruno"]
        )

        let app = launchApp(
            recentGroups: SpliitTestAPI.recentGroupsJSON([]),
            qrCode: "\(baseURL)groups/\(group.id)/expenses?ref=share"
        )

        app.buttons[AccessibilityID.GroupsList.scanQRCodeButton].tap()

        assertExists(
            app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)],
            "The scanned group should have been added to the list."
        )
        capture(app, "added-by-qr-code")
    }

    /// Anything at all can be printed on a QR code, and the answer to one that is not a group
    /// link is a sentence rather than a round trip to the server.
    @MainActor
    func testACodeThatIsNotAGroupLinkSaysSo() {
        let app = launchApp(
            recentGroups: SpliitTestAPI.recentGroupsJSON([]),
            qrCode: "WIFI:S:Cafe;T:WPA;P:hunter2;;"
        )

        app.buttons[AccessibilityID.GroupsList.scanQRCodeButton].tap()

        let status = app.staticTexts[AccessibilityID.ScanQRCode.status]
        assertExists(status, "The scanner should say what was wrong with the code.")
        XCTAssertEqual(status.label, "That QR code isn’t a Spliit group link.")
        capture(app, "qr-code-not-a-group-link")
    }

    /// A well-formed link to a group this instance has never heard of is answered with the
    /// camera still up, so the next code is one movement away rather than a screen away.
    @MainActor
    func testACodeForAGroupTheServerDoesNotHaveSaysSo() {
        let app = launchApp(
            recentGroups: SpliitTestAPI.recentGroupsJSON([]),
            qrCode: "\(baseURL)groups/not-a-real-group/expenses?ref=share"
        )

        app.buttons[AccessibilityID.GroupsList.scanQRCodeButton].tap()

        let status = app.staticTexts[AccessibilityID.ScanQRCode.status]
        assertExists(status, "The scanner should say the group is not on this server.")
        XCTAssertEqual(status.label, "No group with that link exists on this server.")

        // And the screen is still the scanner, rather than having been dismissed onto a list
        // that gained nothing.
        assertExists(
            app.buttons[AccessibilityID.ScanQRCode.cancelButton],
            "The scanner should stay up so another code can be held to it."
        )
    }
}
