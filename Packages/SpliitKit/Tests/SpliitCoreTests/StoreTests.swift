import Foundation
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
