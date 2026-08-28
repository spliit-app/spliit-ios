import Foundation

/// Creates data straight through the tRPC API, so a test that is *about* the expense list
/// doesn't have to click its way through group creation to get one.
///
/// Deliberately hand-rolled rather than sharing `SpliitAPI`: if the client had a bug, a test
/// harness built on it would set up the wrong state and still agree with itself.
struct SpliitTestAPI {

    let baseURL: URL

    struct Group {
        let id: String
        /// Participant IDs by name.
        let participants: [String: String]
    }

    enum Failure: Error, CustomStringConvertible {
        case http(String)

        var description: String {
            switch self { case .http(let message): message }
        }
    }

    /// - Parameters:
    ///   - information: the group's free-text note, which the information tab shows.
    ///   - currency: the symbol the group's amounts are drawn with.
    ///   - currencyCode: the ISO code, which is what decides how many minor-unit digits the
    ///     amounts have. Dollars unless a test says otherwise, because two decimals is the case
    ///     most of them are written against.
    func createGroup(
        name: String,
        participants: [String],
        information: String? = nil,
        currency: String = "$",
        currencyCode: String = "USD"
    ) async throws -> Group {
        var values: [String: Any] = [
            "name": name,
            "currency": currency,
            "currencyCode": currencyCode,
            "participants": participants.map { ["name": $0] },
        ]
        // Omitted rather than sent as null: the field is optional on the server, and a group
        // created without one is the case most tests are about.
        if let information { values["information"] = information }

        let created = try await mutate("groups.create", ["groupFormValues": values])
        let id = try require(created["groupId"] as? String, "groups.create returned no id")

        let fetched = try await query("groups.get", ["groupId": id])
        let group = try require(fetched["group"] as? [String: Any], "groups.get returned no group")
        let people = try require(group["participants"] as? [[String: Any]], "no participants")

        var byName: [String: String] = [:]
        for person in people {
            if let name = person["name"] as? String, let id = person["id"] as? String {
                byName[name] = id
            }
        }
        return Group(id: id, participants: byName)
    }

    /// - Parameter daysAgo: how far back to date the expense, for date-bucket assertions.
    func createExpense(
        in group: Group,
        title: String,
        amount: Int,
        paidBy: String,
        paidFor: [String]? = nil,
        daysAgo: Int = 0,
        /// Server category ID. 0 is Uncategorized/General, which is what most tests want; pass one
        /// of the other 43 to exercise the category glyph on the expense row.
        category: Int = 0,
        isReimbursement: Bool = false,
        /// One of `EVENLY`, `BY_SHARES`, `BY_PERCENTAGE`, `BY_AMOUNT`.
        splitMode: String = "EVENLY",
        /// Per-participant share by name, for a split that isn't even. The units are the split
        /// mode's: a raw minor-unit amount for `BY_AMOUNT`, the share value ×100 for the rest.
        /// Whoever appears here is who the expense was paid for, so `paidFor` is not needed too.
        shares: [String: Int]? = nil,
        notes: String? = nil
    ) async throws {
        let payer = try require(group.participants[paidBy], "unknown participant \(paidBy)")
        let date = Calendar(identifier: .gregorian).date(
            byAdding: .day, value: -daysAgo, to: Date()
        ) ?? Date()

        let split: [[String: Any]]
        if let shares {
            split = try shares.map { name, value in
                let id = try require(group.participants[name], "unknown participant \(name)")
                return ["participant": id, "shares": value]
            }
        } else {
            split = (paidFor ?? Array(group.participants.keys))
                .compactMap { group.participants[$0] }
                .map { ["participant": $0, "shares": 100] }
        }

        var values: [String: Any] = [
            "title": title,
            "expenseDate": ISO8601DateFormatter().string(from: date),
            "amount": amount,
            "category": category,
            "paidBy": payer,
            "paidFor": split,
            "splitMode": splitMode,
            "saveDefaultSplittingOptions": false,
            "isReimbursement": isReimbursement,
            "documents": [],
            "recurrenceRule": "NONE",
        ]
        if let notes { values["notes"] = notes }

        _ = try await mutate(
            "groups.expenses.create",
            ["groupId": group.id, "expenseFormValues": values]
        )
    }

    /// The JSON the app would store for these groups, for `-uiTestRecentGroups`.
    static func recentGroupsJSON(_ groups: [(id: String, name: String)]) -> String {
        recentGroupsJSON(
            organised: groups.map {
                (id: $0.id, name: $0.name, isStarred: false, isArchived: false)
            }
        )
    }

    /// The same, for a list that has already been organised. Named rather than overloaded: the
    /// two tuple types differ only in their labels, and the compiler cannot tell them apart.
    ///
    /// - Parameter activeParticipants: who the user is, by group ID — a participant ID, or an
    ///   empty string for the "nobody" a group can also be answered with.
    static func recentGroupsJSON(
        organised groups: [(id: String, name: String, isStarred: Bool, isArchived: Bool)],
        activeParticipants: [String: String] = [:]
    ) -> String {
        let payload = groups.map { group in
            var entry: [String: Any] = [
                "groupId": group.id,
                "groupName": group.name,
                "isStarred": group.isStarred,
                "isArchived": group.isArchived,
            ]
            // Left out rather than sent empty when there is none: an absent key is a question
            // nobody has answered, and an empty string is an answer of "nobody".
            if let participant = activeParticipants[group.id] {
                entry["activeParticipant"] = participant
            }
            return entry
        }
        let data = try! JSONSerialization.data(withJSONObject: payload)
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Transport

    private func query(_ path: String, _ input: [String: Any]) async throws -> [String: Any] {
        let envelope = try JSONSerialization.data(withJSONObject: ["json": input])
        let encoded = String(decoding: envelope, as: UTF8.self)
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let url = URL(string: "\(baseURL)api/trpc/\(path)?input=\(encoded)")!
        return try await send(URLRequest(url: url), path: path)
    }

    private func mutate(_ path: String, _ input: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "\(baseURL)api/trpc/\(path)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["json": input])
        return try await send(request, path: path)
    }

    private func send(_ request: URLRequest, path: String) async throws -> [String: Any] {
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.http("\(path): response wasn’t JSON")
        }
        if let error = body["error"] as? [String: Any],
           let json = error["json"] as? [String: Any] {
            throw Failure.http("\(path): \(json["message"] as? String ?? "unknown error")")
        }
        let result = try require(body["result"] as? [String: Any], "\(path): no result")
        let wrapped = try require(result["data"] as? [String: Any], "\(path): no data")
        return wrapped["json"] as? [String: Any] ?? [:]
    }

    private func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw Failure.http(message) }
        return value
    }
}
