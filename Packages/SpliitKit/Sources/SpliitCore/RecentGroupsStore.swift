import Foundation
import Observation
import SpliitAPI

/// Who the person holding this phone is, in one group.
///
/// Spliit has no accounts, so this is a local answer to a local question, and it is asked once
/// per group: someone can be Ana in the flatshare and a guest on the ski trip.
///
/// Three states, which is why this is not simply a `String?`. A group nobody has answered for
/// should be asked; a group answered with "nobody" — a shared phone, a group kept for other
/// people — should not be asked again. `nil` is the question, `.nobody` is an answer to it.
public enum ActiveParticipant: Sendable, Hashable, Codable {
    case participant(String)
    case nobody

    /// Encoded as the bare participant ID, and as an empty string for "nobody", so the stored
    /// list stays something a person can read and a test can write by hand.
    public init(from decoder: any Decoder) throws {
        let id = try decoder.singleValueContainer().decode(String.self)
        self = id.isEmpty ? .nobody : .participant(id)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .participant(let id): try container.encode(id)
        case .nobody: try container.encode("")
        }
    }

    public var participantID: String? {
        if case .participant(let id) = self { return id }
        return nil
    }

    /// Reads a stored answer against the group it was stored for.
    ///
    /// A participant who has since been removed reads as *unanswered* rather than as a missing
    /// person: the alternative is a screen that shows no balance, names nobody, and offers no
    /// way to say so.
    public static func resolve(
        _ stored: ActiveParticipant?,
        in participants: [Participant]
    ) -> ActiveParticipant? {
        guard case .participant(let id) = stored else { return stored }
        return participants.contains { $0.id == id } ? stored : nil
    }
}

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

    /// Which participant the user is here, once they have said. Kept beside the flags for the
    /// same reason they are: one file, one write, and no way to be somebody in a group the list
    /// has forgotten.
    public var activeParticipant: ActiveParticipant?

    public var id: String { groupId }

    public init(
        groupId: String,
        groupName: String,
        isStarred: Bool = false,
        isArchived: Bool = false,
        activeParticipant: ActiveParticipant? = nil
    ) {
        self.groupId = groupId
        self.groupName = groupName
        self.isStarred = isStarred
        self.isArchived = isArchived
        self.activeParticipant = activeParticipant
    }

    private enum CodingKeys: String, CodingKey {
        case groupId, groupName, isStarred, isArchived, activeParticipant
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
        activeParticipant = try container.decodeIfPresent(
            ActiveParticipant.self, forKey: .activeParticipant
        )
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
    /// flags and no identity — so the stored ones win. Otherwise renaming a group would quietly
    /// unstar it, and make the person holding the phone a stranger in it.
    public func remember(_ group: RecentGroup) {
        var group = group
        if let existing = groups.first(where: { $0.groupId == group.groupId }) {
            group.isStarred = existing.isStarred
            group.isArchived = existing.isArchived
            group.activeParticipant = existing.activeParticipant
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

    /// Who the user said they are in this group, or nil if they have not been asked yet.
    public func activeParticipant(inGroup groupId: String) -> ActiveParticipant? {
        groups.first { $0.groupId == groupId }?.activeParticipant
    }

    /// Who to credit for a change made from this phone, as the server's activity log wants it.
    ///
    /// Nil is the honest answer twice over: for a phone that has never been asked, and for one
    /// that answered "nobody". The log then says "Someone", which is exactly what is known.
    public func actorID(inGroup groupId: String, participants: [Participant]) -> String? {
        ActiveParticipant.resolve(activeParticipant(inGroup: groupId), in: participants)?
            .participantID
    }

    /// Records the answer. A group the list has never heard of is not one anybody can be
    /// standing in — every way into a group screen remembers it first — so this is a no-op
    /// rather than a reason to invent a row with no name.
    public func setActiveParticipant(_ participant: ActiveParticipant, groupId: String) {
        modify(groupId) { $0.activeParticipant = participant }
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
