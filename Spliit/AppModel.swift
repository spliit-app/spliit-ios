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

    /// Instances that have said they store no documents, for as long as the app is running.
    ///
    /// There is no way to ask: document storage is optional in Spliit, the route that signs an
    /// upload is compiled in whether or not a bucket is configured, and the flag saying so is a
    /// server-side one the tRPC API never exposes. So the answer only ever arrives as a failed
    /// upload — and remembering it is what stops the next expense offering the same dead end.
    ///
    /// Not persisted, deliberately. An instance that gains a bucket should start working again
    /// on the next launch rather than after somebody reinstalls the app.
    private var instancesWithoutDocumentStorage: Set<URL> = []

    /// Whether attaching a document to an expense is worth offering on this instance.
    var storesDocuments: Bool {
        !instancesWithoutDocumentStorage.contains(settings.baseURL)
    }

    func noteDocumentStorageIsUnavailable() {
        instancesWithoutDocumentStorage.insert(settings.baseURL)
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
