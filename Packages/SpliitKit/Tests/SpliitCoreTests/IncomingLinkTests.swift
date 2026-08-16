import Foundation
import Testing

@testable import SpliitCore

@Suite("Incoming links")
struct IncomingLinkTests {

    private let official = URL(string: "https://spliit.app/")!
    private let selfHosted = URL(string: "https://spliit.example.com/")!

    @Test("A shared link to the official site opens the group")
    func officialLink() {
        let link = IncomingLink.parse(
            URL(string: "https://spliit.app/groups/abc123")!,
            knownOrigins: IncomingLink.knownOrigins(baseURL: official)
        )
        #expect(link == .group(id: "abc123"))
    }

    /// The instance in settings is a link source too — that is the whole point of self-hosting.
    @Test("A link to the configured instance opens the group")
    func selfHostedLink() {
        let link = IncomingLink.parse(
            URL(string: "https://spliit.example.com/groups/xyz")!,
            knownOrigins: IncomingLink.knownOrigins(baseURL: selfHosted)
        )
        #expect(link == .group(id: "xyz"))
    }

    /// The official site stays trusted even while the app points somewhere else, so a link a
    /// friend sends from spliit.app still opens for someone running their own server.
    @Test("The official site is trusted even when pointed elsewhere")
    func officialStaysTrusted() {
        let link = IncomingLink.parse(
            URL(string: "https://spliit.app/groups/abc123")!,
            knownOrigins: IncomingLink.knownOrigins(baseURL: selfHosted)
        )
        #expect(link == .group(id: "abc123"))
    }

    @Test("Somebody else's website is left to Safari")
    func unknownHost() {
        let link = IncomingLink.parse(
            URL(string: "https://spliit.app.evil.example/groups/abc123")!,
            knownOrigins: IncomingLink.knownOrigins(baseURL: official)
        )
        #expect(link == nil)
    }

    /// Declared in `Info.plist` since the first commit, carried over from the React Native app,
    /// and consumed by nobody until now.
    @Test("The custom scheme the old app registered still opens a group")
    func customScheme() {
        let link = IncomingLink.parse(
            URL(string: "app.spliit.spliitmobile://groups/abc123")!,
            knownOrigins: IncomingLink.knownOrigins(baseURL: official)
        )
        #expect(link == .group(id: "abc123"))
    }

    @Test("A link with no group in it is not a group link")
    func notAGroupLink() {
        for text in [
            "https://spliit.app/",
            "https://spliit.app/about",
            "https://spliit.app/groups",
            "https://spliit.app/groups/",
        ] {
            #expect(
                IncomingLink.parse(
                    URL(string: text)!,
                    knownOrigins: IncomingLink.knownOrigins(baseURL: official)
                ) == nil,
                "\(text) should not resolve to a group"
            )
        }
    }

    /// http rather than https: the entitlement only covers https, and a plain-text link naming
    /// a trusted host is exactly what a downgrade attack looks like.
    @Test("An insecure link is not followed")
    func insecureLink() {
        let link = IncomingLink.parse(
            URL(string: "http://spliit.app/groups/abc123")!,
            knownOrigins: IncomingLink.knownOrigins(baseURL: official)
        )
        #expect(link == nil)
    }

    /// A self-hosted instance on a home network, or the end-to-end harness on localhost. The app
    /// is configured to talk to it over plain http, so refusing http outright would refuse the
    /// links of everyone self-hosting without a certificate.
    @Test("An http instance the app is pointed at is followed over http")
    func insecureSelfHostedInstance() {
        let local = URL(string: "http://localhost:3009/")!
        let link = IncomingLink.parse(
            URL(string: "http://localhost:3009/groups/abc123")!,
            knownOrigins: IncomingLink.knownOrigins(baseURL: local)
        )
        #expect(link == .group(id: "abc123"))
    }

    /// The port is part of the origin: two instances on one host are two instances.
    @Test("A different port on the same host is a different instance")
    func portMatters() {
        let link = IncomingLink.parse(
            URL(string: "http://localhost:9999/groups/abc123")!,
            knownOrigins: IncomingLink.knownOrigins(baseURL: URL(string: "http://localhost:3009/")!)
        )
        #expect(link == nil)
    }

    @Test("Origin matching ignores case")
    func hostCasing() {
        let link = IncomingLink.parse(
            URL(string: "https://Spliit.App/groups/abc123")!,
            knownOrigins: IncomingLink.knownOrigins(baseURL: official)
        )
        #expect(link == .group(id: "abc123"))
    }
}
