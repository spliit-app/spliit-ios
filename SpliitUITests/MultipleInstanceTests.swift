import XCTest

/// Groups from more than one Spliit instance, in one list.
///
/// One server stands in for two: `localhost:3009` and `127.0.0.1:3009` are the same thing to the
/// machine and two entirely different instances to the app, which is the whole of what is under
/// test — the address travels with the group rather than with the app, so a group on somebody's
/// own server and a group on spliit.app can be open on the same phone.
final class MultipleInstanceTests: SpliitUITestCase {

    /// The same server under its other name.
    private var otherBaseURL: String {
        baseURL.replacingOccurrences(of: "localhost", with: "127.0.0.1")
    }

    /// The link names the server, which is what lets somebody be handed a group on an instance
    /// this device has never talked to.
    @MainActor
    func testAGroupAddedByLinkKeepsTheServerTheLinkNames() async throws {
        let group = try await api.createGroup(
            name: "Hallway server", participants: ["Ana", "Bruno"]
        )
        let app = launchApp()

        app.buttons[AccessibilityID.GroupsList.addByURLButton].tap()
        replaceText(
            in: app.textFields[AccessibilityID.AddByURL.field],
            with: "\(otherBaseURL)groups/\(group.id)"
        )
        app.buttons[AccessibilityID.AddByURL.addButton].tap()

        assertExists(
            app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)],
            "A link to another instance should add the group."
        )

        app.staticTexts[AccessibilityID.GroupsList.rowTitle(group.id)].tap()
        assertExists(app.buttons["Information"], "The group should have an information tab.")
        app.buttons["Information"].tap()

        let server = app.staticTexts[AccessibilityID.GroupInformation.server]
        assertExists(server, "The information tab should say which server the group is on.")
        // `LabeledContent` reads its row as one element, so the label is "Server, <address>".
        XCTAssertTrue(
            server.label.contains("127.0.0.1:3009"),
            """
            The group should be on the instance its link named, not on the app's default. \
            The row read “\(server.label)”.
            """
        )
    }

    /// Both servers are asked, and each is only asked about its own groups: a participant count
    /// on a row is detail that can only have come from the instance that group is on.
    @MainActor
    func testGroupsFromTwoServersLoadSideBySide() async throws {
        let here = try await api.createGroup(name: "This server", participants: ["Ana", "Bruno"])
        let there = try await api.createGroup(
            name: "That server", participants: ["Ana", "Bruno", "Chloe"]
        )

        let app = launchApp(
            recentGroups: SpliitTestAPI.recentGroupsJSON(
                onInstances: [
                    (id: here.id, name: "This server", instanceURL: baseURL),
                    (id: there.id, name: "That server", instanceURL: otherBaseURL),
                ]
            )
        )

        let mine = app.staticTexts[AccessibilityID.GroupsList.rowParticipants(here.id)]
        let theirs = app.staticTexts[AccessibilityID.GroupsList.rowParticipants(there.id)]
        assertExists(mine, "The group on this server should fill in from it.")
        assertExists(theirs, "The group on the other server should fill in from that one.")
        XCTAssertEqual(mine.label, "2 participants")
        XCTAssertEqual(theirs.label, "3 participants")
        capture(app, "two-instances")
    }
}
