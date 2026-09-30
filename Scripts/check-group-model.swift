// Run from the repository root, using the same Swift toolchain for these commands:
// (cd Packages/SpliitKit && swift build --build-system native)
// core_build=$(cd Packages/SpliitKit && swift build --build-system native --show-bin-path)
// swiftc -parse-as-library -module-cache-path /tmp/spliit-model-module-cache \
//   -I "$core_build/Modules" Spliit/GroupDetailModel.swift \
//   Scripts/check-group-model.swift "$core_build"/SpliitAPI.build/*.o \
//   "$core_build"/SpliitCore.build/*.o -o /tmp/check-group-model
// python3 -c "import subprocess; subprocess.run(['/tmp/check-group-model'], check=True, timeout=30)"

import Foundation
import SpliitAPI

// Same URLProtocol seam as the API tests, with responses held until the check releases them.
private final class HeldRequest: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var waiting: [HeldRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.lock.withLock { Self.waiting.append(self) } }
    override func stopLoading() {}

    static func next() async throws -> HeldRequest {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if let request = lock.withLock({ waiting.isEmpty ? nil : waiting.removeFirst() }) {
                return request
            }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw CheckFailure.requestDidNotStart
    }

    func respond(_ data: Data, status: Int = 200) {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
        )!
        client!.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client!.urlProtocol(self, didLoad: data)
        client!.urlProtocolDidFinishLoading(self)
    }

    func fail() { client!.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost)) }
}

private enum CheckFailure: Error { case requestDidNotStart }

@main
private struct CheckGroupModel {
    @MainActor static func main() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HeldRequest.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = TRPCClient(baseURL: URL(string: "https://model.example/")!, session: session)
        let totals = try Data(contentsOf: URL(fileURLWithPath:
            "Packages/SpliitKit/Tests/SpliitAPITests/Fixtures/groups-stats-overview-anonymous.json"
        ))

        let model = GroupDetailModel(groupID: "group")
        model.formattingLocale = Locale(identifier: "fr_FR")
        precondition(model.moneyFormatter.string(minorUnits: 1234).contains("12,34"))
        model.formattingLocale = .autoupdatingCurrent
        let canceled = Task { await model.loadStats(for: nil, using: client) }
        _ = try await HeldRequest.next()
        canceled.cancel()
        await canceled.value
        precondition(!model.statsLoad.isLoading && !model.statsLoad.didFail)
        let retry = Task { await model.loadStats(for: nil, using: client) }
        try await HeldRequest.next().respond(totals)
        await retry.value
        precondition(model.stats != nil && model.statsLoad.hasLoaded)

        // Older success, failure, or cancellation must not replace a newer same-participant result.
        for outcome in ["success", "failure", "unsupported", "cancellation"] {
            let old = Task { await model.refreshStats(for: nil, using: client) }
            let oldRequest = try await HeldRequest.next()
            let latest = Task { await model.refreshStats(for: nil, using: client) }
            try await HeldRequest.next().respond(totals)
            await latest.value
            let expected = model.stats
            switch outcome {
            case "success":
                let changed = String(decoding: totals, as: UTF8.self)
                    .replacingOccurrences(of: "63680", with: "1")
                oldRequest.respond(Data(changed.utf8))
            case "failure": oldRequest.fail()
            case "unsupported":
                let missing = Data(#"{"error":{"json":{"message":"No procedure found","code":-32004,"data":{"code":"NOT_FOUND","httpStatus":404}}}}"#.utf8)
                oldRequest.respond(missing, status: 404)
                try await HeldRequest.next().respond(missing, status: 404)
            default: old.cancel()
            }
            await old.value
            precondition(model.stats == expected)
            precondition(model.statsLoad.hasLoaded && !model.statsLoad.didFail)
            precondition(!model.statsLoad.isLoading)
            precondition(!model.statsUnavailable)
        }

        // Cancellation keeps the next page available and preserves its cursor for retry.
        let firstPage = Task { await model.search("query", using: client) }
        try await HeldRequest.next().respond(Data(
            #"{"result":{"data":{"json":{"expenses":[],"hasMore":true,"nextCursor":20}}}}"#.utf8
        ))
        await firstPage.value
        precondition(model.hasMoreSearchResults)
        let page = Task { await model.loadNextSearchPage(using: client) }
        let pageRequest = try await HeldRequest.next()
        page.cancel()
        await page.value
        precondition(model.hasMoreSearchResults && !model.isLoadingMoreSearchResults)
        let pageRetry = Task { await model.loadNextSearchPage(using: client) }
        let retryRequest = try await HeldRequest.next()
        precondition(pageRequest.request.url == retryRequest.request.url)
        retryRequest.respond(Data(
            #"{"result":{"data":{"json":{"expenses":[],"hasMore":false,"nextCursor":40}}}}"#.utf8
        ))
        await pageRetry.value
        precondition(!model.hasMoreSearchResults && !model.isLoadingMoreSearchResults)

        // Do not rely on the view canceling its previous task: Android's bridge may leave it alive.
        let staleDebounce = Task { await model.search("other", using: client) }
        try await Task.sleep(for: .milliseconds(10))
        await model.search("query", using: client)
        try await Task.sleep(for: .milliseconds(300))
        precondition(model.filter == "query" && !model.searchLoad.isLoading)
        await staleDebounce.value

        let staleSearch = Task { await model.search("old", using: client) }
        let staleRequest = try await HeldRequest.next()
        let latestSearch = Task { await model.search("latest", using: client) }
        try await HeldRequest.next().respond(Data(
            #"{"result":{"data":{"json":{"expenses":[],"hasMore":false,"nextCursor":40}}}}"#.utf8
        ))
        await latestSearch.value
        staleRequest.respond(Data(
            #"{"result":{"data":{"json":{"expenses":[],"hasMore":true,"nextCursor":20}}}}"#.utf8
        ))
        await staleSearch.value
        precondition(model.filter == "latest" && !model.hasMoreSearchResults)

        // Exercise the three real sentinel loaders with their first pages already loaded.
        let reload = Task { await model.reload(using: client) }
        let fixtures = ["groups.get": "groups-get", "groups.balances.list": "balances-list",
                        "categories.list": "categories-list"]
        let expensesPage = Data(#"{"result":{"data":{"json":{"expenses":[],"hasMore":true,"nextCursor":20}}}}"#.utf8)
        let activityPage = Data(#"{"result":{"data":{"json":{"activities":[],"hasMore":true,"nextCursor":20}}}}"#.utf8)
        for _ in 0..<4 {
            let request = try await HeldRequest.next()
            let procedure = request.request.url!.lastPathComponent
            if procedure == "groups.expenses.list" {
                request.respond(expensesPage)
            } else {
                let fixture = fixtures[procedure]!
                request.respond(try Data(contentsOf: URL(fileURLWithPath:
                    "Packages/SpliitKit/Tests/SpliitAPITests/Fixtures/\(fixture).json"
                )))
            }
        }
        await reload.value
        let activities = Task { await model.loadActivitiesIfNeeded(using: client) }
        try await HeldRequest.next().respond(activityPage)
        await activities.value
        let search = Task { await model.search("pages", using: client) }
        try await HeldRequest.next().respond(expensesPage)
        await search.value

        let loaders: [(String, @MainActor () async -> Void, @MainActor () -> Bool,
                       @MainActor () -> Bool, Data)] = [
            ("expenses", { await model.loadNextPage(using: client) },
             { model.hasMoreExpenses }, { model.isLoadingMore }, expensesPage),
            ("activity", { await model.loadNextActivityPage(using: client) },
             { model.hasMoreActivities }, { model.isLoadingMoreActivities }, activityPage),
            ("search", { await model.loadNextSearchPage(using: client) },
             { model.hasMoreSearchResults }, { model.isLoadingMoreSearchResults }, expensesPage),
        ]
        for (name, load, hasMore, isLoading, response) in loaders {
            for outcome in ["cancellation", "success", "failure"] {
                let old = Task { await load() }
                let oldRequest = try await HeldRequest.next()
                // Start reentry while its predecessor is still running, before cancellation unwinds.
                let replacement = Task { await load() }
                let replacementRequest = try await HeldRequest.next()
                precondition(oldRequest.request.url == replacementRequest.request.url, name)
                switch outcome {
                case "cancellation": old.cancel()
                case "success":
                    oldRequest.respond(Data(String(decoding: response, as: UTF8.self)
                        .replacingOccurrences(of: "true", with: "false").utf8))
                default: oldRequest.fail()
                }
                await old.value
                precondition(hasMore() && isLoading(), name)
                replacementRequest.respond(response)
                await replacement.value
                precondition(hasMore() && !isLoading(), name)
            }

            // First-page replacement invalidates reads started both before and during refresh.
            let beforeRefresh = Task { await load() }
            let beforeRequest = try await HeldRequest.next()
            let refresh = Task {
                switch name {
                case "expenses": await model.reload(using: client)
                case "activity": await model.refreshActivities(using: client)
                default: await model.search("refreshed", using: client)
                }
            }
            var firstRequest: HeldRequest?
            for _ in 0..<(name == "expenses" ? 3 : 1) {
                let request = try await HeldRequest.next()
                let procedure = request.request.url!.lastPathComponent
                if procedure == "groups.expenses.list" || procedure == "groups.activities.list" {
                    firstRequest = request
                } else {
                    request.respond(try Data(contentsOf: URL(fileURLWithPath:
                        "Packages/SpliitKit/Tests/SpliitAPITests/Fixtures/\(fixtures[procedure]!).json"
                    )))
                }
            }
            let duringRefresh = Task { await load() }
            let duringRequest = try await HeldRequest.next()
            firstRequest!.respond(Data(String(decoding: response, as: UTF8.self)
                .replacingOccurrences(of: "true", with: "false").utf8))
            await refresh.value
            precondition(!hasMore() && !isLoading(), name)
            beforeRequest.respond(response)
            duringRequest.respond(response)
            await beforeRefresh.value
            await duringRefresh.value
            precondition(!hasMore() && !isLoading(), name)
        }
        print("PASS: totals cancellation/stale responses; all pagination loaders reenter safely; uncanceled search ordering")
    }
}
