import Foundation
import Testing

@testable import SpliitAPI

/// Answers each procedure differently, and remembers what was asked. A call that asks a second
/// procedure when the first turns out not to exist cannot be tested by a stub with one answer
/// for every request — which is the whole point of the totals.
///
/// Its own storage and its own host, so it never contends with ``StubURLProtocol``'s: suites run
/// in parallel, and two of them writing one static would be a race rather than a test.
final class StatsStubURLProtocol: StubURLProtocol, @unchecked Sendable {

    /// Outcomes by the tRPC procedure the path ends in. Anything unlisted is answered the way a
    /// router answers a name it has never heard of.
    nonisolated(unsafe) static var byProcedure: [String: Outcome] = [:]
    /// Every procedure asked for, in the order it was asked. Which one comes first is behaviour.
    nonisolated(unsafe) static var asked: [String] = []

    static func reset() {
        byProcedure = [:]
        asked = []
    }

    override class func outcome(for request: URLRequest) -> Outcome {
        let path = request.url?.path ?? ""
        let procedure = String(path.split(separator: "/").last ?? "")
        asked.append(procedure)
        return byProcedure[procedure] ?? .response(status: 404, body: unknownProcedure(procedure))
    }

    /// Verbatim what a tRPC router answers for a procedure it does not have. `spliit.app` says
    /// exactly this about `groups.stats.get` today, which is what sent the totals tab into its
    /// "no totals on this server" state for everybody on it.
    static func unknownProcedure(_ procedure: String) -> String {
        """
        {"error":{"json":{"message":"No procedure found on path \\"\(procedure)\\"",\
        "code":-32004,"data":{"code":"NOT_FOUND","httpStatus":404,"path":"\(procedure)"}}}}
        """
    }
}

/// Which of the two names the totals go by, and what happens when an instance has the other one.
///
/// Serialized because the stub's record of what was asked is shared across the suite.
@Suite("Asking for the totals", .serialized)
struct StatsProcedureTests {

    private func client() -> TRPCClient {
        TRPCClient(
            baseURL: URL(string: "https://stats.example.com/")!,
            session: StatsStubURLProtocol.session()
        )
    }

    private func body(_ fixture: String) throws -> String {
        String(decoding: try Fixture.data(fixture), as: UTF8.self)
    }

    /// The order matters rather than merely working: the instance most people are on is the one
    /// that has dropped `groups.stats.get`, so asking for it first would spend a 404 on every
    /// load of the tab to reach the answer.
    @Test("An instance with the overview is asked for it, and asked nothing else")
    func prefersTheOverview() async throws {
        StatsStubURLProtocol.reset()
        StatsStubURLProtocol.byProcedure = [
            "groups.stats.overview": .response(status: 200, body: try body("groups-stats-overview"))
        ]

        let response = try await client().groupStats(groupId: "lisbon", participantId: "ana")

        #expect(StatsStubURLProtocol.asked == ["groups.stats.overview"])
        #expect(response.totalGroupSpendings == 63680)
        #expect(response.totalParticipantShare == 17627)
    }

    /// Every published image is still one of these, so this is the path a self-hosted instance
    /// takes today — and the one `make test-live` exercises, because the server it runs against
    /// is that image.
    @Test("An instance that predates the overview is asked the old name instead")
    func fallsBackToTheOldProcedure() async throws {
        StatsStubURLProtocol.reset()
        StatsStubURLProtocol.byProcedure = [
            "groups.stats.get": .response(status: 200, body: try body("groups-stats-get"))
        ]

        let response = try await client().groupStats(groupId: "lisbon", participantId: "ana")

        #expect(StatsStubURLProtocol.asked == ["groups.stats.overview", "groups.stats.get"])
        #expect(response.totalGroupSpendings == 63680)
        #expect(response.totalParticipantShare == 17627)
    }

    /// Only an instance with neither has no totals, and the tab tells that from an outage by the
    /// error it is handed. Reporting the *overview's* `NOT_FOUND` before trying the old name is
    /// what the shipped bug did.
    @Test("An instance with neither reports an unknown procedure, and nothing else")
    func reportsAnUnknownProcedureOnlyWhenBothAreMissing() async throws {
        StatsStubURLProtocol.reset()

        do {
            _ = try await client().groupStats(groupId: "lisbon")
            Issue.record("Expected the call to fail.")
        } catch let error as TRPCServerError {
            #expect(error.isUnknownProcedure)
            #expect(error.path == "groups.stats.get")
        }

        #expect(StatsStubURLProtocol.asked == ["groups.stats.overview", "groups.stats.get"])
    }

    /// An instance that has the overview and answers it badly is a server having a bad day, not
    /// a server without totals — so it must not fall through to the old name and come back
    /// saying the feature is missing.
    @Test("A failure that isn’t a missing procedure is not retried under the other name")
    func doesNotFallBackOnAnOrdinaryFailure() async throws {
        StatsStubURLProtocol.reset()
        StatsStubURLProtocol.byProcedure = [
            "groups.stats.overview": .response(status: 500, body: "<html>Bad Gateway</html>")
        ]

        await #expect(throws: TRPCClientError.self) {
            _ = try await client().groupStats(groupId: "lisbon")
        }

        #expect(StatsStubURLProtocol.asked == ["groups.stats.overview"])
    }
}
