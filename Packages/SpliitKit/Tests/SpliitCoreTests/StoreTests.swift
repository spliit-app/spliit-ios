import Foundation
import SpliitAPI
import Testing

@testable import SpliitCore

@Suite("Settings")
struct SettingsStoreTests {

    private func makeDefaults() throws -> UserDefaults {
        let name = "settings-tests-\(UUID().uuidString)"
        return try #require(UserDefaults(suiteName: name))
    }

    @Test("A fresh install talks to the official instance")
    @MainActor
    func defaultsToOfficialInstance() throws {
        let settings = SettingsStore(defaults: try makeDefaults())

        #expect(settings.baseURL == SettingsStore.defaultBaseURL)
        #expect(settings.isUsingOfficialInstance)
    }

    @Test("A changed address survives a restart")
    @MainActor
    func persistsBaseURL() throws {
        let defaults = try makeDefaults()
        let settings = SettingsStore(defaults: defaults)

        settings.baseURL = try #require(URL(string: "https://home.example.com/spliit/"))

        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.baseURL.absoluteString == "https://home.example.com/spliit/")
        #expect(reloaded.isUsingOfficialInstance == false)
    }

    /// UI tests pass `-baseURL http://localhost:3009/` at launch; `UserDefaults` surfaces that
    /// through its argument domain, so the app needs no test-only code path.
    @Test("A launch argument overrides the stored address")
    @MainActor
    func launchArgumentWins() throws {
        let defaults = try makeDefaults()
        defaults.set("https://stored.example.com/", forKey: SettingsStore.Key.baseURL)

        // Simulates what the argument domain does to the same key.
        defaults.set("http://localhost:3009/", forKey: SettingsStore.Key.baseURL)

        #expect(SettingsStore(defaults: defaults).baseURL.absoluteString == "http://localhost:3009/")
    }

    @Test("A bare host is accepted and completed")
    func normalizesTypedAddresses() {
        #expect(SettingsStore.normalize("spliit.example.com")?.absoluteString == "https://spliit.example.com/")
        #expect(SettingsStore.normalize("https://spliit.example.com")?.absoluteString == "https://spliit.example.com/")
        #expect(SettingsStore.normalize("  https://spliit.example.com/  ")?.absoluteString == "https://spliit.example.com/")
        #expect(SettingsStore.normalize("http://localhost:3009")?.absoluteString == "http://localhost:3009/")
    }

    @Test("A subpath is preserved and given a trailing slash")
    func normalizesSubpaths() {
        #expect(SettingsStore.normalize("https://home.example.com/spliit")?.absoluteString == "https://home.example.com/spliit/")
    }

    @Test("Unusable input is rejected instead of producing a broken URL")
    func rejectsUnusableInput() {
        #expect(SettingsStore.normalize("") == nil)
        #expect(SettingsStore.normalize("   ") == nil)
        #expect(SettingsStore.normalize("https://") == nil)
    }
}

@Suite("Recent groups")
struct RecentGroupsStoreTests {

    @MainActor
    private func makeStore() -> RecentGroupsStore {
        let url = URL.temporaryDirectory
            .appending(path: "recent-\(UUID().uuidString)")
            .appending(path: "recent-groups.json")
        return RecentGroupsStore(fileURL: url)
    }

    @Test("A newly opened group goes to the front")
    @MainActor
    func remembersMostRecentFirst() {
        let store = makeStore()

        store.remember(RecentGroup(groupId: "a", groupName: "Lisbon"))
        store.remember(RecentGroup(groupId: "b", groupName: "Flat 3B"))

        #expect(store.groups.map(\.groupId) == ["b", "a"])
    }

    @Test("Reopening a group moves it up and refreshes its name")
    @MainActor
    func deduplicatesAndRenames() {
        let store = makeStore()

        store.remember(RecentGroup(groupId: "a", groupName: "Lisbon"))
        store.remember(RecentGroup(groupId: "b", groupName: "Flat 3B"))
        store.remember(RecentGroup(groupId: "a", groupName: "Weekend in Lisbon"))

        #expect(store.groups.count == 2)
        #expect(store.groups.first?.groupId == "a")
        #expect(store.groups.first?.groupName == "Weekend in Lisbon")
    }

    @Test("Removing a group only removes that one")
    @MainActor
    func forgetsOneGroup() {
        let store = makeStore()
        store.remember(RecentGroup(groupId: "a", groupName: "Lisbon"))
        store.remember(RecentGroup(groupId: "b", groupName: "Flat 3B"))

        store.forget(groupId: "a")

        #expect(store.groups.map(\.groupId) == ["b"])
    }

    @Test("The list survives a restart")
    @MainActor
    func persistsAcrossLaunches() {
        let url = URL.temporaryDirectory
            .appending(path: "recent-\(UUID().uuidString)")
            .appending(path: "recent-groups.json")

        let store = RecentGroupsStore(fileURL: url)
        store.remember(RecentGroup(groupId: "a", groupName: "Lisbon"))

        let reloaded = RecentGroupsStore(fileURL: url)
        #expect(reloaded.groups.map(\.groupName) == ["Lisbon"])
    }

    /// The legacy JSON uses the same key names, so a migrated list decodes without translation.
    @Test("The React Native JSON shape decodes directly")
    @MainActor
    func decodesLegacyShape() throws {
        let legacy = Data(#"[{"groupId":"abc","groupName":"Weekend in Lisbon"}]"#.utf8)

        let groups = try JSONDecoder().decode([RecentGroup].self, from: legacy)

        #expect(groups == [RecentGroup(groupId: "abc", groupName: "Weekend in Lisbon")])
    }

    @Test("Starred, recent and archived groups each land in one section")
    @MainActor
    func partitionsIntoSections() {
        let store = makeStore()
        store.remember(RecentGroup(groupId: "a", groupName: "Lisbon"))
        store.remember(RecentGroup(groupId: "b", groupName: "Flat 3B"))
        store.remember(RecentGroup(groupId: "c", groupName: "Ski trip"))

        store.setStarred(true, groupId: "b")
        store.setArchived(true, groupId: "a")

        #expect(store.starred.map(\.groupId) == ["b"])
        #expect(store.recent.map(\.groupId) == ["c"])
        #expect(store.archived.map(\.groupId) == ["a"])
    }

    /// Within a section the list keeps its own order, so the most recently opened starred group
    /// is still the first one under Starred.
    @Test("A section keeps the list's order")
    @MainActor
    func sectionsKeepRecencyOrder() {
        let store = makeStore()
        store.remember(RecentGroup(groupId: "a", groupName: "Lisbon"))
        store.remember(RecentGroup(groupId: "b", groupName: "Flat 3B"))

        store.setStarred(true, groupId: "a")
        store.setStarred(true, groupId: "b")

        #expect(store.starred.map(\.groupId) == ["b", "a"])
    }

    @Test("Starring an archived group brings it back, and archiving a starred one puts it away")
    @MainActor
    func starringAndArchivingAreExclusive() {
        let store = makeStore()
        store.remember(RecentGroup(groupId: "a", groupName: "Lisbon"))

        store.setArchived(true, groupId: "a")
        store.setStarred(true, groupId: "a")

        #expect(store.starred.map(\.groupId) == ["a"])
        #expect(store.archived.isEmpty)

        store.setArchived(true, groupId: "a")

        #expect(store.archived.map(\.groupId) == ["a"])
        #expect(store.starred.isEmpty)
    }

    /// Renaming a group rebuilds it from what the server just returned, which knows nothing
    /// about stars — so this is the path that would silently drop one.
    @Test("Reopening or renaming a group keeps its star")
    @MainActor
    func rememberPreservesFlags() {
        let store = makeStore()
        store.remember(RecentGroup(groupId: "a", groupName: "Lisbon"))
        store.setStarred(true, groupId: "a")

        store.remember(RecentGroup(groupId: "a", groupName: "Weekend in Lisbon"))

        #expect(store.starred.map(\.groupName) == ["Weekend in Lisbon"])
    }

    @Test("Opening an archived group doesn't un-archive it")
    @MainActor
    func openingKeepsAGroupArchived() {
        let store = makeStore()
        store.remember(RecentGroup(groupId: "a", groupName: "Lisbon"))
        store.setArchived(true, groupId: "a")

        store.remember(RecentGroup(groupId: "a", groupName: "Lisbon"))

        #expect(store.archived.map(\.groupId) == ["a"])
    }

    @Test("Stars survive a restart")
    @MainActor
    func persistsFlagsAcrossLaunches() {
        let url = URL.temporaryDirectory
            .appending(path: "recent-\(UUID().uuidString)")
            .appending(path: "recent-groups.json")

        let store = RecentGroupsStore(fileURL: url)
        store.remember(RecentGroup(groupId: "a", groupName: "Lisbon"))
        store.remember(RecentGroup(groupId: "b", groupName: "Flat 3B"))
        store.setStarred(true, groupId: "a")
        store.setArchived(true, groupId: "b")

        let reloaded = RecentGroupsStore(fileURL: url)
        #expect(reloaded.starred.map(\.groupId) == ["a"])
        #expect(reloaded.archived.map(\.groupId) == ["b"])
    }

    /// Every list written before this release, and everything the React Native app wrote, has
    /// neither flag. Decoding has to treat that as "not starred", not as a corrupt file.
    @Test("A list saved before starring existed still decodes")
    @MainActor
    func decodesGroupsWithoutFlags() throws {
        let stored = Data(#"[{"groupId":"abc","groupName":"Weekend in Lisbon"}]"#.utf8)

        let groups = try JSONDecoder().decode([RecentGroup].self, from: stored)

        #expect(groups.first?.isStarred == false)
        #expect(groups.first?.isArchived == false)
    }

    @Test("Setting a flag on a group that isn't listed does nothing")
    @MainActor
    func ignoresUnknownGroups() {
        let store = makeStore()
        store.remember(RecentGroup(groupId: "a", groupName: "Lisbon"))

        store.setStarred(true, groupId: "not-in-the-list")

        #expect(store.groups.count == 1)
        #expect(store.starred.isEmpty)
    }

    // MARK: - Who you are

    @Test("Who you are is remembered per group, not per phone")
    @MainActor
    func remembersWhoYouArePerGroup() {
        let store = makeStore()
        store.remember(RecentGroup(groupId: "a", groupName: "Lisbon"))
        store.remember(RecentGroup(groupId: "b", groupName: "Flat 3B"))

        store.setActiveParticipant(.participant("ana"), groupId: "a")

        #expect(store.activeParticipant(inGroup: "a") == .participant("ana"))
        #expect(store.activeParticipant(inGroup: "b") == nil)
    }

    /// "Nobody" is an answer to the question, and the whole point of storing it is that the
    /// group stops asking. It must not read back as an unanswered question.
    @Test("Nobody is an answer, and it is not the same as never having been asked")
    @MainActor
    func nobodyIsAnAnswer() {
        let store = makeStore()
        store.remember(RecentGroup(groupId: "a", groupName: "Lisbon"))

        store.setActiveParticipant(.nobody, groupId: "a")

        #expect(store.activeParticipant(inGroup: "a") == .nobody)
        #expect(store.activeParticipant(inGroup: "a") != nil)
    }

    /// Renaming rebuilds the group from what the server just returned, which knows nothing
    /// about who is holding the phone.
    @Test("Renaming a group doesn’t make you a stranger in it")
    @MainActor
    func rememberPreservesWhoYouAre() {
        let store = makeStore()
        store.remember(RecentGroup(groupId: "a", groupName: "Lisbon"))
        store.setActiveParticipant(.participant("ana"), groupId: "a")

        store.remember(RecentGroup(groupId: "a", groupName: "Weekend in Lisbon"))

        #expect(store.activeParticipant(inGroup: "a") == .participant("ana"))
    }

    @Test("Who you are survives a restart, nobody included")
    @MainActor
    func persistsWhoYouAreAcrossLaunches() {
        let url = URL.temporaryDirectory
            .appending(path: "recent-\(UUID().uuidString)")
            .appending(path: "recent-groups.json")

        let store = RecentGroupsStore(fileURL: url)
        store.remember(RecentGroup(groupId: "a", groupName: "Lisbon"))
        store.remember(RecentGroup(groupId: "b", groupName: "Flat 3B"))
        store.setActiveParticipant(.participant("ana"), groupId: "a")
        store.setActiveParticipant(.nobody, groupId: "b")

        let reloaded = RecentGroupsStore(fileURL: url)
        #expect(reloaded.activeParticipant(inGroup: "a") == .participant("ana"))
        #expect(reloaded.activeParticipant(inGroup: "b") == .nobody)
    }

    /// The participant ID goes on the wire as a bare string so the file stays readable — and so
    /// a UI test can seed one without knowing anything about how the enum is shaped.
    @Test("A stored answer is a plain string in the file")
    @MainActor
    func encodesAsAPlainString() throws {
        let groups = [
            RecentGroup(groupId: "a", groupName: "Lisbon", activeParticipant: .participant("ana")),
            RecentGroup(groupId: "b", groupName: "Flat 3B", activeParticipant: .nobody),
            RecentGroup(groupId: "c", groupName: "Ski trip"),
        ]

        let encoded = String(decoding: try JSONEncoder().encode(groups), as: UTF8.self)

        #expect(encoded.contains(#""activeParticipant":"ana""#))
        #expect(encoded.contains(#""activeParticipant":"""#))
        // Never asked is the absence of the key, not an empty answer to it.
        #expect(try JSONDecoder().decode([RecentGroup].self, from: Data(encoded.utf8)) == groups)
    }

    @Test("A list saved before this existed still decodes")
    @MainActor
    func decodesGroupsWithoutAnActiveParticipant() throws {
        let stored = Data(#"[{"groupId":"abc","groupName":"Weekend in Lisbon"}]"#.utf8)

        let groups = try JSONDecoder().decode([RecentGroup].self, from: stored)

        #expect(groups.first?.activeParticipant == nil)
    }

    @Test("A migrated list replaces whatever was there")
    @MainActor
    func replacesAll() {
        let store = makeStore()
        store.remember(RecentGroup(groupId: "old", groupName: "Old"))

        store.replaceAll(with: [
            RecentGroup(groupId: "a", groupName: "Lisbon"),
            RecentGroup(groupId: "b", groupName: "Flat 3B"),
        ])

        #expect(store.groups.map(\.groupId) == ["a", "b"])
    }
}

@Suite("Who you are, read against a group")
struct ActiveParticipantTests {

    private let participants = [
        Participant(id: "ana", name: "Ana"),
        Participant(id: "bruno", name: "Bruno"),
    ]

    @Test("A participant the group still has resolves to themselves")
    func resolvesAKnownParticipant() {
        #expect(
            ActiveParticipant.resolve(.participant("ana"), in: participants)
                == .participant("ana")
        )
    }

    /// Someone removed from the group leaves an ID pointing at nobody. Reading that as an
    /// unanswered question is what puts the invitation back on screen; reading it as an answer
    /// would leave a balance nobody can see and no way to ask for a different one.
    @Test("A participant who has left the group reads as an unanswered question")
    func forgetsARemovedParticipant() {
        #expect(ActiveParticipant.resolve(.participant("chloe"), in: participants) == nil)
    }

    @Test("Nobody survives whoever is in the group")
    func keepsNobody() {
        #expect(ActiveParticipant.resolve(.nobody, in: participants) == .nobody)
        #expect(ActiveParticipant.resolve(.nobody, in: []) == .nobody)
    }

    @Test("Never asked stays never asked")
    func keepsUnanswered() {
        #expect(ActiveParticipant.resolve(nil, in: participants) == nil)
    }
}
