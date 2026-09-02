import Foundation
import Testing

@testable import SpliitAPI

@Suite("Building tRPC requests")
struct RequestBuildingTests {

    private func client(_ base: String) throws -> TRPCClient {
        TRPCClient(baseURL: try #require(URL(string: base)))
    }

    private func decodedInput(_ request: URLRequest) throws -> [String: Any] {
        let query = try #require(request.url?.query)
        let raw = try #require(String(query.dropFirst("input=".count)).removingPercentEncoding)
        let envelope = try #require(
            JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any]
        )
        return try #require(envelope["json"] as? [String: Any])
    }

    @Test("A query is a GET with the envelope in the input parameter")
    func buildsQuery() throws {
        let request = try client("https://spliit.app/")
            .makeRequest(for: Spliit.group(id: "abc123"))

        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/api/trpc/groups.get")
        #expect(try decodedInput(request)["groupId"] as? String == "abc123")
        #expect(request.httpBody == nil)
    }

    @Test("A base URL without a trailing slash still produces a valid path")
    func toleratesMissingTrailingSlash() throws {
        let request = try client("https://spliit.example.com")
            .makeRequest(for: Spliit.group(id: "abc"))

        #expect(request.url?.absoluteString.hasPrefix("https://spliit.example.com/api/trpc/groups.get") == true)
    }

    @Test("A self-hosted instance served from a subpath keeps that prefix")
    func preservesSubpath() throws {
        let request = try client("https://home.example.com/spliit/")
            .makeRequest(for: Spliit.group(id: "abc"))

        #expect(request.url?.path == "/spliit/api/trpc/groups.get")
    }

    /// The server's `participantId` is `z.string().optional()`, so leaving it out is how you
    /// ask for the group's total and nobody's share. Sending `null` instead is a 400.
    @Test("Stats for nobody in particular leave the participant out of the input")
    func omitsAbsentParticipant() throws {
        let request = try client("https://spliit.app/")
            .makeRequest(for: Spliit.stats(groupId: "abc123"))

        let input = try decodedInput(request)
        #expect(request.url?.path == "/api/trpc/groups.stats.get")
        #expect(input["groupId"] as? String == "abc123")
        #expect(input["participantId"] == nil)
    }

    @Test("Stats for a participant name them in the input")
    func sendsParticipantForStats() throws {
        let request = try client("https://spliit.app/")
            .makeRequest(for: Spliit.stats(groupId: "abc123", participantId: "ana"))

        #expect(try decodedInput(request)["participantId"] as? String == "ana")
    }

    /// The name the totals go by on an instance that has folded the stats page into one query.
    /// It takes the same input, and leaving the date range out is what asks for all of it.
    @Test("The stats overview takes the same input under its own name")
    func buildsStatsOverview() throws {
        let request = try client("https://spliit.app/")
            .makeRequest(for: Spliit.statsOverview(groupId: "abc123", participantId: "ana"))

        let input = try decodedInput(request)
        #expect(request.url?.path == "/api/trpc/groups.stats.overview")
        #expect(input["groupId"] as? String == "abc123")
        #expect(input["participantId"] as? String == "ana")
        #expect(input["from"] == nil)
        #expect(input["to"] == nil)
    }

    @Test("A procedure with no input sends no input parameter")
    func omitsEmptyInput() throws {
        let request = try client("https://spliit.app/").makeRequest(for: Spliit.categories())

        #expect(request.httpMethod == "GET")
        #expect(request.url?.query == nil)
    }

    @Test("A mutation is a POST carrying the envelope as JSON")
    func buildsMutation() throws {
        let values = GroupFormValues(
            name: "Flat 3B",
            currency: "$",
            participants: [.init(name: "Dana"), .init(name: "Eli")]
        )
        let request = try client("https://spliit.app/")
            .makeRequest(for: Spliit.createGroup(values))

        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/trpc/groups.create")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let body = try #require(request.httpBody)
        let envelope = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        let json = try #require(envelope["json"] as? [String: Any])
        let form = try #require(json["groupFormValues"] as? [String: Any])
        #expect(form["name"] as? String == "Flat 3B")
        #expect((form["participants"] as? [Any])?.count == 2)
    }

    /// The envelope is JSON, so it is full of characters — `{`, `"`, `,`, `+` — that
    /// `URLComponents` would happily leave unescaped in a query value and corrupt.
    @Test("Envelope characters are fully percent-encoded in the query")
    func percentEncodesTheEnvelope() throws {
        let request = try client("https://spliit.app/")
            .makeRequest(for: Spliit.expenses(groupId: "g1", filter: "a+b &c=d"))

        let query = try #require(request.url?.query)
        #expect(query.contains("{") == false)
        #expect(query.contains("\"") == false)
        #expect(query.contains("&") == false)
        #expect(query.contains("+") == false)

        #expect(try decodedInput(request)["filter"] as? String == "a+b &c=d")
    }

    @Test("An expense mutation sends minor units and an annotated date")
    func buildsExpenseMutation() throws {
        let values = ExpenseFormValues(
            title: "Airport taxi",
            expenseDate: Date(timeIntervalSince1970: 1_700_000_000),
            amount: 4250,
            paidBy: "p1",
            paidFor: [.init(participant: "p1", shares: 100)]
        )
        let request = try client("https://spliit.app/")
            .makeRequest(for: Spliit.createExpense(groupId: "g1", values))

        let body = try #require(request.httpBody)
        let envelope = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let json = try #require(envelope["json"] as? [String: Any])
        let form = try #require(json["expenseFormValues"] as? [String: Any])

        #expect(form["amount"] as? Int == 4250)
        #expect(form["expenseDate"] as? String == "2023-11-14T22:13:20.000Z")

        let meta = try #require(envelope["meta"] as? [String: Any])
        let values2 = try #require(meta["values"] as? [String: Any])
        #expect(values2["expenseFormValues.expenseDate"] as? [String] == ["Date"])
    }

    /// `originalCurrency` goes out even when there is nothing to convert. A nil optional would be
    /// left out of the request, reach tRPC as `undefined` and tell Prisma to leave the column
    /// alone — so an expense moved back to the group's own currency would go on claiming to have
    /// been paid in another one. The amount and the rate are omitted instead: the server's schema
    /// rejects null for those two, and the currency is what governs.
    @Test("A conversion is sent with the expense, and its currency cleared when there isn't one")
    func sendsTheConversion() throws {
        func formValues(in body: Data) throws -> [String: Any] {
            let envelope = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let json = try #require(envelope["json"] as? [String: Any])
            return try #require(json["expenseFormValues"] as? [String: Any])
        }

        let converted = ExpenseFormValues(
            title: "Airport taxi",
            expenseDate: Date(timeIntervalSince1970: 1_700_000_000),
            amount: 3696,
            paidBy: "p1",
            paidFor: [.init(participant: "p1", shares: 100)],
            originalAmount: 4000,
            originalCurrency: "USD",
            conversionRate: Decimal(string: "0.9241")
        )
        let body = try #require(
            try client("https://spliit.app/")
                .makeRequest(for: Spliit.createExpense(groupId: "g1", converted)).httpBody
        )
        let form = try formValues(in: body)

        #expect(form["originalAmount"] as? Int == 4000)
        #expect(form["originalCurrency"] as? String == "USD")
        // Asserted on the bytes: a rate that arrives as 0.9241000000000001 is a rate that no
        // longer produces the amount stored beside it.
        #expect(String(decoding: body, as: UTF8.self).contains("\"conversionRate\":0.9241"))

        let plain = ExpenseFormValues(
            title: "Coffee",
            expenseDate: Date(timeIntervalSince1970: 1_700_000_000),
            amount: 450,
            paidBy: "p1",
            paidFor: [.init(participant: "p1", shares: 100)]
        )
        let cleared = try formValues(
            in: try #require(
                try client("https://spliit.app/")
                    .makeRequest(for: Spliit.updateExpense(groupId: "g1", expenseId: "e1", plain))
                    .httpBody
            )
        )

        #expect(cleared["originalCurrency"] is NSNull)
        #expect(cleared["originalAmount"] == nil)
        #expect(cleared["conversionRate"] == nil)
    }

    @Test("A base URL with no host is rejected before any request goes out")
    func rejectsUnusableBaseURL() throws {
        let client = TRPCClient(baseURL: try #require(URL(string: "not-a-url")))

        #expect(throws: TRPCClientError.self) {
            try client.makeRequest(for: Spliit.group(id: "abc"))
        }
    }
}
