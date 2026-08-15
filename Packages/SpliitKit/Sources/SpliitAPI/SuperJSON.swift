import Foundation

/// Encoding and decoding for the superjson envelope the Spliit API wraps every payload in.
///
/// superjson sends `{"json": <value>, "meta": {"values": …}}`, where `meta.values` maps
/// dot-separated key paths to annotations for values plain JSON cannot express — `Date`,
/// `undefined`, `Decimal`.
///
/// Decoding deliberately ignores `meta.values`. Our models are statically typed, so a field
/// the server annotated as a `Date` is already declared `Date` here and parses straight from
/// its ISO-8601 string. Encoding *does* emit annotations, so the server rebuilds real `Date`
/// instances before its own validation runs.
public enum SuperJSON {

    // MARK: - Dates

    static let iso8601WithMilliseconds = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    static let iso8601 = Date.ISO8601FormatStyle(includingFractionalSeconds: false)

    /// The API mixes timestamps with and without milliseconds — `expenseDate` is a bare
    /// Postgres `date`, while `createdAt` is a full timestamp — so accept both.
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = try? iso8601WithMilliseconds.parse(text) { return date }
            if let date = try? iso8601.parse(text) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an ISO-8601 timestamp, found “\(text)”."
            )
        }
        return decoder
    }

    // MARK: - Encoding

    /// Wraps `value` in a superjson envelope, annotating every `Date` it contains.
    ///
    /// `JSONEncoder` gives no way to learn which strings came from dates, so dates are written
    /// with a per-call random prefix and the prefix is stripped on a second pass, recording the
    /// key path of each one. The prefix carries a UUID, so no real payload string can collide.
    public static func envelope(encoding value: some Encodable) throws -> Data {
        let marker = "\u{1}superjson-date:\(UUID().uuidString):"

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(marker + iso8601WithMilliseconds.format(date))
        }

        let payload = try encoder.encode(value)
        let json = try JSONSerialization.jsonObject(with: payload, options: [.fragmentsAllowed])

        var datePaths: [String] = []
        let cleaned = stripMarkers(from: json, marker: marker, at: [], collecting: &datePaths)

        var envelope: [String: Any] = ["json": cleaned]
        if datePaths == [""] {
            // A bare root value is annotated with the type array directly.
            envelope["meta"] = ["values": ["Date"]]
        } else if !datePaths.isEmpty {
            let values = datePaths.map { ($0, ["Date"]) }
            envelope["meta"] = ["values": Dictionary(uniqueKeysWithValues: values)]
        }

        return try JSONSerialization.data(
            withJSONObject: envelope,
            options: [.sortedKeys, .fragmentsAllowed]
        )
    }

    // MARK: - Response envelopes

    /// Unwraps `{"result":{"data":{"json": …}}}` into the payload type.
    public static func decode<Payload: Decodable>(
        _ type: Payload.Type,
        fromResponse data: Data
    ) throws -> Payload {
        try makeDecoder().decode(SuccessEnvelope<Payload>.self, from: data).result.data.json
    }

    /// Reads `{"error":{"json": …}}`, or nil if the body isn't a tRPC error.
    public static func decodeError(fromResponse data: Data) -> TRPCServerError? {
        guard let envelope = try? makeDecoder().decode(FailureEnvelope.self, from: data) else {
            return nil
        }
        return TRPCServerError(
            code: envelope.error.json.data?.code,
            message: envelope.error.json.message,
            httpStatus: envelope.error.json.data?.httpStatus,
            path: envelope.error.json.data?.path
        )
    }

    struct SuccessEnvelope<Payload: Decodable>: Decodable {
        let result: Result

        struct Result: Decodable {
            let data: Wrapped
        }

        struct Wrapped: Decodable {
            let json: Payload

            private enum CodingKeys: String, CodingKey { case json }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                if let value = try container.decodeIfPresent(Payload.self, forKey: .json) {
                    json = value
                } else if let void = TRPCVoid() as? Payload {
                    // Procedures returning `undefined` send `{"json": null}`.
                    json = void
                } else {
                    throw DecodingError.valueNotFound(
                        Payload.self,
                        DecodingError.Context(
                            codingPath: container.codingPath + [CodingKeys.json],
                            debugDescription: "The procedure returned no value."
                        )
                    )
                }
            }
        }
    }

    struct FailureEnvelope: Decodable {
        let error: Wrapped

        struct Wrapped: Decodable {
            let json: Payload
        }

        struct Payload: Decodable {
            let message: String
            let data: Details?
        }

        struct Details: Decodable {
            let code: String?
            let httpStatus: Int?
            let path: String?
        }
    }

    private static func stripMarkers(
        from value: Any,
        marker: String,
        at path: [String],
        collecting paths: inout [String]
    ) -> Any {
        switch value {
        case let text as String where text.hasPrefix(marker):
            paths.append(path.joined(separator: "."))
            return String(text.dropFirst(marker.count))

        case let object as [String: Any]:
            var result: [String: Any] = [:]
            result.reserveCapacity(object.count)
            for (key, nested) in object {
                result[key] = stripMarkers(
                    from: nested, marker: marker, at: path + [key], collecting: &paths
                )
            }
            return result

        case let array as [Any]:
            return array.enumerated().map { index, nested in
                stripMarkers(
                    from: nested, marker: marker, at: path + [String(index)], collecting: &paths
                )
            }

        default:
            return value
        }
    }
}
