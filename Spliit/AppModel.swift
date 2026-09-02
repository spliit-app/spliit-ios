import Foundation
import Observation
import SpliitAPI
import SpliitCore

/// The composition root: the stores the app reads from, and the client it talks through.
@Observable
final class AppModel {

    let settings: SettingsStore
    let recentGroups: RecentGroupsStore
    let reviewPrompt: ReviewPromptStore

    /// What the first-launch migration found, kept for logging.
    private(set) var migration: LegacyDataMigration.Result?

    private let defaults: UserDefaults

    private enum Key {
        static let didMigrate = "didMigrateFromReactNative"
    }

    init(
        defaults: UserDefaults = .standard,
        recentGroupsFileURL: URL = RecentGroupsStore.defaultFileURL(),
        cloud: (any RecentGroupsCloudStorage)? = AppModel.cloudStorage()
    ) {
        self.defaults = defaults
        settings = SettingsStore(defaults: defaults)
        recentGroups = RecentGroupsStore(fileURL: recentGroupsFileURL, cloud: cloud)
        reviewPrompt = ReviewPromptStore(defaults: defaults)
    }

    /// Where the recent-groups list is mirrored, or nil to keep it on this device.
    ///
    /// A UI test gets nil: it seeds the list it wants and asserts on what it seeded, and a
    /// simulator signed into somebody's iCloud account would otherwise hand it a second list
    /// nobody asked for.
    static func cloudStorage() -> (any RecentGroupsCloudStorage)? {
        #if DEBUG
        if UITestSupport.isRunningUITests { return nil }
        #endif
        return UbiquitousRecentGroupsCloudStorage()
    }

    /// The instance a group is on: the address stored with it, or the default for a group that
    /// has not been told one — a list restored from an older version, or seeded by a test.
    func instanceURL(forGroup groupID: String) -> URL {
        recentGroups.instanceURL(forGroup: groupID) ?? settings.defaultInstanceURL
    }

    /// A client for the instance a group is on. Cheap to build, so it is not cached — and there
    /// is deliberately no client for "the app", because every request belongs to a group and
    /// sending one to the wrong server is a group that appears not to exist.
    func client(forGroup groupID: String) -> TRPCClient {
        client(on: instanceURL(forGroup: groupID))
    }

    /// A client for an instance named directly: a group being created, or one being added from a
    /// pasted link, neither of which is in the list yet.
    func client(on instanceURL: URL) -> TRPCClient {
        TRPCClient(baseURL: instanceURL)
    }

    /// Remembers where the last group was deliberately created, so the form opens there next
    /// time. Only the create form calls this: adding a group somebody else made says nothing
    /// about where this person makes theirs.
    func noteInstanceUsedForNewGroup(_ url: URL) {
        settings.defaultInstanceURL = url
    }

    /// The instances worth offering in the create form: everywhere this list already has a group,
    /// the default, and spliit.app — which is where most people are, whatever else is here.
    var knownInstances: [URL] {
        var seen: Set<URL> = []
        return ([settings.defaultInstanceURL]
            + recentGroups.instancesInUse(fallback: settings.defaultInstanceURL)
            + [SettingsStore.officialInstanceURL])
            .filter { seen.insert($0).inserted }
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

    /// Whether attaching a document to an expense is worth offering on this instance. Asked per
    /// instance, because one of the servers in the list can have a bucket while another has not.
    func storesDocuments(on instanceURL: URL) -> Bool {
        !instancesWithoutDocumentStorage.contains(instanceURL)
    }

    func noteDocumentStorageIsUnavailable(on instanceURL: URL) {
        instancesWithoutDocumentStorage.insert(instanceURL)
    }

    /// Everything that has to happen once, before the first screen reads a store.
    func prepare() {
        migrateFromReactNativeIfNeeded()
        // After the migration, which is what can still change the default: a list brought over
        // from the React Native app is a list of groups on whatever instance *it* was pointed at.
        recentGroups.stampInstances(with: settings.defaultInstanceURL)
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

        // Not "only when the list is empty" any more: iCloud may have restored a list from
        // another phone before this ran, and the legacy one can hold groups it doesn't.
        // `addMissing` leaves everything already here alone, which is the same promise.
        if !result.recentGroups.isEmpty {
            recentGroups.addMissing(result.recentGroups)
        }
        if let baseURL = result.baseURL, settings.isUsingOfficialInstance {
            settings.defaultInstanceURL = baseURL
        }

        defaults.set(true, forKey: Key.didMigrate)
        migration = result
    }
}
