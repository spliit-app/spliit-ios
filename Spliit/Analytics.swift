import Foundation
import SpliitCore
import SwiftUI
import UIKit

/// Posts ``AnalyticsEvent`` to Plausible and to Umami, and nothing else.
///
/// Both are cookieless and store nothing per-person; what travels with a request is the screen
/// name and no more — see ``AnalyticsEvent`` for why a group or expense ID cannot be attached
/// to one. Umami is fed beside Plausible until its numbers can be trusted, and only once
/// ``AnalyticsEvent/umamiWebsiteID`` names the app's site. Nothing is sent from debug builds or
/// under UI tests: a test run should never show up as traffic.
@MainActor
struct Analytics {

    private static let plausibleEndpoint = URL(string: "https://plausible.io/api/event")!

    // Straight to Umami Cloud rather than through spliit.app's first-party proxy: that exists
    // for ad blockers and the web's content security policy, neither of which an app meets, and
    // going direct keeps the app independent of how the website is deployed.
    private static let umamiEndpoint = URL(string: "https://cloud.umami.is/api/send")!

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

        var request = URLRequest(url: Self.plausibleEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Plausible rejects requests without one.
        request.setValue("Spliit iOS", forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: event.body)

        // Fire and forget: analytics must never delay or fail anything the user is doing.
        URLSession.shared.dataTask(with: request).resume()

        sendToUmami(event)
    }

    private func sendToUmami(_ event: AnalyticsEvent) {
        guard let websiteID = AnalyticsEvent.umamiWebsiteID else { return }

        let device = Self.device
        var request = URLRequest(url: Self.umamiEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(device.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONEncoder().encode(
            event.umamiRequest(websiteID: websiteID, device: device)
        )

        URLSession.shared.dataTask(with: request).resume()
    }

    /// Read at each event rather than once: the language can change under a running app, and
    /// the screen is only known once a scene is connected.
    private static var device: AnalyticsDevice {
        let screen =
            UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen.bounds.size }
            .first ?? .zero
        return AnalyticsDevice(
            isPad: UIDevice.current.userInterfaceIdiom == .pad,
            systemVersion: UIDevice.current.systemVersion,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            // Portrait, as `window.screen` reports it whichever way the phone is held.
            screenWidth: Int(min(screen.width, screen.height)),
            screenHeight: Int(max(screen.width, screen.height)),
            language: Locale.preferredLanguages.first ?? "en"
        )
    }
}

extension View {
    /// Reports a screen view when this view appears.
    func trackScreen(_ screen: AnalyticsEvent.Screen) -> some View {
        onAppear { Analytics.shared.screen(screen) }
    }
}
