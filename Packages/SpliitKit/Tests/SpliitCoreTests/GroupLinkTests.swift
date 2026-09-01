import Testing

@testable import SpliitCore

/// The link somebody hands over on purpose. Which links the *system* may open is
/// `IncomingLinkTests`; this is the looser reading given to something typed out or scanned.
@Suite("Group links")
struct GroupLinkTests {

    @Test("A group URL names its group")
    func plainGroupURL() {
        #expect(GroupLink.groupID(inURL: "https://spliit.app/groups/abc123") == "abc123")
    }

    /// What the web app's share dialog actually encodes into the QR code — a link into the
    /// expenses tab, with a query string saying where it came from. Neither belongs to the ID.
    @Test("The QR code the web app draws names its group")
    func sharedQRCodePayload() {
        #expect(
            GroupLink.groupID(inURL: "https://spliit.app/groups/abc123/expenses?ref=share")
                == "abc123"
        )
    }

    /// The host is nobody's business here. A group is looked up on the instance the app is
    /// pointed at, and that lookup is what says whether it exists — refusing a self-hosted link
    /// on sight would only turn "no such group" into "no such link".
    @Test("A link to any instance names its group")
    func selfHostedURL() {
        #expect(GroupLink.groupID(inURL: "http://localhost:3009/groups/xyz") == "xyz")
        #expect(GroupLink.groupID(inURL: "https://spliit.example.com/groups/xyz") == "xyz")
    }

    @Test("A URL that names no group is not a group link")
    func urlWithoutAGroup() {
        #expect(GroupLink.groupID(inURL: "https://spliit.app") == nil)
        #expect(GroupLink.groupID(inURL: "https://spliit.app/groups") == nil)
        #expect(GroupLink.groupID(inURL: "https://spliit.app/groups/") == nil)
        #expect(GroupLink.groupID(inURL: "https://example.com/") == nil)
    }

    /// A QR code can carry anything at all, which is why the scanned reading is the strict one:
    /// a Wi-Fi sticker has no slashes and no spaces either, and would otherwise pass for an ID.
    @Test("Text that is not a URL is not a scanned group link")
    func scannedTextIsNotABareID() {
        #expect(GroupLink.groupID(inURL: "abc123") == nil)
        #expect(GroupLink.groupID(inURL: "WIFI:S:Cafe;T:WPA;P:hunter2;;") == nil)
        #expect(GroupLink.groupID(inURL: "") == nil)
    }

    /// Pasting is the looser reading: people copy the ID out of the address bar as often as the
    /// whole link.
    @Test("A bare ID can be pasted")
    func pastedBareID() {
        #expect(GroupLink.groupID(inPastedText: "abc123") == "abc123")
        #expect(GroupLink.groupID(inPastedText: "  abc123\n") == "abc123")
    }

    @Test("A pasted link is read the same way a scanned one is")
    func pastedURL() {
        #expect(
            GroupLink.groupID(inPastedText: "https://spliit.app/groups/abc123/expenses")
                == "abc123"
        )
    }

    @Test("A pasted value with no ID in it names nothing")
    func pastedNonsense() {
        #expect(GroupLink.groupID(inPastedText: "") == nil)
        #expect(GroupLink.groupID(inPastedText: "   ") == nil)
        #expect(GroupLink.groupID(inPastedText: "two words") == nil)
        #expect(GroupLink.groupID(inPastedText: "not/a/link") == nil)
    }
}
