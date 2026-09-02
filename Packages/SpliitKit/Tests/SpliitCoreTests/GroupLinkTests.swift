import Foundation
import Testing

@testable import SpliitCore

/// The link somebody hands over on purpose. Which links the *system* may open is
/// `IncomingLinkTests`; this is the looser reading given to something typed out or scanned.
@Suite("Group links")
struct GroupLinkTests {

    @Test("A group URL names its group")
    func plainGroupURL() {
        #expect(GroupLink(url: "https://spliit.app/groups/abc123")?.groupID == "abc123")
    }

    /// What the web app's share dialog actually encodes into the QR code — a link into the
    /// expenses tab, with a query string saying where it came from. Neither belongs to the ID.
    @Test("The QR code the web app draws names its group")
    func sharedQRCodePayload() {
        #expect(
            GroupLink(url: "https://spliit.app/groups/abc123/expenses?ref=share")?.groupID
                == "abc123"
        )
    }

    /// The host is nobody's business here. A group is looked up on the instance the app is
    /// pointed at, and that lookup is what says whether it exists — refusing a self-hosted link
    /// on sight would only turn "no such group" into "no such link".
    @Test("A link to any instance names its group")
    func selfHostedURL() {
        #expect(GroupLink(url: "http://localhost:3009/groups/xyz")?.groupID == "xyz")
        #expect(GroupLink(url: "https://spliit.example.com/groups/xyz")?.groupID == "xyz")
    }

    @Test("A URL that names no group is not a group link")
    func urlWithoutAGroup() {
        #expect(GroupLink(url: "https://spliit.app")?.groupID == nil)
        #expect(GroupLink(url: "https://spliit.app/groups")?.groupID == nil)
        #expect(GroupLink(url: "https://spliit.app/groups/")?.groupID == nil)
        #expect(GroupLink(url: "https://example.com/")?.groupID == nil)
    }

    /// A QR code can carry anything at all, which is why the scanned reading is the strict one:
    /// a Wi-Fi sticker has no slashes and no spaces either, and would otherwise pass for an ID.
    @Test("Text that is not a URL is not a scanned group link")
    func scannedTextIsNotABareID() {
        #expect(GroupLink(url: "abc123")?.groupID == nil)
        #expect(GroupLink(url: "WIFI:S:Cafe;T:WPA;P:hunter2;;")?.groupID == nil)
        #expect(GroupLink(url: "")?.groupID == nil)
    }

    /// Pasting is the looser reading: people copy the ID out of the address bar as often as the
    /// whole link.
    @Test("A bare ID can be pasted")
    func pastedBareID() {
        #expect(GroupLink(pastedText: "abc123")?.groupID == "abc123")
        #expect(GroupLink(pastedText: "  abc123\n")?.groupID == "abc123")
    }

    @Test("A pasted link is read the same way a scanned one is")
    func pastedURL() {
        #expect(
            GroupLink(pastedText: "https://spliit.app/groups/abc123/expenses")?.groupID
                == "abc123"
        )
    }

    @Test("A pasted value with no ID in it names nothing")
    func pastedNonsense() {
        #expect(GroupLink(pastedText: "")?.groupID == nil)
        #expect(GroupLink(pastedText: "   ")?.groupID == nil)
        #expect(GroupLink(pastedText: "two words")?.groupID == nil)
        #expect(GroupLink(pastedText: "not/a/link")?.groupID == nil)
    }

    // MARK: - The server the link names

    /// The whole of how somebody is let into a group on an instance this device has never talked
    /// to: the link says which server, and the group is looked up there.
    @Test("A link names the instance its group is on")
    func namesItsInstance() {
        #expect(
            GroupLink(url: "https://spliit.app/groups/abc123")?.instanceURL
                == URL(string: "https://spliit.app/")
        )
        #expect(
            GroupLink(url: "https://spliit.example.com/groups/abc123/expenses?ref=share")?
                .instanceURL == URL(string: "https://spliit.example.com/")
        )
    }

    /// A home network without a certificate, or the end-to-end harness. The port is part of the
    /// address, so two instances on one host stay two instances.
    @Test("A plain http address keeps its scheme and its port")
    func insecureInstance() {
        #expect(
            GroupLink(url: "http://localhost:3009/groups/abc123")?.instanceURL
                == URL(string: "http://localhost:3009/")
        )
    }

    /// An instance served from a subdirectory keeps it: dropping the prefix would point every
    /// request at the root of somebody's website.
    @Test("An instance in a subdirectory keeps its path")
    func subdirectoryInstance() {
        #expect(
            GroupLink(url: "https://home.example.com/spliit/groups/abc123")?.instanceURL
                == URL(string: "https://home.example.com/spliit/")
        )
    }

    /// Lowercased, so a link typed with a capital letter doesn't become a second instance
    /// sitting beside the one it already is.
    @Test("The address is read case-insensitively")
    func hostCasing() {
        #expect(
            GroupLink(url: "https://Spliit.App/groups/abc123")?.instanceURL
                == URL(string: "https://spliit.app/")
        )
    }

    /// A link copied out of an address bar often loses its scheme on the way.
    @Test("A pasted link without its scheme still names its instance")
    func schemelessPaste() {
        let link = GroupLink(pastedText: "spliit.example.com/groups/abc123")
        #expect(link?.groupID == "abc123")
        #expect(link?.instanceURL == URL(string: "https://spliit.example.com/"))
    }

    /// A bare ID names no server at all, which is a different thing from naming the wrong one:
    /// the app falls back to where it creates groups.
    @Test("A bare ID names no instance")
    func bareIDNamesNoInstance() {
        #expect(GroupLink(pastedText: "abc123")?.instanceURL == nil)
    }
}
