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

    /// Kept at the top of the home screen. The web app stores this as a separate array of IDs
    /// because `localStorage` gave it one key per concern; here it belongs to the group, which
    /// means one file, one write, and no way to end up starring a group the list has forgotten.
    public var isStarred: Bool

    /// Kept, but out of the way — the trip that ended, the flatshare that moved out. Starring
    /// and archiving say opposite things, so a group is never both.
    public var isArchived: Bool

    public var id: String { groupId }

    public init(
        groupId: String,
        groupName: String,
        isStarred: Bool = false,
        isArchived: Bool = false
    ) {
        self.groupId = groupId
        self.groupName = groupName
        self.isStarred = isStarred
        self.isArchived = isArchived
    }

    private enum CodingKeys: String, CodingKey {
        case groupId, groupName, isStarred, isArchived
    }

    /// Written by hand because the flags arrived after the file did: every list saved before
    /// this release, and everything the React Native app ever wrote, has neither key. A
    /// synthesised decoder would throw on the missing key rather than fall back to the default
    /// — and a list that fails to decode is a list of groups nobody can get back to.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        groupId = try container.decode(String.self, forKey: .groupId)
        groupName = try container.decode(String.self, forKey: .groupName)
        isStarred = try container.decodeIfPresent(Bool.self, forKey: .isStarred) ?? false
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
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

    /// The three sections the home screen shows, in the order it shows them. Each group appears
    /// in exactly one: a group that somehow carried both flags reads as archived, because that
    /// is the quieter of the two mistakes to make on someone's behalf.
    public var starred: [RecentGroup] { groups.filter { $0.isStarred && !$0.isArchived } }
    public var recent: [RecentGroup] { groups.filter { !$0.isStarred && !$0.isArchived } }
    public var archived: [RecentGroup] { groups.filter(\.isArchived) }

    /// Adds a group, or moves it to the front and refreshes its name if it's already there.
    ///
    /// Callers build a `RecentGroup` from what the server just told them, which carries no
    /// flags — so the stored ones win. Otherwise renaming a group would quietly unstar it.
    public func remember(_ group: RecentGroup) {
        var group = group
        if let existing = groups.first(where: { $0.groupId == group.groupId }) {
            group.isStarred = existing.isStarred
            group.isArchived = existing.isArchived
        }
        groups.removeAll { $0.groupId == group.groupId }
        groups.insert(group, at: 0)
        save()
    }

    public func forget(groupId: String) {
        groups.removeAll { $0.groupId == groupId }
        save()
    }

    /// Stars a group, or takes the star away. Starring un-archives, because a group cannot be
    /// both the one you reach for most and the one you have put away.
    public func setStarred(_ isStarred: Bool, groupId: String) {
        modify(groupId) { group in
            group.isStarred = isStarred
            if isStarred { group.isArchived = false }
        }
    }

    /// Archives a group, or brings it back. Archiving unstars, for the same reason.
    public func setArchived(_ isArchived: Bool, groupId: String) {
        modify(groupId) { group in
            group.isArchived = isArchived
            if isArchived { group.isStarred = false }
        }
    }

    private func modify(_ groupId: String, _ change: (inout RecentGroup) -> Void) {
        guard let index = groups.firstIndex(where: { $0.groupId == groupId }) else { return }
        change(&groups[index])
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
