import Foundation
import Testing

@testable import SpliitCore

/// Two things are worth pinning about analytics. The names are one: they are the axis of a
/// dashboard that has been collecting since the React Native app, and a rename silently splits
/// a line in two. The payload is the other: nothing identifying a group or an expense may leave
/// the device, and the way that is guaranteed — no custom properties at all — is invisible at
/// the call site, so it is asserted here instead.
@Suite("Analytics events")
struct AnalyticsEventTests {

    @Test("A screen view is a pageview at the screen's path")
    func screenPayload() {
        #expect(
            AnalyticsEvent.screen(.groupExpenses).body == [
                "name": "pageview",
                "domain": "spliit.app/mobile",
                "url": "https://spliit.app/mobile/group-expenses",
            ]
        )
    }

    @Test("An action is named, and counted wherever the person was")
    func actionPayload() {
        #expect(
            AnalyticsEvent.action(.createExpense).body == [
                "name": "create-expense",
                "domain": "spliit.app/mobile",
                "url": "https://spliit.app/mobile/",
            ]
        )
    }

    /// The payload is a fixed three keys. Plausible reads custom properties from `props`, so an
    /// ID could only ever arrive under that key — its absence is the whole guarantee.
    @Test("Nothing but the name, the domain and the path is ever sent")
    func payloadCarriesNothingElse() {
        let payloads =
            AnalyticsEvent.Screen.allCases.map { AnalyticsEvent.screen($0).body }
            + AnalyticsEvent.Action.allCases.map { AnalyticsEvent.action($0).body }

        for body in payloads {
            #expect(body.keys.sorted() == ["domain", "name", "url"])
            #expect(body["props"] == nil)
        }
    }

    /// The names the Plausible dashboard is already keyed by. Changing one starts a new line on
    /// the chart rather than continuing the old one, so this is a deliberate-change guard: if a
    /// rename is really wanted, the dashboard needs to know first.
    @Test("Screen names match the ones the dashboard already has")
    func screenNamesAreStable() {
        #expect(
            AnalyticsEvent.Screen.allCases.map(\.rawValue) == [
                "home",
                "about",
                "create-group",
                "add-group-by-url",
                "add-group-by-qr-code",
                "group-expenses",
                "group-balances",
                "group-search",
                "group-information",
                "group-stats",
                "group-activity",
                "group-settings",
                "group-create-expense",
                "group-edit-expense",
            ]
        )
    }

    @Test("Action names match the ones the dashboard already has")
    func actionNamesAreStable() {
        #expect(
            AnalyticsEvent.Action.allCases.map(\.rawValue)
                == ["create-group", "create-expense", "scan-receipt", "attach-document"]
        )
    }

    // MARK: - Umami

    private static let phone = AnalyticsDevice(
        isPad: false,
        systemVersion: "26.0.1",
        appVersion: "2.6.0",
        screenWidth: 393,
        screenHeight: 852,
        language: "fr-CA"
    )

    /// Decoded back from the JSON that goes on the wire, so a field the encoder adds — an
    /// optional that stops being nil, say — shows up here rather than on the dashboard.
    private func umamiJSON(_ event: AnalyticsEvent) throws -> [String: Any] {
        let request = event.umamiRequest(websiteID: "site", device: Self.phone)
        let data = try JSONEncoder().encode(request)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("A screen view reaches Umami as a pageview: no name, at the screen's path")
    func umamiScreenPayload() throws {
        let json = try umamiJSON(.screen(.groupExpenses))
        let payload = try #require(json["payload"] as? [String: String])

        #expect(json["type"] as? String == "event")
        #expect(
            payload == [
                "website": "site",
                "hostname": "spliit.app",
                "url": "/group-expenses",
                "language": "fr-CA",
                "screen": "393x852",
            ]
        )
    }

    @Test("An action reaches Umami by its name, wherever the person was")
    func umamiActionPayload() throws {
        let payload = try #require(try umamiJSON(.action(.createExpense))["payload"] as? [String: String])

        #expect(payload["name"] == "create-expense")
        #expect(payload["url"] == "/")
    }

    /// Umami reads `data` as custom properties and `id` as a persistent identifier for the
    /// person; `title` and `referrer` are where the web tracker leaks a group's name or ID. None
    /// may ever be sent, and the request type has nowhere to put them — this proves it.
    @Test("Nothing but the site, the path, the name and the device's language and screen")
    func umamiPayloadCarriesNothingElse() throws {
        let events =
            AnalyticsEvent.Screen.allCases.map { AnalyticsEvent.screen($0) }
            + AnalyticsEvent.Action.allCases.map { AnalyticsEvent.action($0) }

        for event in events {
            let json = try umamiJSON(event)
            let payload = try #require(json["payload"] as? [String: Any])

            #expect(json.keys.sorted() == ["payload", "type"])
            #expect(
                Set(payload.keys).isSubset(of: ["website", "hostname", "url", "name", "language", "screen"])
            )
        }
    }

    @Test("The User-Agent names the OS the way Safari does, so Umami neither drops nor misfiles it")
    func umamiUserAgent() {
        #expect(
            Self.phone.userAgent
                == "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0_1 like Mac OS X) AppleWebKit/605.1.15 "
                + "(KHTML, like Gecko) Mobile/15E148 Spliit/2.6.0"
        )

        var pad = Self.phone
        pad.isPad = true
        #expect(pad.userAgent.hasPrefix("Mozilla/5.0 (iPad; CPU OS 26_0_1 like Mac OS X)"))
    }
}
