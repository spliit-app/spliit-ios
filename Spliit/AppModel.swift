import Foundation
import Observation
import SpliitAPI
import SpliitCore

/// The composition root: the stores the app reads from, and the client it talks through.
@Observable
final class AppModel {

    let settings: SettingsStore
    let recentGroups: RecentGroupsStore

    /// What the first-launch migration found, kept for the settings screen and for logging.
    private(set) var migration: LegacyDataMigration.Result?

    private let defaults: UserDefaults

    private enum Key {
        static let didMigrate = "didMigrateFromReactNative"
    }

    init(
        defaults: UserDefaults = .standard,
        recentGroupsFileURL: URL = RecentGroupsStore.defaultFileURL()
    ) {
        self.defaults = defaults
        settings = SettingsStore(defaults: defaults)
        recentGroups = RecentGroupsStore(fileURL: recentGroupsFileURL)
    }

    /// A client for the currently configured instance. Cheap to build, so it is not cached —
    /// which also means changing the address in settings takes effect on the next call.
    var client: TRPCClient {
        TRPCClient(baseURL: settings.baseURL)
    }

    /// Brings the React Native app's data across, once, on the first launch after the update.
    ///
    /// Deliberately conservative: it never overwrites data this app already has, and it leaves
    /// the legacy files untouched so a later release can retry if something went wrong here.
    func migrateFromReactNativeIfNeeded() {
        guard !defaults.bool(forKey: Key.didMigrate) else { return }

        let storage = LegacyAsyncStorage.standardLocations(
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "app.spliit.spliitmobile"
        )
        let result = LegacyDataMigration.read(from: storage)

        if !result.recentGroups.isEmpty, recentGroups.groups.isEmpty {
            recentGroups.replaceAll(with: result.recentGroups)
        }
        if let baseURL = result.baseURL, settings.isUsingOfficialInstance {
            settings.baseURL = baseURL
        }

        defaults.set(true, forKey: Key.didMigrate)
        migration = result
    }
}
