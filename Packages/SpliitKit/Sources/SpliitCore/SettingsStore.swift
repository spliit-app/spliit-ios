import Foundation
import Observation

/// App settings. Today that's only which instance a *new* group starts on.
///
/// Not which instance the app talks to: that is a property of each group, because one list can
/// hold groups from spliit.app and from a server at home at the same time. What's left here is
/// the address the "Create group" form opens on — the last one a group was deliberately created
/// on, so somebody who self-hosts isn't choosing it again every time.
///
/// It lives in `UserDefaults` on purpose: a launch argument of the form `-baseURL <value>` lands
/// in the argument domain automatically, so a UI test can point the app at its own server
/// without the app needing any test-only code path.
@MainActor
@Observable
public final class SettingsStore {

    public enum Key {
        /// Still "baseURL": the launch argument, and every install that has one stored, predate
        /// this being a default rather than the address of everything.
        public static let baseURL = "baseURL"
    }

    public nonisolated static let officialInstanceURL = URL(string: "https://spliit.app/")!

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaultInstanceURL = Self.readDefaultInstance(from: defaults)
    }

    /// Where a group is created unless the form is told otherwise, and what a group with no
    /// address of its own is taken to be on. Always ends in a slash, so procedure paths append
    /// cleanly.
    public var defaultInstanceURL: URL {
        didSet {
            guard defaultInstanceURL != oldValue else { return }
            defaults.set(defaultInstanceURL.absoluteString, forKey: Key.baseURL)
        }
    }

    public var isUsingOfficialInstance: Bool {
        defaultInstanceURL == Self.officialInstanceURL
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

    /// What to call an instance on screen: the host, with the port and path when it has them,
    /// and never the scheme. "spliit.app" is what people call it; a row reading
    /// "https://spliit.app/" is a URL rather than a name.
    public nonisolated static func displayName(for url: URL) -> String {
        guard let host = url.host() else { return url.absoluteString }
        let port = url.port.map { ":\($0)" } ?? ""
        let path = url.path().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.isEmpty ? "\(host)\(port)" : "\(host)\(port)/\(path)"
    }

    private static func readDefaultInstance(from defaults: UserDefaults) -> URL {
        guard let stored = defaults.string(forKey: Key.baseURL),
              let url = normalize(stored)
        else {
            return officialInstanceURL
        }
        return url
    }
}
