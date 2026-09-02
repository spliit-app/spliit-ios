import Foundation
import Testing

@testable import SpliitAPI

/// Stands in for the network so failure paths can be exercised deterministically. Without
/// this, the only way a transport failure ever got tested was by unplugging something.
///
/// Subclass it to answer one request differently from the next — a call that asks a second
/// procedure when the first turns out not to exist cannot be told apart by a stub with one
/// answer for everything. Each subclass brings its own storage, because suites run in parallel
/// and two of them writing one static would be a race rather than a test.
class StubURLProtocol: URLProtocol, @unchecked Sendable {

    /// What the next request should do. Set before building a session.
    nonisolated(unsafe) static var outcome: Outcome = .failure(URLError(.timedOut))

    enum Outcome {
        case failure(URLError)
        case response(status: Int, body: String)
    }

    /// Which outcome answers this particular request.
    class func outcome(for request: URLRequest) -> Outcome { Self.outcome }

    class func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        switch Self.outcome(for: request) {
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        case .response(let status, let body):
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
}

@Suite("Transport failures", .serialized)
struct TransportFailureTests {

    private func client() -> TRPCClient {
        TRPCClient(baseURL: URL(string: "https://spliit.example.com/")!, session: StubURLProtocol.session())
    }

    /// The case that left a spinner on screen indefinitely: a request the server never answers.
    @Test("A timed-out request surfaces as a network failure, not a hang")
    func reportsTimeout() async {
        StubURLProtocol.outcome = .failure(URLError(.timedOut))

        await #expect(throws: TRPCClientError.self) {
            _ = try await client().call(Spliit.group(id: "abc"))
        }
    }

    /// Search cancels the request in flight on every keystroke. Reporting that as a network
    /// failure told people their server was unreachable when all they had done was type another
    /// character — "Couldn't search" flashing between letters, on a server that was answering
    /// perfectly well.
    @Test("A cancelled request is cancelled, not a network failure")
    func cancellationIsNotAFailure() async {
        StubURLProtocol.outcome = .failure(URLError(.cancelled))

        await #expect(throws: CancellationError.self) {
            _ = try await client().call(Spliit.group(id: "abc"))
        }
    }

    @Test("An unreachable server surfaces as a network failure")
    func reportsUnreachableHost() async throws {
        StubURLProtocol.outcome = .failure(URLError(.cannotConnectToHost))

        do {
            _ = try await client().call(Spliit.categories())
            Issue.record("Expected the call to fail.")
        } catch let error as TRPCClientError {
            guard case .network = error else {
                Issue.record("Expected a network failure, got \(error).")
                return
            }
            #expect(error.errorDescription?.isEmpty == false)
        }
    }

    @Test("A server error carrying a tRPC envelope becomes a typed server error")
    func reportsServerError() async throws {
        StubURLProtocol.outcome = .response(
            status: 404,
            body: #"{"error":{"json":{"message":"Group not found.","code":-32004,"data":{"code":"NOT_FOUND","httpStatus":404,"path":"groups.getDetails"}}}}"#
        )

        do {
            _ = try await client().call(Spliit.groupDetails(id: "abc"))
            Issue.record("Expected the call to fail.")
        } catch let error as TRPCServerError {
            #expect(error.code == "NOT_FOUND")
            #expect(error.httpStatus == 404)
        }
    }

    /// A self-hosted instance behind a login page answers with HTML, not JSON. That should read
    /// as an unexpected response rather than a decoding bug.
    @Test("A non-tRPC error response is reported with its status")
    func reportsUnexpectedResponse() async throws {
        StubURLProtocol.outcome = .response(status: 502, body: "<html>Bad Gateway</html>")

        do {
            _ = try await client().call(Spliit.group(id: "abc"))
            Issue.record("Expected the call to fail.")
        } catch let error as TRPCClientError {
            guard case .unexpectedResponse(let status, _) = error else {
                Issue.record("Expected an unexpected-response failure, got \(error).")
                return
            }
            #expect(status == 502)
        }
    }

    @Test("A 200 that isn’t the expected shape is reported as a decoding failure")
    func reportsDecodingFailure() async throws {
        StubURLProtocol.outcome = .response(status: 200, body: #"{"result":{"data":{"json":{}}}}"#)

        do {
            _ = try await client().call(Spliit.expenses(groupId: "g1"))
            Issue.record("Expected the call to fail.")
        } catch let error as TRPCClientError {
            guard case .decoding = error else {
                Issue.record("Expected a decoding failure, got \(error).")
                return
            }
        }
    }
}
