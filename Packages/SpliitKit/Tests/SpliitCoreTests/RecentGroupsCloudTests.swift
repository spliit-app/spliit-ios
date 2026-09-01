import Foundation
import Testing

@testable import SpliitCore

/// One device's copy of iCloud's key-value store.
///
/// Each device gets its own, because that is what the real thing is: a local cache that the
/// daemon fills in. Handing two stores the same object would test a shared variable rather than
/// two phones that hear about each other late.
@MainActor
private final class FakeCloud: RecentGroupsCloudStorage {
    var payload: Data?
    private var handler: (@MainActor () -> Void)?

    init(payload: Data? = nil) {
        self.payload = payload
    }

    func observeExternalChanges(_ handler: @escaping @MainActor () -> Void) {
        self.handler = handler
    }

    /// Another device's write, arriving.
    func receive(from other: FakeCloud) {
        payload = other.payload
        handler?()
    }
}

@MainActor
private func makeFileURL() -> URL {
    URL.temporaryDirectory
        .appending(path: "recent-\(UUID().uuidString)")
        .appending(path: "recent-groups.json")
}

@MainActor
private func snapshot(in cloud: FakeCloud) throws -> RecentGroupsSnapshot {
    try JSONDecoder().decode(RecentGroupsSnapshot.self, from: #require(cloud.payload))
}

@MainActor
private func cloudHolding(_ groups: [RecentGroup]) throws -> FakeCloud {
    FakeCloud(payload: try JSONEncoder().encode(RecentGroupsSnapshot(groups: groups)))
}

@Suite("Recent groups in iCloud")
struct RecentGroupsCloudTests {

    @Test("A new phone starts from the list the old one left in iCloud")
    @MainActor
    func restoresOntoAnEmptyDevice() throws {
        let cloud = try cloudHolding([
            RecentGroup(groupId: "a", groupName: "Lisbon", updatedAt: .now, lastOpenedAt: .now),
        ])

        let store = RecentGroupsStore(fileURL: makeFileURL(), cloud: cloud)

        #expect(store.groups.map(\.groupName) == ["Lisbon"])
    }

    @Test("What iCloud restores is written to this device too")
    @MainActor
    func restoredListIsAlsoOnDisk() throws {
        let url = makeFileURL()
        let cloud = try cloudHolding([
            RecentGroup(groupId: "a", groupName: "Lisbon", updatedAt: .now, lastOpenedAt: .now),
        ])

        _ = RecentGroupsStore(fileURL: url, cloud: cloud)

        // The App Intents read the file rather than the store, and so does the next launch if
        // iCloud is unreachable by then.
        let offline = RecentGroupsStore(fileURL: url)
        #expect(offline.groups.map(\.groupName) == ["Lisbon"])
    }

    @Test("A list that predates iCloud is sent up on the first launch that can")
    @MainActor
    func uploadsAnExistingList() throws {
        let url = makeFileURL()
        let existing = RecentGroupsStore(fileURL: url)
        existing.remember(RecentGroup(groupId: "a", groupName: "Lisbon"))

        let cloud = FakeCloud()
        _ = RecentGroupsStore(fileURL: url, cloud: cloud)

        #expect(try snapshot(in: cloud).groups.map(\.groupName) == ["Lisbon"])
    }

    @Test("Who you are in a group travels with it")
    @MainActor
    func activeParticipantSyncs() throws {
        let cloud = FakeCloud()
        let store = RecentGroupsStore(fileURL: makeFileURL(), cloud: cloud)
        store.remember(RecentGroup(groupId: "a", groupName: "Lisbon"))
        store.setActiveParticipant(.participant("ana"), groupId: "a")

        let arrived = RecentGroupsStore(fileURL: makeFileURL(), cloud: cloud)

        #expect(arrived.activeParticipant(inGroup: "a") == .participant("ana"))
    }

    @Test("Nobody travels too, and stays an answer rather than a question")
    @MainActor
    func nobodySyncs() throws {
        let cloud = FakeCloud()
        let store = RecentGroupsStore(fileURL: makeFileURL(), cloud: cloud)
        store.remember(RecentGroup(groupId: "a", groupName: "Lisbon"))
        store.setActiveParticipant(.nobody, groupId: "a")

        let arrived = RecentGroupsStore(fileURL: makeFileURL(), cloud: cloud)

        #expect(arrived.activeParticipant(inGroup: "a") == .nobody)
    }

    @Test("Stars and archives travel")
    @MainActor
    func flagsSync() throws {
        let cloud = FakeCloud()
        let store = RecentGroupsStore(fileURL: makeFileURL(), cloud: cloud)
        store.remember(RecentGroup(groupId: "a", groupName: "Lisbon"))
        store.remember(RecentGroup(groupId: "b", groupName: "Ski trip"))
        store.setStarred(true, groupId: "a")
        store.setArchived(true, groupId: "b")

        let arrived = RecentGroupsStore(fileURL: makeFileURL(), cloud: cloud)

        #expect(arrived.starred.map(\.groupId) == ["a"])
        #expect(arrived.archived.map(\.groupId) == ["b"])
    }

    @Test("Two phones that each know a group end up knowing both")
    @MainActor
    func mergeKeepsBothSides() {
        let (phone, cloud) = twoPhones()
        phone.first.remember(RecentGroup(groupId: "a", groupName: "Lisbon"))
        phone.second.remember(RecentGroup(groupId: "b", groupName: "Flat 3B"))

        cloud.second.receive(from: cloud.first)

        #expect(Set(phone.second.groups.map(\.groupId)) == ["a", "b"])
    }

    @Test("A group opened while the other phone was renaming it keeps the newer name")
    @MainActor
    func latestEditWins() {
        let (phone, cloud) = twoPhones()
        phone.first.remember(RecentGroup(groupId: "a", groupName: "Lisbon"))
        cloud.second.receive(from: cloud.first)

        phone.second.remember(RecentGroup(groupId: "a", groupName: "Weekend in Lisbon"))
        cloud.first.receive(from: cloud.second)

        #expect(phone.first.groups.map(\.groupName) == ["Weekend in Lisbon"])
    }

    @Test("A group removed on one phone goes away on the other")
    @MainActor
    func deletionTravels() {
        let (phone, cloud) = twoPhones()
        phone.first.remember(RecentGroup(groupId: "a", groupName: "Lisbon"))
        phone.first.remember(RecentGroup(groupId: "b", groupName: "Flat 3B"))
        cloud.second.receive(from: cloud.first)

        phone.first.forget(groupId: "a")
        cloud.second.receive(from: cloud.first)

        #expect(phone.second.groups.map(\.groupId) == ["b"])
    }

    /// The reason tombstones exist at all: a merge that only ever adds is a merge in which
    /// nobody can delete anything, because the other phone puts it straight back.
    @Test("And it doesn’t come back when that phone answers")
    @MainActor
    func deletionIsNotResurrected() {
        let (phone, cloud) = twoPhones()
        phone.first.remember(RecentGroup(groupId: "a", groupName: "Lisbon"))
        cloud.second.receive(from: cloud.first)

        phone.first.forget(groupId: "a")
        cloud.second.receive(from: cloud.first)
        cloud.first.receive(from: cloud.second)

        #expect(phone.first.groups.isEmpty)
        #expect(phone.second.groups.isEmpty)
    }

    @Test("Opening a group again outranks having deleted it earlier")
    @MainActor
    func reopeningBeatsAnEarlierDeletion() {
        let (phone, cloud) = twoPhones()
        phone.first.remember(RecentGroup(groupId: "a", groupName: "Lisbon"))
        cloud.second.receive(from: cloud.first)
        phone.first.forget(groupId: "a")

        // Someone opens the shared link again on the other phone, which hasn't heard yet.
        phone.second.remember(RecentGroup(groupId: "a", groupName: "Lisbon"))
        cloud.first.receive(from: cloud.second)

        #expect(phone.first.groups.map(\.groupId) == ["a"])
    }

    @Test("A phone that has been in a drawer for a season is not told about old deletions")
    @MainActor
    func tombstonesExpire() {
        let longAgo = Date.now.addingTimeInterval(-100 * 24 * 60 * 60)
        let mine = RecentGroupsSnapshot(groups: [], deleted: ["a": longAgo])
        let theirs = RecentGroupsSnapshot(
            groups: [RecentGroup(groupId: "a", groupName: "Lisbon", lastOpenedAt: longAgo)]
        )

        let merged = RecentGroupsSnapshot.merging(mine, theirs)

        #expect(merged.deleted.isEmpty)
        #expect(merged.groups.map(\.groupId) == ["a"])
    }

    @Test("A merged list is still most recently opened first")
    @MainActor
    func mergeKeepsRecencyOrder() {
        let (phone, cloud) = twoPhones()
        phone.first.remember(RecentGroup(groupId: "a", groupName: "Lisbon"))
        phone.second.remember(RecentGroup(groupId: "b", groupName: "Flat 3B"))

        cloud.first.receive(from: cloud.second)

        #expect(phone.first.groups.map(\.groupId) == ["b", "a"])
    }

    /// A list written before any of this carries no times at all, and the order it is in is the
    /// only record of when anything was opened. Losing that would reshuffle the home screen of
    /// everyone who upgrades.
    @Test("A list saved before timestamps existed keeps its order through the first merge")
    @MainActor
    func legacyOrderSurvivesTheFirstMerge() throws {
        let url = makeFileURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(
            #"[{"groupId":"a","groupName":"Lisbon"},{"groupId":"b","groupName":"Flat 3B"}]"#.utf8
        ).write(to: url)

        let store = RecentGroupsStore(fileURL: url, cloud: FakeCloud())

        #expect(store.groups.map(\.groupId) == ["a", "b"])
    }

    @Test("A cloud copy that can’t be read leaves the list on this phone alone")
    @MainActor
    func unreadableCloudIsIgnored() throws {
        let url = makeFileURL()
        let existing = RecentGroupsStore(fileURL: url)
        existing.remember(RecentGroup(groupId: "a", groupName: "Lisbon"))

        let cloud = FakeCloud(payload: Data("not a snapshot".utf8))
        let store = RecentGroupsStore(fileURL: url, cloud: cloud)

        #expect(store.groups.map(\.groupId) == ["a"])
        // And the unreadable copy is replaced rather than left for the next launch to trip on.
        #expect(try snapshot(in: cloud).groups.map(\.groupId) == ["a"])
    }

    /// Two phones ran the old app, with two different lists and no sync between them. The
    /// second one to be updated finds iCloud already holding the first one's groups, and its own
    /// React Native data still on disk — and must end up with both.
    @Test("A second phone updating from the old app keeps its own groups as well")
    @MainActor
    func migrationAddsToARestoredList() throws {
        let cloud = try cloudHolding([
            RecentGroup(groupId: "a", groupName: "Lisbon", updatedAt: .now, lastOpenedAt: .now),
        ])
        let store = RecentGroupsStore(fileURL: makeFileURL(), cloud: cloud)

        store.addMissing([RecentGroup(groupId: "b", groupName: "Flat 3B")])

        #expect(store.groups.map(\.groupId) == ["a", "b"])
        #expect(try snapshot(in: cloud).groups.map(\.groupId) == ["a", "b"])
    }

    @Test("With no iCloud to write to, the list behaves exactly as it did before")
    @MainActor
    func staysLocalWithoutCloud() {
        let url = makeFileURL()
        let store = RecentGroupsStore(fileURL: url)
        store.remember(RecentGroup(groupId: "a", groupName: "Lisbon"))
        store.forget(groupId: "a")
        store.remember(RecentGroup(groupId: "b", groupName: "Flat 3B"))

        #expect(RecentGroupsStore(fileURL: url).groups.map(\.groupId) == ["b"])
    }

    /// Two phones signed into the same account, each with its own local cache of the same key.
    private typealias Phones = (first: RecentGroupsStore, second: RecentGroupsStore)
    private typealias Clouds = (first: FakeCloud, second: FakeCloud)

    @MainActor
    private func twoPhones() -> (Phones, Clouds) {
        let clouds = (first: FakeCloud(), second: FakeCloud())
        return (
            (
                first: RecentGroupsStore(fileURL: makeFileURL(), cloud: clouds.first),
                second: RecentGroupsStore(fileURL: makeFileURL(), cloud: clouds.second)
            ),
            clouds
        )
    }
}
