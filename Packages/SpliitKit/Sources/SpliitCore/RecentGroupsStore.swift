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

    /// How this group's expenses are usually divided, once somebody has said so. Beside the
    /// rest for the same reason they are, and with one more: a split is a list of participant
    /// IDs, and the only thing that can vouch for those is the group they belong to.
    public var defaultSplit: DefaultSplit?

    /// When this row last changed, in any way — opened, renamed, starred, archived, answered
    /// for. This is what decides a disagreement between two devices, and nothing else: the
    /// later row wins whole, because the fields on it were last edited together and picking a
    /// star from one side and a participant from the other would produce a row neither phone
    /// ever had.
    public var updatedAt: Date?

    /// When the group was last opened. Kept apart from `updatedAt` because it means something
    /// different: this is what "most recently first" is sorted by, and starring a group is not
    /// opening it.
    public var lastOpenedAt: Date?

    /// The Spliit instance this group is on.
    ///
    /// A group ID means nothing on its own: the same list can hold a flatshare on spliit.app and
    /// a family group on a server in somebody's hallway, and asking the wrong one about either
    /// gets back a group that does not exist. So the address belongs to the group, not to the
    /// app — which is what lets the two sit in one list.
    ///
    /// Nil means "wherever this install points by default", which is every list written before
    /// this existed and everything the React Native app ever wrote: those were one instance at a
    /// time. `stampInstances` fills them in on the next launch, so a nil never lives long enough
    /// for a changed default to move somebody's groups out from under them.
    public var instanceURL: URL?

    public var id: String { groupId }

    public init(
        groupId: String,
        groupName: String,
        isStarred: Bool = false,
        isArchived: Bool = false,
        activeParticipant: ActiveParticipant? = nil,
        defaultSplit: DefaultSplit? = nil,
        updatedAt: Date? = nil,
        lastOpenedAt: Date? = nil,
        instanceURL: URL? = nil
    ) {
        self.groupId = groupId
        self.groupName = groupName
        self.isStarred = isStarred
        self.isArchived = isArchived
        self.activeParticipant = activeParticipant
        self.defaultSplit = defaultSplit
        self.updatedAt = updatedAt
        self.lastOpenedAt = lastOpenedAt
        self.instanceURL = instanceURL
    }

    private enum CodingKeys: String, CodingKey {
        case groupId, groupName, isStarred, isArchived, activeParticipant, defaultSplit
        case updatedAt, lastOpenedAt, instanceURL
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
        defaultSplit = try container.decodeIfPresent(DefaultSplit.self, forKey: .defaultSplit)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        lastOpenedAt = try container.decodeIfPresent(Date.self, forKey: .lastOpenedAt)
        instanceURL = try container.decodeIfPresent(URL.self, forKey: .instanceURL)
    }
}

/// The whole of what one device knows about the list: the groups, and the ones it has been told
/// to forget.
///
/// The tombstones are here and nowhere else. Without them a merge is a union — the only shape
/// that can't lose a group — and a union resurrects everything anybody deletes, on every other
/// phone, forever. They are only needed until every device has heard, so they are dropped after
/// `tombstoneLifetime`.
public struct RecentGroupsSnapshot: Codable, Sendable, Equatable {
    public var groups: [RecentGroup]
    public var deleted: [String: Date]

    /// Long enough for a phone that spent a season in a drawer, short enough that the list of
    /// groups somebody once deleted doesn't become the larger half of what is stored.
    static let tombstoneLifetime: TimeInterval = 90 * 24 * 60 * 60

    public init(groups: [RecentGroup] = [], deleted: [String: Date] = [:]) {
        self.groups = groups
        self.deleted = deleted
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        groups = try container.decodeIfPresent([RecentGroup].self, forKey: .groups) ?? []
        deleted = try container.decodeIfPresent([String: Date].self, forKey: .deleted) ?? [:]
    }

    /// Combines what two devices know, in a way that gives the same answer whichever one is
    /// asking — so two phones that have both seen both snapshots agree without another round.
    ///
    /// The rules, in the order they matter: a group either side has is kept, because a group is
    /// only reachable by its ID and a list that drops one drops it for good. A group both sides
    /// have is taken from whichever edited it last. A group deleted after it was last edited is
    /// gone. Everything else is ordering.
    public static func merging(
        _ mine: RecentGroupsSnapshot,
        _ theirs: RecentGroupsSnapshot,
        now: Date = .now
    ) -> RecentGroupsSnapshot {
        var deleted = mine.deleted
        for (groupId, date) in theirs.deleted {
            deleted[groupId] = max(deleted[groupId] ?? .distantPast, date)
        }
        deleted = deleted.filter { now.timeIntervalSince($0.value) < tombstoneLifetime }

        var groups: [String: RecentGroup] = [:]
        for group in mine.groups + theirs.groups {
            guard let rival = groups[group.groupId] else {
                groups[group.groupId] = group
                continue
            }
            let isNewer = (group.updatedAt ?? .distantPast) > (rival.updatedAt ?? .distantPast)
            groups[group.groupId] = isNewer ? group : rival
        }

        let surviving = groups.values.filter { group in
            guard let tombstone = deleted[group.groupId] else { return true }
            return (group.updatedAt ?? .distantPast) > tombstone
        }

        return RecentGroupsSnapshot(groups: ordered(surviving), deleted: deleted)
    }

    /// Most recently opened first, which is the order the home screen shows and the order the
    /// list has always kept for itself. The group ID breaks a tie so that two devices sorting
    /// the same rows can't end up with different lists.
    static func ordered(_ groups: some Collection<RecentGroup>) -> [RecentGroup] {
        groups.sorted {
            let left = $0.lastOpenedAt ?? .distantPast
            let right = $1.lastOpenedAt ?? .distantPast
            return left == right ? $0.groupId < $1.groupId : left > right
        }
    }

    /// Gives every row a time, keeping the order it arrived in.
    ///
    /// A list written before this release — or by the React Native app, or seeded by a test —
    /// carries no timestamps at all, and the order it is in is the only record of when anything
    /// was opened. Turning that position back into a time is what stops the first merge from
    /// shuffling a list the user has never touched into alphabetical order.
    static func stamped(_ groups: [RecentGroup], now: Date = .now) -> [RecentGroup] {
        groups.enumerated().map { index, group in
            guard group.lastOpenedAt == nil else { return group }
            var group = group
            group.lastOpenedAt = now.addingTimeInterval(-Double(index) - 1)
            return group
        }
    }
}

/// The user's recent groups, most recently touched first.
///
/// The file on this device is the copy everything reads — the home screen, the App Intents, the
/// migration. iCloud is a second copy of the same thing, kept in step so that a new phone, or a
/// reinstall, doesn't start from a list of nothing: without accounts, a forgotten group ID is a
/// group nobody can get back to.
@MainActor
@Observable
public final class RecentGroupsStore {

    public private(set) var groups: [RecentGroup] = []

    private let fileURL: URL
    private let fileManager: FileManager
    private let cloud: (any RecentGroupsCloudStorage)?

    /// Groups this device has been told to forget, kept until every other device has heard.
    /// Only ever written to iCloud: with nothing to sync there is nothing to resurrect, so a
    /// device on its own needs no tombstones at all.
    private var deleted: [String: Date] = [:]

    /// - Parameter cloud: where to mirror the list, or nil to keep it on this device only —
    ///   which is what a UI test wants, and what the app falls back to on a platform or a build
    ///   without the iCloud entitlement.
    public init(
        fileURL: URL,
        fileManager: FileManager = .default,
        cloud: (any RecentGroupsCloudStorage)? = nil
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.cloud = cloud

        let local = RecentGroupsSnapshot.stamped(Self.load(from: fileURL) ?? [])
        guard let cloud else {
            groups = local
            return
        }

        let mine = RecentGroupsSnapshot(groups: local)
        let theirs = Self.read(from: cloud)
        let merged = RecentGroupsSnapshot.merging(mine, theirs)
        groups = merged.groups
        deleted = merged.deleted
        // Whichever side was behind gets written, which on an upgraded install is the empty
        // cloud and on a restored device is the empty file. When they already agree this is the
        // launch that writes nothing at all.
        if merged != mine || merged != theirs {
            save()
        }

        cloud.observeExternalChanges { [weak self] in
            self?.mergeFromCloud()
        }
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
            // The instance is the exception: the caller has just been answered by a server, so
            // it knows better than the list does where this group was found.
            group.instanceURL = group.instanceURL ?? existing.instanceURL
        }
        group.updatedAt = .now
        group.lastOpenedAt = group.updatedAt
        // Opening a group is the plainest possible statement that it should be in the list, so
        // it outranks another device having deleted it earlier.
        deleted[group.groupId] = nil
        groups.removeAll { $0.groupId == group.groupId }
        groups.insert(group, at: 0)
        save()
    }

    public func forget(groupId: String) {
        groups.removeAll { $0.groupId == groupId }
        if cloud != nil {
            deleted[groupId] = .now
        }
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

    /// How this group's expenses are usually split, or nil when nothing has been remembered.
    ///
    /// A split naming somebody the group no longer has reads as nothing remembered rather than
    /// as a smaller split — see ``DefaultSplit/applies(to:)``. It is left in the file rather than
    /// cleared: this is asked while a screen is being built, and a read is not the place to write
    /// anything. The next expense saved with the box ticked replaces it.
    public func defaultSplit(
        inGroup groupId: String, participants: [Participant]
    ) -> DefaultSplit? {
        guard let split = groups.first(where: { $0.groupId == groupId })?.defaultSplit,
              split.applies(to: participants)
        else { return nil }
        return split
    }

    /// Remembers how this expense was split, for the ones after it.
    public func setDefaultSplit(_ split: DefaultSplit, groupId: String) {
        modify(groupId) { $0.defaultSplit = split }
    }

    /// Where a group lives, or nil for one that has never been told.
    public func instanceURL(forGroup groupId: String) -> URL? {
        groups.first { $0.groupId == groupId }?.instanceURL
    }

    /// The instances the list actually uses, most recently opened first, resolving the groups
    /// that carry no address to `fallback`.
    public func instancesInUse(fallback: URL) -> [URL] {
        var seen: Set<URL> = []
        return groups.compactMap { group in
            let url = group.instanceURL ?? fallback
            return seen.insert(url).inserted ? url : nil
        }
    }

    /// The group IDs to ask each instance about. The home screen makes one request per instance,
    /// because `groups.list` can only answer for the server it was sent to.
    public func groupIDsByInstance(fallback: URL) -> [URL: [String]] {
        Dictionary(grouping: groups) { $0.instanceURL ?? fallback }
            .mapValues { $0.map(\.groupId) }
    }

    /// Writes an address onto every group that has none, so that changing which instance is the
    /// default can never silently move a group somewhere it isn't.
    ///
    /// Deliberately does not touch `updatedAt`: this is a device filling in what it already
    /// believed, not an edit. Stamping as an edit would let one phone's default overwrite the
    /// other's on a list they share, and neither of them is wrong.
    public func stampInstances(with url: URL) {
        var changed = false
        for index in groups.indices where groups[index].instanceURL == nil {
            groups[index].instanceURL = url
            changed = true
        }
        if changed { save() }
    }

    private func modify(_ groupId: String, _ change: (inout RecentGroup) -> Void) {
        guard let index = groups.firstIndex(where: { $0.groupId == groupId }) else { return }
        change(&groups[index])
        // Every edit is stamped, including the ones that leave the order alone: this is what
        // another device compares against, and an unstamped change is one it will discard.
        groups[index].updatedAt = .now
        save()
    }

    /// Brings in a list from somewhere else — the React Native app's — adding the groups this
    /// device doesn't have and leaving the ones it does exactly as they are.
    ///
    /// Adding rather than replacing, because iCloud may have got here first: a second phone
    /// updating from the old app can have a restored list *and* a legacy one, and they need not
    /// hold the same groups. Whichever way round, nothing already here is touched.
    ///
    /// The new rows go below everything already listed, and carry no `updatedAt`: a legacy list
    /// is the oldest information there is about a group, so it must never win a merge against a
    /// name or a star another device has since edited.
    public func addMissing(_ incoming: [RecentGroup]) {
        let known = Set(groups.map(\.groupId))
        let oldest = groups.compactMap(\.lastOpenedAt).min() ?? .now
        let missing = RecentGroupsSnapshot.stamped(
            incoming.filter { !known.contains($0.groupId) }, now: oldest
        )
        guard !missing.isEmpty else { return }
        groups += missing
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
        push()
    }

    // MARK: - iCloud

    /// Takes in what another device just wrote.
    ///
    /// Runs on a notification rather than on a schedule, so this is the same merge the launch
    /// does and nothing here decides *when* — only what the answer is once both sides are known.
    private func mergeFromCloud() {
        guard let cloud else { return }
        let merged = RecentGroupsSnapshot.merging(
            RecentGroupsSnapshot(groups: groups, deleted: deleted), Self.read(from: cloud)
        )
        guard merged != RecentGroupsSnapshot(groups: groups, deleted: deleted) else { return }
        groups = merged.groups
        deleted = merged.deleted
        save()
    }

    private func push() {
        guard let cloud else { return }
        let snapshot = RecentGroupsSnapshot(groups: groups, deleted: deleted)
        // A snapshot that won't encode is a snapshot not worth replacing a good one with —
        // leave whatever is up there alone rather than clearing the only copy that survives
        // this device.
        guard let data = try? JSONEncoder().encode(snapshot) else {
            assertionFailure("Couldn’t encode recent groups for iCloud")
            return
        }
        cloud.payload = data
    }

    private static func read(from cloud: any RecentGroupsCloudStorage) -> RecentGroupsSnapshot {
        // Anything unreadable is treated as an empty cloud, which merges to exactly what this
        // device already has. The alternative — throwing — would strand the local list behind
        // an error nobody can clear.
        guard let data = cloud.payload,
              let snapshot = try? JSONDecoder().decode(RecentGroupsSnapshot.self, from: data)
        else {
            return RecentGroupsSnapshot()
        }
        return snapshot
    }
}
