import Foundation
import Observation

/// App settings: which Spliit instance to talk to, and what the app interrupts for.
///
/// These live in `UserDefaults` on purpose: a launch argument of the form `-baseURL <value>`
/// lands in the argument domain automatically, so a UI test can point the app at its own
/// server without the app needing any test-only code path.
@MainActor
@Observable
public final class SettingsStore {

    public enum Key {
        public static let baseURL = "baseURL"
        public static let notificationLevel = "notificationLevel"
    }

    public nonisolated static let defaultBaseURL = URL(string: "https://spliit.app/")!

    /// What a group notifies about when it has not been given a level of its own.
    ///
    /// The useful middle by default. Nothing reaches a lock screen until iOS has been asked for
    /// permission, so this is a preference waiting for an answer rather than one taking effect
    /// on install — which is what makes it safe for it to be something other than "nothing".
    public nonisolated static let defaultNotificationLevel = NotificationLevel.involvingMe

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        baseURL = Self.readBaseURL(from: defaults)
        notificationLevel = Self.readNotificationLevel(from: defaults)
    }

    /// The instance the app talks to. Always ends in a slash, so procedure paths append cleanly.
    public var baseURL: URL {
        didSet {
            guard baseURL != oldValue else { return }
            defaults.set(baseURL.absoluteString, forKey: Key.baseURL)
        }
    }

    /// What every group that has not said otherwise interrupts for.
    public var notificationLevel: NotificationLevel {
        didSet {
            guard notificationLevel != oldValue else { return }
            defaults.set(notificationLevel.rawValue, forKey: Key.notificationLevel)
        }
    }

    public var isUsingOfficialInstance: Bool {
        baseURL == Self.defaultBaseURL
    }

    public func resetToOfficialInstance() {
        baseURL = Self.defaultBaseURL
    }

    /// Accepts what a person would type — "spliit.example.com", "https://spliit.example.com" —
    /// and returns the URL to store, or nil if it can't be made into one.
    public nonisolated static func normalize(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard var components = URLComponents(string: withScheme),
              let host = components.host, !host.isEmpty
        else {
            return nil
        }

        if !components.path.hasSuffix("/") {
            components.path += "/"
        }
        components.query = nil
        components.fragment = nil
        return components.url
    }

    /// A stored value this build cannot read falls back to the default rather than throwing:
    /// the setting is a preference, and refusing to launch over one would be absurd.
    private static func readNotificationLevel(from defaults: UserDefaults) -> NotificationLevel {
        guard let stored = defaults.string(forKey: Key.notificationLevel),
              let level = NotificationLevel(rawValue: stored)
        else {
            return defaultNotificationLevel
        }
        return level
    }

    private static func readBaseURL(from defaults: UserDefaults) -> URL {
        guard let stored = defaults.string(forKey: Key.baseURL),
              let url = normalize(stored)
        else {
            return defaultBaseURL
        }
        return url
    }
}
