import Foundation

/// Pulls the React Native app's two stored keys into values the SwiftUI app understands.
///
/// This runs unattended on the first launch after the update, and groups are only reachable by
/// ID — a user who loses their list cannot get it back. So nothing here throws: anything
/// unreadable is recorded in `problems` and skipped, and the caller keeps whatever was
/// recovered. The legacy files are never modified or deleted.
public enum LegacyDataMigration {

    /// The keys the React Native app wrote.
    public enum Key {
        public static let recentGroups = "recent-groups"
        public static let settings = "spliit-settings"
    }

    public struct Result: Sendable, Equatable {
        public var recentGroups: [RecentGroup] = []
        /// Only set when the user had pointed the old app at a self-hosted instance.
        public var baseURL: URL?
        /// Human-readable notes about anything that couldn't be read, for logging.
        public var problems: [String] = []

        public var foundAnything: Bool {
            !recentGroups.isEmpty || baseURL != nil
        }
    }

    public static func read(from storage: LegacyAsyncStorage) -> Result {
        var result = Result()

        if let raw = storage.value(forKey: Key.recentGroups) {
            do {
                result.recentGroups = try JSONDecoder().decode(
                    [RecentGroup].self, from: Data(raw.utf8)
                )
            } catch {
                result.problems.append("recent-groups could not be decoded: \(error)")
            }
        }

        if let raw = storage.value(forKey: Key.settings) {
            do {
                let settings = try JSONDecoder().decode(StoredSettings.self, from: Data(raw.utf8))
                if let text = settings.baseUrl, let url = URL(string: text), url.scheme != nil {
                    result.baseURL = url
                } else if settings.baseUrl != nil {
                    result.problems.append("spliit-settings held an unusable baseUrl")
                }
            } catch {
                result.problems.append("spliit-settings could not be decoded: \(error)")
            }
        }

        return result
    }

    private struct StoredSettings: Decodable {
        let baseUrl: String?
    }
}
