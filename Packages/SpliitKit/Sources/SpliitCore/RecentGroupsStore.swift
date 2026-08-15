import Foundation
import Observation

/// A group the user has opened, remembered locally. Spliit has no accounts — this list is the
/// only way back to a group, which is why the migration from the old app matters so much.
///
/// The property names match the JSON the React Native app wrote, so the same decoder reads
/// both the legacy value and ours.
public struct RecentGroup: Codable, Sendable, Identifiable, Hashable {
    public let groupId: String
    public var groupName: String

    public var id: String { groupId }

    public init(groupId: String, groupName: String) {
        self.groupId = groupId
        self.groupName = groupName
    }
}

/// The user's recent groups, most recently touched first.
@MainActor
@Observable
public final class RecentGroupsStore {

    public private(set) var groups: [RecentGroup] = []

    private let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        groups = Self.load(from: fileURL) ?? []
    }

    /// The default location: `Application Support/Spliit/recent-groups.json`.
    public static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        return base.appending(path: "Spliit").appending(path: "recent-groups.json")
    }

    /// Adds a group, or moves it to the front and refreshes its name if it's already there.
    public func remember(_ group: RecentGroup) {
        groups.removeAll { $0.groupId == group.groupId }
        groups.insert(group, at: 0)
        save()
    }

    public func forget(groupId: String) {
        groups.removeAll { $0.groupId == groupId }
        save()
    }

    /// Replaces the whole list — used by the migration, and to reset state in UI tests.
    public func replaceAll(with groups: [RecentGroup]) {
        self.groups = groups
        save()
    }

    // MARK: - Persistence

    private static func load(from url: URL) -> [RecentGroup]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([RecentGroup].self, from: data)
    }

    private func save() {
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(groups)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Losing a write is recoverable — the list rebuilds as groups are opened — so
            // don't take the app down over it.
            assertionFailure("Couldn’t save recent groups: \(error)")
        }
    }
}
