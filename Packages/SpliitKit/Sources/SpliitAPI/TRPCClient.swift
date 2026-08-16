import Foundation

/// Talks to a Spliit instance's tRPC endpoint.
///
/// Requests are sent unbatched: queries as `GET …/api/trpc/<path>?input=<envelope>`, mutations
/// as `POST` with the envelope as the body. The server accepts both, so there's no need to
/// implement tRPC's batching protocol.
public struct TRPCClient: Sendable {

    public let baseURL: URL
    private let session: URLSession

    /// - Parameters:
    ///   - baseURL: the instance root, with or without a trailing slash — the settings screen
    ///     stores it as `https://spliit.app/`.
    ///   - session: defaults to a session shared by every client, so switching instances does
    ///     not leak a connection pool per call.
    public init(baseURL: URL, session: URLSession? = nil) {
        self.baseURL = baseURL
        self.session = session ?? Self.sharedSession
    }

    /// `URLSession.shared` waits 60 seconds before giving up, which a person reads as the app
    /// having hung. Failing sooner lets the screen offer a retry while the attempt is still
    /// something they remember making.
    ///
    /// Ephemeral because responses to an API are not worth caching, and a cached `GET` would
    /// quietly serve stale balances.
    private static let sharedSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    public func call<Input, Output>(
        _ procedure: TRPCProcedure<Input, Output>
    ) async throws -> Output {
        let request = try makeRequest(for: procedure)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // A cancelled request is not a failed one, and calling it a network error made the
            // app tell people their server was unreachable when all they had done was type
            // another character. `URLSession` reports cancellation as `URLError.cancelled`;
            // rethrowing it as `CancellationError` says the same thing in the language callers
            // already check.
            if error is CancellationError { throw error }
            if (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw TRPCClientError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw TRPCClientError.network("The response wasn’t an HTTP response.")
        }

        if (200..<300).contains(http.statusCode) {
            do {
                return try SuperJSON.decode(Output.self, fromResponse: data)
            } catch {
                throw TRPCClientError.decoding(String(describing: error))
            }
        }

        if let failure = SuperJSON.decodeError(fromResponse: data) {
            throw TRPCServerError(
                code: failure.code,
                message: failure.message,
                httpStatus: failure.httpStatus ?? http.statusCode,
                path: failure.path
            )
        }

        throw TRPCClientError.unexpectedResponse(
            status: http.statusCode,
            body: String(decoding: data.prefix(512), as: UTF8.self)
        )
    }

    // MARK: - Requests

    func makeRequest<Input, Output>(
        for procedure: TRPCProcedure<Input, Output>
    ) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              components.scheme != nil, components.host != nil
        else {
            throw TRPCClientError.invalidBaseURL(baseURL.absoluteString)
        }

        var path = components.path
        if !path.hasSuffix("/") { path += "/" }
        components.path = path + "api/trpc/" + procedure.path

        let takesInput = Input.self != NoInput.self

        switch procedure.kind {
        case .query:
            if takesInput {
                let envelope = try SuperJSON.envelope(encoding: procedure.input)
                let text = String(decoding: envelope, as: UTF8.self)
                components.percentEncodedQuery = "input=" + percentEncoded(text)
            }
            guard let url = components.url else {
                throw TRPCClientError.invalidBaseURL(baseURL.absoluteString)
            }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            return request

        case .mutation:
            guard let url = components.url else {
                throw TRPCClientError.invalidBaseURL(baseURL.absoluteString)
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = try SuperJSON.envelope(encoding: procedure.input)
            return request
        }
    }

    /// `URLComponents` leaves characters like `+` and `&` alone inside a query value, which
    /// would corrupt the JSON envelope, so escape everything outside the unreserved set.
    private func percentEncoded(_ text: String) -> String {
        let unreserved = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        )
        return text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? text
    }
}
