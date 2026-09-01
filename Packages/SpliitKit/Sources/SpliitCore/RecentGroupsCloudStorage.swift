import Foundation

/// The one value `RecentGroupsStore` keeps in the cloud, and the two things it needs to do with
/// it. A protocol rather than `NSUbiquitousKeyValueStore` directly so the merge — the half that
/// can actually be wrong — is testable on a host with no iCloud account and no entitlement.
@MainActor
public protocol RecentGroupsCloudStorage: AnyObject {
    /// The stored snapshot, or nil when this device has never seen one.
    var payload: Data? { get set }

    /// Installs the handler to run when *another* device writes. Called once, by the store.
    func observeExternalChanges(_ handler: @escaping @MainActor () -> Void)
}

/// The recent-groups list in iCloud's key-value store.
///
/// Key-value rather than CloudKit because of what this list is: a few dozen short rows, no
/// schema to migrate, no conflict a person would want to be asked about, and — crucially — no
/// account. Spliit has no sign-in, so the only thing that can carry a group ID from an old
/// phone to a new one is the iCloud account the phone is already signed into.
/// `NSUbiquitousKeyValueStore` restores with the device backup and syncs without asking the
/// user for anything.
///
/// Everything here degrades to nothing rather than to an error. A device signed out of iCloud
/// reads nil and writes into a local cache nobody collects, which is exactly the behaviour the
/// app had before this existed.
@MainActor
public final class UbiquitousRecentGroupsCloudStorage: RecentGroupsCloudStorage {

    /// One key for the whole list. The 1 MB per-key limit is thousands of groups away, and a
    /// key per group would spend the 1,024-key budget on something no reader wants separately.
    private nonisolated static let key = "recentGroups"

    private let store: NSUbiquitousKeyValueStore
    private var observer: (any NSObjectProtocol)?

    public init(store: NSUbiquitousKeyValueStore = .default) {
        self.store = store
        // Apple's own advice: pull whatever the daemon already has before the first read, so a
        // fresh launch on a restored device doesn't start from an empty list and then jump.
        store.synchronize()
    }

    /// Isolated so it can reach the token at all: a block observer is an Objective-C object,
    /// which is not `Sendable`, so a plain `deinit` isn't allowed to look at one.
    isolated deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    public var payload: Data? {
        get { store.data(forKey: Self.key) }
        set {
            store.set(newValue, forKey: Self.key)
            // Flushes to the on-disk cache and schedules the upload. Without it the write only
            // reaches iCloud at the system's leisure, which for a list whose whole job is to
            // outlive this device is too late.
            store.synchronize()
        }
    }

    public func observeExternalChanges(_ handler: @escaping @MainActor () -> Void) {
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { notification in
            // The notification also fires for a quota violation and for the first download of
            // an account, and it names the keys that moved. Anything that didn't touch ours is
            // not our business — but a change with no key list at all is, since that is what
            // an account switch looks like.
            let changed = notification.userInfo?[
                NSUbiquitousKeyValueStoreChangedKeysKey
            ] as? [String]
            guard changed == nil || changed?.contains(Self.key) == true else { return }
            MainActor.assumeIsolated { handler() }
        }
    }
}
