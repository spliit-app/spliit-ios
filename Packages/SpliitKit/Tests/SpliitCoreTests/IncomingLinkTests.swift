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
            knownOrigins: IncomingLink.knownOrigins(instances: [official])
        )
        #expect(link == .group(id: "abc123", instanceURL: official))
    }

    /// An instance the list already has groups on is a link source too — that is the whole point
    /// of self-hosting.
    @Test("A link to a known instance opens the group")
    func selfHostedLink() {
        let link = IncomingLink.parse(
            URL(string: "https://spliit.example.com/groups/xyz")!,
            knownOrigins: IncomingLink.knownOrigins(instances: [selfHosted])
        )
        #expect(link == .group(id: "xyz", instanceURL: selfHosted))
    }

    /// The official site stays trusted even for somebody whose groups are all self-hosted, so a
    /// link a friend sends from spliit.app still opens.
    @Test("The official site is trusted even with no groups on it")
    func officialStaysTrusted() {
        let link = IncomingLink.parse(
            URL(string: "https://spliit.app/groups/abc123")!,
            knownOrigins: IncomingLink.knownOrigins(instances: [selfHosted])
        )
        #expect(link == .group(id: "abc123", instanceURL: official))
    }

    @Test("Somebody else's website is left to Safari")
    func unknownHost() {
        let link = IncomingLink.parse(
            URL(string: "https://spliit.app.evil.example/groups/abc123")!,
            knownOrigins: IncomingLink.knownOrigins(instances: [official])
        )
        #expect(link == nil)
    }

    /// Declared in `Info.plist` since the first commit, carried over from the React Native app,
    /// and consumed by nobody until now.
    @Test("The custom scheme the old app registered still opens a group, naming no instance")
    func customScheme() {
        let link = IncomingLink.parse(
            URL(string: "app.spliit.spliitmobile://groups/abc123")!,
            knownOrigins: IncomingLink.knownOrigins(instances: [official])
        )
        #expect(link == .group(id: "abc123", instanceURL: nil))
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
                    knownOrigins: IncomingLink.knownOrigins(instances: [official])
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
            knownOrigins: IncomingLink.knownOrigins(instances: [official])
        )
        #expect(link == nil)
    }

    /// A self-hosted instance on a home network, or the end-to-end harness on localhost. The app
    /// is configured to talk to it over plain http, so refusing http outright would refuse the
    /// links of everyone self-hosting without a certificate.
    @Test("An http instance the list already uses is followed over http")
    func insecureSelfHostedInstance() {
        let local = URL(string: "http://localhost:3009/")!
        let link = IncomingLink.parse(
            URL(string: "http://localhost:3009/groups/abc123")!,
            knownOrigins: IncomingLink.knownOrigins(instances: [local])
        )
        #expect(link == .group(id: "abc123", instanceURL: local))
    }

    /// The port is part of the origin: two instances on one host are two instances.
    @Test("A different port on the same host is a different instance")
    func portMatters() {
        let link = IncomingLink.parse(
            URL(string: "http://localhost:9999/groups/abc123")!,
            knownOrigins: IncomingLink.knownOrigins(instances: [URL(string: "http://localhost:3009/")!])
        )
        #expect(link == nil)
    }

    @Test("Origin matching ignores case")
    func hostCasing() {
        let link = IncomingLink.parse(
            URL(string: "https://Spliit.App/groups/abc123")!,
            knownOrigins: IncomingLink.knownOrigins(instances: [official])
        )
        #expect(link == .group(id: "abc123", instanceURL: official))
    }

    /// Two instances at once is the point: a link is opened against the server it names, whether
    /// or not that is where the last group came from.
    @Test("Each known instance keeps its own links")
    func severalInstances() {
        let origins = IncomingLink.knownOrigins(instances: [official, selfHosted])

        #expect(
            IncomingLink.parse(URL(string: "https://spliit.app/groups/one")!, knownOrigins: origins)
                == .group(id: "one", instanceURL: official)
        )
        #expect(
            IncomingLink.parse(
                URL(string: "https://spliit.example.com/groups/two")!, knownOrigins: origins
            ) == .group(id: "two", instanceURL: selfHosted)
        )
    }

    /// An instance served from a subdirectory keeps it: the group is under the whole prefix, and
    /// dropping it would point every request at the root of somebody's website.
    @Test("An instance in a subdirectory keeps its path")
    func subdirectoryInstance() {
        let hosted = URL(string: "https://home.example.com/spliit/")!
        let link = IncomingLink.parse(
            URL(string: "https://home.example.com/spliit/groups/abc123")!,
            knownOrigins: IncomingLink.knownOrigins(instances: [hosted])
        )
        #expect(link == .group(id: "abc123", instanceURL: hosted))
    }
}

@Suite("Pasted group links")
struct PastedLinkTests {

    /// Deliberately not origin-checked: a link somebody pastes is how a group on a server this
    /// device has never talked to gets into the list at all.
    @Test("A link to an instance the app has never seen is taken at its word")
    func unknownInstance() {
        #expect(
            IncomingLink.pasted("https://spliit.somebody.example/groups/abc123")
                == .group(
                    id: "abc123", instanceURL: URL(string: "https://spliit.somebody.example/")!
                )
        )
    }

    /// What people paste when they copy from the address bar of a group they already have open.
    @Test("A bare ID names no instance")
    func bareID() {
        #expect(IncomingLink.pasted("  abc123  ") == .group(id: "abc123", instanceURL: nil))
    }

    @Test("A link copied without its scheme still works")
    func schemeless() {
        #expect(
            IncomingLink.pasted("spliit.example.com/groups/abc123")
                == .group(id: "abc123", instanceURL: URL(string: "https://spliit.example.com/")!)
        )
    }

    @Test("An instance in a subdirectory keeps its path")
    func subdirectory() {
        #expect(
            IncomingLink.pasted("https://home.example.com/spliit/groups/abc123")
                == .group(
                    id: "abc123", instanceURL: URL(string: "https://home.example.com/spliit/")!
                )
        )
    }

    @Test("A plain http address on a home network is accepted")
    func insecure() {
        #expect(
            IncomingLink.pasted("http://localhost:3009/groups/abc123")
                == .group(id: "abc123", instanceURL: URL(string: "http://localhost:3009/")!)
        )
    }

    @Test("Anything that isn’t a group link is refused")
    func refused() {
        for text in ["", "   ", "https://spliit.app/", "https://spliit.app/about", "two words"] {
            #expect(IncomingLink.pasted(text) == nil, "\(text) should not resolve to a group")
        }
    }
}
