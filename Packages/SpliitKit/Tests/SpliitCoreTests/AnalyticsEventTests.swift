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
                "group-expenses",
                "group-balances",
                "group-search",
                "group-information",
                "group-stats",
                "group-settings",
                "group-create-expense",
                "group-edit-expense",
            ]
        )
    }

    @Test("Action names match the ones the dashboard already has")
    func actionNamesAreStable() {
        #expect(
            AnalyticsEvent.Action.allCases.map(\.rawValue) == ["create-group", "create-expense"]
        )
    }
}
