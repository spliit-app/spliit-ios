#if DEBUG
import Foundation
import SpliitCore

/// Test-only hooks, compiled out of release builds.
///
/// UI tests need to control what the app starts from: an empty list, a seeded one, or — for
/// the upgrade test — a planted React Native store to migrate. Everything is driven by launch
/// arguments so the app itself has no idea it is under test.
///
/// The base URL needs nothing here: `-baseURL <value>` lands in `UserDefaults`' argument
/// domain on its own.
enum UITestSupport {

    enum Argument {
        /// Wipe local state so the run starts from a known-empty app.
        static let resetState = "-uiTestResetState"
        /// A JSON array of `{groupId, groupName}` to pre-populate recent groups with.
        static let seedRecentGroups = "-uiTestRecentGroups"
        /// A JSON object of AsyncStorage key/value pairs, written out in the legacy on-disk
        /// format so the real migration path runs against it.
        static let plantLegacyStore = "-uiTestLegacyStore"
    }

    static func applyLaunchArguments() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains(where: { $0.hasPrefix("-uiTest") }) else { return }

        if arguments.contains(Argument.resetState) {
            resetState()
        }
        if let json = value(for: Argument.plantLegacyStore, in: arguments) {
            plantLegacyStore(json)
        }
        if let json = value(for: Argument.seedRecentGroups, in: arguments) {
            seedRecentGroups(json)
        }
    }

    private static func value(for argument: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: argument),
              arguments.indices.contains(index + 1)
        else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func resetState() {
        let defaults = UserDefaults.standard
        for key in ["didMigrateFromReactNative", SettingsStore.Key.baseURL] {
            defaults.removeObject(forKey: key)
        }
        try? FileManager.default.removeItem(at: RecentGroupsStore.defaultFileURL())
        try? FileManager.default.removeItem(at: legacyStoreDirectory())
    }

    private static func seedRecentGroups(_ json: String) {
        guard let groups = try? JSONDecoder().decode([RecentGroup].self, from: Data(json.utf8))
        else {
            return
        }
        let url = RecentGroupsStore.defaultFileURL()
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? JSONEncoder().encode(groups).write(to: url)
    }

    /// Recreates the exact layout AsyncStorage would have left behind, including spilling
    /// values past 1024 characters into MD5-named sidecar files — the path a user with a long
    /// group list actually takes.
    private static func plantLegacyStore(_ json: String) {
        guard let values = try? JSONSerialization.jsonObject(with: Data(json.utf8))
            as? [String: String]
        else {
            return
        }

        let directory = legacyStoreDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var manifest: [String: Any] = [:]
        for (key, value) in values {
            if value.count <= 1024 {
                manifest[key] = value
            } else {
                manifest[key] = NSNull()
                try? Data(value.utf8).write(to: directory.appending(path: md5Hex(key)))
            }
        }
        try? JSONSerialization.data(withJSONObject: manifest)
            .write(to: directory.appending(path: "manifest.json"))
    }

    private static func legacyStoreDirectory() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        return base
            .appending(path: Bundle.main.bundleIdentifier ?? "app.spliit.spliitmobile")
            .appending(path: "RCTAsyncLocalStorage_V1")
    }

    private static func md5Hex(_ text: String) -> String {
        LegacyAsyncStorage.md5Hex(text)
    }
}
#endif
