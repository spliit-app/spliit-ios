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

    @Test("A base URL with no host is rejected before any request goes out")
    func rejectsUnusableBaseURL() throws {
        let client = TRPCClient(baseURL: try #require(URL(string: "not-a-url")))

        #expect(throws: TRPCClientError.self) {
            try client.makeRequest(for: Spliit.group(id: "abc"))
        }
    }
}
