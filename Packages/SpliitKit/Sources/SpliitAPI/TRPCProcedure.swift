import Foundation

/// One call to the Spliit API: where the procedure lives, whether it reads or writes, and
/// the input it takes.
public struct TRPCProcedure<Input: Encodable & Sendable, Output: Decodable & Sendable>: Sendable {

    public enum Kind: Sendable {
        /// Sent as `GET`, with the input in the query string.
        case query
        /// Sent as `POST`, with the input in the body.
        case mutation
    }

    public let path: String
    public let kind: Kind
    public let input: Input

    public init(path: String, kind: Kind, input: Input) {
        self.path = path
        self.kind = kind
        self.input = input
    }

    public static func query(_ path: String, _ input: Input) -> Self {
        Self(path: path, kind: .query, input: input)
    }

    public static func mutation(_ path: String, _ input: Input) -> Self {
        Self(path: path, kind: .mutation, input: input)
    }
}

/// Input for procedures that take none. The client omits the query string entirely rather
/// than sending an explicit null, which is what the server expects for these.
public struct NoInput: Encodable, Sendable {
    public init() {}

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encodeNil()
    }
}

/// Output for procedures that return nothing meaningful — `groups.update` returns
/// `undefined`, `expenses.delete` returns `{}`.
public struct TRPCVoid: Decodable, Sendable {
    public init() {}
    public init(from decoder: any Decoder) throws {}
}
