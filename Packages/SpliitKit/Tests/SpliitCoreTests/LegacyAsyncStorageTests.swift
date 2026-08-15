import Foundation
import Testing

@testable import SpliitCore

/// Builds the on-disk layout `@react-native-async-storage/async-storage@1.23.1` writes, so the
/// reader is tested against the real format rather than against a convenient stand-in.
struct LegacyStoreBuilder {
    let directory: URL

    init() throws {
        directory = URL.temporaryDirectory
            .appending(path: "legacy-\(UUID().uuidString)")
            .appending(path: "RCTAsyncLocalStorage_V1")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Writes values the way AsyncStorage would: inline when short enough, otherwise `null` in
    /// the manifest plus a sidecar file named after the MD5 of the key.
    func write(_ values: [String: String]) throws {
        var manifest: [String: Any] = [:]
        for (key, value) in values {
            if value.count <= LegacyAsyncStorage.inlineValueLimit {
                manifest[key] = value
            } else {
                manifest[key] = NSNull()
                try Data(value.utf8).write(
                    to: directory.appending(path: LegacyAsyncStorage.md5Hex(key))
                )
            }
        }
        try JSONSerialization.data(withJSONObject: manifest).write(
            to: directory.appending(path: "manifest.json")
        )
    }

    var storage: LegacyAsyncStorage { LegacyAsyncStorage(directories: [directory]) }
}

@Suite("Reading the React Native store")
struct LegacyAsyncStorageTests {

    /// Cross-checked against `printf '%s' 'recent-groups' | md5`. If this ever changes, every
    /// upgrading user with a long group list silently loses it.
    @Test("Sidecar file names match AsyncStorage's MD5 naming")
    func matchesKnownKeyHashes() {
        #expect(LegacyAsyncStorage.md5Hex("recent-groups") == "1cbcb324ae1107e8720de37fcf7616c1")
        #expect(LegacyAsyncStorage.md5Hex("spliit-settings") == "2109ef73d295fd69ac535e9f1380245a")
    }

    @Test("A short value is read from the manifest itself")
    func readsInlineValue() throws {
        let store = try LegacyStoreBuilder()
        try store.write(["spliit-settings": #"{"baseUrl":"https://spliit.example.com/"}"#])

        #expect(
            store.storage.value(forKey: "spliit-settings")
                == #"{"baseUrl":"https://spliit.example.com/"}"#
        )
    }

    /// Roughly fifteen recent groups push the value past the 1024-character inline limit, so
    /// this is the path a heavy user actually takes — not an edge case.
    @Test("A value over 1024 characters is read from its sidecar file")
    func readsSidecarValue() throws {
        let groups = (1...40).map {
            RecentGroup(groupId: "group-id-number-\($0)", groupName: "Trip number \($0)")
        }
        let encoded = String(decoding: try JSONEncoder().encode(groups), as: UTF8.self)
        #expect(encoded.count > LegacyAsyncStorage.inlineValueLimit)

        let store = try LegacyStoreBuilder()
        try store.write(["recent-groups": encoded])

        // The manifest must hold null for this key, not the value.
        let manifest = try JSONSerialization.jsonObject(
            with: Data(contentsOf: store.directory.appending(path: "manifest.json"))
        ) as? [String: Any]
        #expect(manifest?["recent-groups"] is NSNull)

        #expect(store.storage.value(forKey: "recent-groups") == encoded)
    }

    @Test("An absent key reads as nil")
    func returnsNilForMissingKey() throws {
        let store = try LegacyStoreBuilder()
        try store.write(["something-else": "value"])

        #expect(store.storage.value(forKey: "recent-groups") == nil)
    }

    @Test("A missing store reads as nil rather than failing")
    func toleratesMissingStore() {
        let storage = LegacyAsyncStorage(
            directories: [URL.temporaryDirectory.appending(path: "definitely-not-here")]
        )

        #expect(storage.value(forKey: "recent-groups") == nil)
    }

    @Test("A sidecar file that went missing reads as nil rather than failing")
    func toleratesMissingSidecar() throws {
        let store = try LegacyStoreBuilder()
        let manifest = ["recent-groups": NSNull()]
        try JSONSerialization.data(withJSONObject: manifest).write(
            to: store.directory.appending(path: "manifest.json")
        )

        #expect(store.storage.value(forKey: "recent-groups") == nil)
    }

    @Test("Locations are probed in order, newest convention first")
    func prefersTheFirstLocationThatHasTheKey() throws {
        let old = try LegacyStoreBuilder()
        try old.write(["recent-groups": "[]"])
        let current = try LegacyStoreBuilder()
        try current.write([
            "recent-groups": #"[{"groupId":"a","groupName":"Current"}]"#
        ])

        let storage = LegacyAsyncStorage(directories: [current.directory, old.directory])

        #expect(storage.value(forKey: "recent-groups")?.contains("Current") == true)
    }
}
