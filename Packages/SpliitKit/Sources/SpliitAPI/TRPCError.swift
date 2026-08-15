import Foundation

/// An error the Spliit server itself reported, as opposed to a transport failure.
public struct TRPCServerError: Error, Sendable, Equatable {
    /// tRPC's error code, e.g. `NOT_FOUND` or `BAD_REQUEST`.
    public let code: String?
    public let message: String
    public let httpStatus: Int?
    public let path: String?

    public init(code: String?, message: String, httpStatus: Int?, path: String?) {
        self.code = code
        self.message = message
        self.httpStatus = httpStatus
        self.path = path
    }

    /// True when the instance doesn't know this procedure — an older self-hosted deployment.
    /// Callers should degrade the affected screen rather than surface a failure.
    public var isUnknownProcedure: Bool {
        code == "NOT_FOUND" && message.localizedCaseInsensitiveContains("No procedure found")
    }
}

extension TRPCServerError: LocalizedError {
    public var errorDescription: String? { message }
}

/// A failure that happened before the server could answer, or while reading its answer.
public enum TRPCClientError: Error, Sendable, Equatable {
    /// The configured base URL can't be turned into a request URL.
    case invalidBaseURL(String)
    /// The request never completed.
    case network(String)
    /// A non-200 response that carried no tRPC error envelope.
    case unexpectedResponse(status: Int, body: String)
    /// The response arrived but didn't match the expected shape.
    case decoding(String)
}

extension TRPCClientError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL(let url):
            "“\(url)” isn’t a valid Spliit address."
        case .network(let reason):
            "Couldn’t reach the server. \(reason)"
        case .unexpectedResponse(let status, _):
            "The server answered with an unexpected status (\(status))."
        case .decoding:
            "The server’s response couldn’t be read. It may be running a different version."
        }
    }
}
