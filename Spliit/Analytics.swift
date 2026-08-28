import Foundation
import SpliitCore
import SwiftUI

/// Posts ``AnalyticsEvent`` to Plausible, and nothing else.
///
/// Plausible is cookieless and stores nothing per-person; what travels with a request is the
/// screen name and no more — see ``AnalyticsEvent`` for why a group or expense ID cannot be
/// attached to one. Nothing is sent from debug builds or under UI tests: a test run should
/// never show up as traffic.
struct Analytics: Sendable {

    private static let endpoint = URL(string: "https://plausible.io/api/event")!

    var isEnabled: Bool

    static let shared: Analytics = {
        #if DEBUG
        return Analytics(isEnabled: false)
        #else
        let isUITest = ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-uiTest") }
        return Analytics(isEnabled: !isUITest)
        #endif
    }()

    func screen(_ screen: AnalyticsEvent.Screen) {
        send(.screen(screen))
    }

    func event(_ action: AnalyticsEvent.Action) {
        send(.action(action))
    }

    private func send(_ event: AnalyticsEvent) {
        guard isEnabled else { return }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Plausible rejects requests without one.
        request.setValue("Spliit iOS", forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: event.body)

        // Fire and forget: analytics must never delay or fail anything the user is doing.
        URLSession.shared.dataTask(with: request).resume()
    }
}

extension View {
    /// Reports a screen view when this view appears.
    func trackScreen(_ screen: AnalyticsEvent.Screen) -> some View {
        onAppear { Analytics.shared.screen(screen) }
    }
}
