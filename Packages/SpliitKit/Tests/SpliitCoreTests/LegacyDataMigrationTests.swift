import Foundation
import Testing

@testable import SpliitCore

/// The migration runs once, unattended, on the first launch after the App Store update. A
/// group is only reachable by its ID, so anything lost here is lost for good — these tests
/// exist mainly to prove that bad input degrades instead of throwing away good input.
@Suite("Migrating from the React Native app")
struct LegacyDataMigrationTests {

    @Test("Recent groups and a self-hosted address both come across")
    func migratesBothKeys() throws {
        let store = try LegacyStoreBuilder()
        try store.write([
            "recent-groups": """
                [{"groupId":"abc","groupName":"Weekend in Lisbon"},\
                {"groupId":"def","groupName":"Flat 3B"}]
                """,
            "spliit-settings": #"{"baseUrl":"https://spliit.example.com/"}"#,
        ])

        let result = LegacyDataMigration.read(from: store.storage)

        #expect(result.recentGroups.count == 2)
        #expect(result.recentGroups.first?.groupId == "abc")
        #expect(result.recentGroups.first?.groupName == "Weekend in Lisbon")
        #expect(result.baseURL?.absoluteString == "https://spliit.example.com/")
        #expect(result.problems.isEmpty)
        #expect(result.foundAnything)
    }

    @Test("A fresh install with no legacy store yields nothing and no complaints")
    func handlesFreshInstall() {
        let storage = LegacyAsyncStorage(
            directories: [URL.temporaryDirectory.appending(path: UUID().uuidString)]
        )

        let result = LegacyDataMigration.read(from: storage)

        #expect(result.recentGroups.isEmpty)
        #expect(result.baseURL == nil)
        #expect(result.problems.isEmpty)
        #expect(result.foundAnything == false)
    }

    @Test("Someone on the official instance has settings but no custom URL to carry over")
    func handlesDefaultSettings() throws {
        let store = try LegacyStoreBuilder()
        try store.write([
            "recent-groups": #"[{"groupId":"abc","groupName":"Trip"}]"#,
            "spliit-settings": #"{"baseUrl":"https://spliit.app/"}"#,
        ])

        let result = LegacyDataMigration.read(from: store.storage)

        #expect(result.baseURL?.absoluteString == "https://spliit.app/")
        #expect(result.recentGroups.count == 1)
    }

    /// The important half: a corrupt settings blob must not cost the user their group list.
    @Test("Corrupt settings are reported but the group list still comes across")
    func keepsGroupsWhenSettingsAreCorrupt() throws {
        let store = try LegacyStoreBuilder()
        try store.write([
            "recent-groups": #"[{"groupId":"abc","groupName":"Trip"}]"#,
            "spliit-settings": "{not json at all",
        ])

        let result = LegacyDataMigration.read(from: store.storage)

        #expect(result.recentGroups.count == 1)
        #expect(result.baseURL == nil)
        #expect(result.problems.count == 1)
        #expect(result.problems[0].contains("spliit-settings"))
    }

    @Test("A corrupt group list is reported rather than crashing")
    func reportsCorruptGroupList() throws {
        let store = try LegacyStoreBuilder()
        try store.write(["recent-groups": #"{"not":"an array"}"#])

        let result = LegacyDataMigration.read(from: store.storage)

        #expect(result.recentGroups.isEmpty)
        #expect(result.problems.count == 1)
        #expect(result.problems[0].contains("recent-groups"))
    }

    @Test("A settings blob with an unusable URL is reported, not silently accepted")
    func rejectsUnusableBaseURL() throws {
        let store = try LegacyStoreBuilder()
        try store.write(["spliit-settings": #"{"baseUrl":"   "}"#])

        let result = LegacyDataMigration.read(from: store.storage)

        #expect(result.baseURL == nil)
        #expect(result.problems.count == 1)
    }

    @Test("A long group list is migrated from its sidecar file intact")
    func migratesLongListFromSidecar() throws {
        let groups = (1...40).map {
            RecentGroup(groupId: "id-\($0)", groupName: "Group number \($0)")
        }
        let encoded = String(decoding: try JSONEncoder().encode(groups), as: UTF8.self)
        #expect(encoded.count > LegacyAsyncStorage.inlineValueLimit)

        let store = try LegacyStoreBuilder()
        try store.write(["recent-groups": encoded])

        let result = LegacyDataMigration.read(from: store.storage)

        #expect(result.recentGroups.count == 40)
        #expect(result.recentGroups.last?.groupName == "Group number 40")
    }
}
