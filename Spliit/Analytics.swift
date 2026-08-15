import Foundation
import SwiftUI

/// Screen and event tracking, matching what the React Native app reported so the existing
/// Plausible dashboard keeps working across the rewrite.
///
/// Plausible is cookieless and stores nothing per-person; only the screen name and, for a few
/// events, a group ID travel with the request. Nothing is sent from debug builds or under UI
/// tests — a test run should never show up as traffic.
struct Analytics: Sendable {

    /// The same site the old app reported to.
    static let domain = "spliit.app/mobile"
    private static let endpoint = URL(string: "https://plausible.io/api/event")!

    enum Screen: String {
        case home
        case about
        case createGroup = "create-group"
        case addGroupByURL = "add-group-by-url"
        case groupExpenses = "group-expenses"
        case groupBalances = "group-balances"
        case groupSettings = "group-settings"
        case groupCreateExpense = "group-create-expense"
        case groupEditExpense = "group-edit-expense"
    }

    enum Event: String {
        case createGroup = "create-group"
        case createExpense = "create-expense"
    }

    var isEnabled: Bool

    static let shared: Analytics = {
        #if DEBUG
        return Analytics(isEnabled: false)
        #else
        let isUITest = ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-uiTest") }
        return Analytics(isEnabled: !isUITest)
        #endif
    }()

    func screen(_ screen: Screen, properties: [String: String] = [:]) {
        send(name: "pageview", path: screen.rawValue, properties: properties)
    }

    func event(_ event: Event, properties: [String: String] = [:]) {
        send(name: event.rawValue, path: "", properties: properties)
    }

    private func send(name: String, path: String, properties: [String: String]) {
        guard isEnabled else { return }

        var body: [String: Any] = [
            "name": name,
            "domain": Self.domain,
            "url": "https://\(Self.domain)/\(path)",
        ]
        if !properties.isEmpty { body["props"] = properties }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Plausible rejects requests without one.
        request.setValue("Spliit iOS", forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        // Fire and forget: analytics must never delay or fail anything the user is doing.
        URLSession.shared.dataTask(with: request).resume()
    }
}

extension View {
    /// Reports a screen view when this view appears.
    func trackScreen(_ screen: Analytics.Screen, properties: [String: String] = [:]) -> some View {
        onAppear { Analytics.shared.screen(screen, properties: properties) }
    }
}
