import Foundation
import Testing

@testable import SpliitAPI

@Suite("superjson envelopes")
struct SuperJSONTests {

    private func object(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("A payload without dates gets no meta block")
    func omitsMetaWhenThereAreNoDates() throws {
        struct Input: Encodable { let groupId: String }

        let envelope = try object(SuperJSON.envelope(encoding: Input(groupId: "abc")))

        #expect(envelope["meta"] == nil)
        let json = try #require(envelope["json"] as? [String: Any])
        #expect(json["groupId"] as? String == "abc")
    }

    @Test("A date becomes an ISO-8601 string annotated by key path")
    func annotatesDates() throws {
        struct Input: Encodable {
            let title: String
            let expenseDate: Date
        }
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        let envelope = try object(
            SuperJSON.envelope(encoding: Input(title: "Taxi", expenseDate: date))
        )

        let json = try #require(envelope["json"] as? [String: Any])
        #expect(json["expenseDate"] as? String == "2023-11-14T22:13:20.000Z")
        #expect(json["title"] as? String == "Taxi")

        let meta = try #require(envelope["meta"] as? [String: Any])
        let values = try #require(meta["values"] as? [String: Any])
        #expect(values["expenseDate"] as? [String] == ["Date"])
        #expect(values.count == 1)
    }

    /// superjson addresses nested values with dot-separated paths, using the index for array
    /// elements — `expenses.0.expenseDate`. Recorded server responses use exactly this form.
    @Test("Nested and array-indexed dates get the paths superjson expects")
    func annotatesNestedDatePaths() throws {
        struct Item: Encodable { let at: Date }
        struct Input: Encodable {
            let items: [Item]
            let nested: Nested
            struct Nested: Encodable { let when: Date }
        }

        let date = Date(timeIntervalSince1970: 0)
        let envelope = try object(
            SuperJSON.envelope(
                encoding: Input(
                    items: [Item(at: date), Item(at: date)],
                    nested: .init(when: date)
                )
            )
        )

        let meta = try #require(envelope["meta"] as? [String: Any])
        let values = try #require(meta["values"] as? [String: Any])

        #expect(Set(values.keys) == ["items.0.at", "items.1.at", "nested.when"])
    }

    @Test("A string that looks like the internal date marker is left alone")
    func doesNotMistakePayloadStringsForDates() throws {
        struct Input: Encodable { let title: String }
        // The marker carries a per-call UUID, so no payload can collide with it — but a value
        // shaped like one shouldn't be touched either.
        let suspicious = "\u{1}superjson-date:00000000-0000-0000-0000-000000000000:nope"

        let envelope = try object(SuperJSON.envelope(encoding: Input(title: suspicious)))

        #expect(envelope["meta"] == nil)
        let json = try #require(envelope["json"] as? [String: Any])
        #expect(json["title"] as? String == suspicious)
    }

    @Test("Nil optionals are omitted rather than sent as null")
    func omitsNilOptionals() throws {
        struct Input: Encodable {
            let name: String
            let notes: String?
        }

        let envelope = try object(SuperJSON.envelope(encoding: Input(name: "Flat", notes: nil)))
        let json = try #require(envelope["json"] as? [String: Any])

        // The server's zod schemas mark these `.optional()`, which accepts an absent key but
        // not every one of them accepts an explicit null.
        #expect(json.keys.contains("notes") == false)
        #expect(json["name"] as? String == "Flat")
    }

    @Test("Timestamps decode with or without milliseconds")
    func decodesBothTimestampPrecisions() throws {
        struct Payload: Decodable { let at: Date }

        let withMilliseconds = Data(
            #"{"result":{"data":{"json":{"at":"2026-08-15T16:24:15.600Z"}}}}"#.utf8
        )
        let withoutMilliseconds = Data(
            #"{"result":{"data":{"json":{"at":"2026-08-15T16:24:15Z"}}}}"#.utf8
        )

        let a = try SuperJSON.decode(Payload.self, fromResponse: withMilliseconds)
        let b = try SuperJSON.decode(Payload.self, fromResponse: withoutMilliseconds)

        #expect(abs(a.at.timeIntervalSince(b.at) - 0.6) < 0.001)
    }

    @Test("An unparseable timestamp fails loudly rather than defaulting")
    func rejectsNonISOTimestamps() {
        struct Payload: Decodable { let at: Date }
        let body = Data(#"{"result":{"data":{"json":{"at":"last Tuesday"}}}}"#.utf8)

        #expect(throws: (any Error).self) {
            try SuperJSON.decode(Payload.self, fromResponse: body)
        }
    }

    @Test("A decimal arrives as a string and keeps its precision")
    func decodesLenientDecimal() throws {
        struct Payload: Decodable { let rate: LenientDecimal }

        let asString = Data(#"{"result":{"data":{"json":{"rate":"1.0925"}}}}"#.utf8)
        let asNumber = Data(#"{"result":{"data":{"json":{"rate":1.5}}}}"#.utf8)

        #expect(try SuperJSON.decode(Payload.self, fromResponse: asString).rate.value == Decimal(string: "1.0925"))
        #expect(try SuperJSON.decode(Payload.self, fromResponse: asNumber).rate.value == Decimal(string: "1.5"))
    }
}
