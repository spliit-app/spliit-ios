import BackgroundTasks
import Foundation
import Observation
import SpliitAPI
import SpliitCore
import SwiftUI
import UserNotifications

/// Everything a notification needs that cannot live in a view: iOS's permission, the background
/// refresh that does the polling, and where a tap lands.
///
/// A shared instance, which the rest of the app deliberately is not — for the reason `Router`
/// gives. A background refresh is started by the system, against a process that may have been
/// launched for it alone with no window and no view hierarchy, so there is nobody to hand it
/// `AppModel`. It is given the two stores it needs at launch instead, and they are the same
/// instances the app is using.
@MainActor
@Observable
final class ActivityNotifications {

    static let shared = ActivityNotifications()

    /// Also listed in `project.yml` under `BGTaskSchedulerPermittedIdentifiers`. iOS refuses to
    /// register a task whose identifier is not declared there, and says so only at runtime.
    static let taskIdentifier = "app.spliit.spliitmobile.activity-refresh"

    /// The earliest a refresh is asked for. Only a floor: iOS decides when one actually runs,
    /// and with an app that is rarely opened it can be a great deal later than this. Both
    /// screens that offer the setting say as much.
    private static let refreshInterval: TimeInterval = 15 * 60

    /// What iOS currently allows, for the screens that offer to change it. `.notDetermined`
    /// until `refresh()` has been called once, which is what every one of them does on appear.
    private(set) var authorization: UNAuthorizationStatus = .notDetermined

    /// Whether iOS has actually been asked yet. `.notDetermined` is both the starting value and
    /// a real answer, so without this a screen would draw its "turn these on" row for a moment
    /// on every appearance, including for somebody who turned them on months ago.
    private(set) var hasCheckedAuthorization = false

    /// Whether anything at all can be delivered. False also covers the case where notifications
    /// were allowed once and turned off in iOS Settings since.
    var isAllowed: Bool {
        authorization == .authorized || authorization == .provisional
    }

    private var settings: SettingsStore?
    private var recentGroups: RecentGroupsStore?

    private let center = UNUserNotificationCenter.current()
    private let taps = NotificationTapHandler()

    private init() {}

    /// Called once at launch, before any window exists — a process resumed for a background
    /// refresh gets no further than this.
    func configure(settings: SettingsStore, recentGroups: RecentGroupsStore) {
        self.settings = settings
        self.recentGroups = recentGroups
        center.delegate = taps
    }

    // MARK: - Permission

    func refresh() async {
        authorization = await center.notificationSettings().authorizationStatus
        hasCheckedAuthorization = true
    }

    /// Asks iOS, but only the once it is willing to be asked.
    ///
    /// Called when somebody chooses a level other than "Nothing", and from the row a screen
    /// shows while nobody has been asked at all — asking at launch would spend the one prompt
    /// iOS allows on a person who has not yet seen what the app does. A refusal is not an error
    /// to report: the same row then shows the way to iOS Settings, which is the only place a
    /// refusal can be undone.
    func requestAuthorizationIfNeeded() async {
        await refresh()
        guard authorization == .notDetermined else { return }

        #if DEBUG
        // Below the refresh above, not above it: the hook is here to keep a Springboard alert —
        // which belongs to the system rather than to the app a UI test is driving, and blocks
        // every tap until somebody answers it — off the screen. What iOS currently allows is
        // still worth knowing under test, because it is what the screens draw from.
        guard UITestSupport.asksForNotificationPermission else { return }
        #endif

        // Badges are deliberately not asked for. Nothing in the app clears one, and a count that
        // only ever goes up is worse than no count.
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        await refresh()
    }

    // MARK: - Scheduling

    /// Asks for the next background refresh, or withdraws the request when there is nothing left
    /// to look for. Cheap and idempotent — submitting again replaces the pending request — so it
    /// is called on every change of mind as well as on the way into the background.
    ///
    /// It asks iOS what it allows rather than trusting what was last read, and that is the whole
    /// reason it is `async`. `authorization` starts at `.notDetermined`, which is also what a
    /// refusal looks like — so a process iOS launched into the background for a refresh, or one
    /// whose owner never opened either settings screen, would take its own starting value for an
    /// answer and cancel the request that keeps the chain alive.
    func scheduleNextRefresh() async {
        await refresh()

        guard isAllowed, anyGroupWantsNotifications else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
            return
        }

        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: Self.refreshInterval)
        // Throws on a simulator, which has no background scheduling at all, and when the device
        // is in Low Power Mode. Neither is worth a line in the log every fifteen minutes.
        try? BGTaskScheduler.shared.submit(request)
    }

    /// The background refresh itself. Re-arms first, so the chain survives whatever the work
    /// below runs into — a run that ends without submitting the next request is the last one
    /// that will ever happen.
    static func handleBackgroundRefresh() async {
        await shared.scheduleNextRefresh()
        await shared.run()
    }

    private func run() async {
        guard let settings, let recentGroups else { return }
        await ActivityNotifier(
            settings: settings,
            recentGroups: recentGroups,
            client: TRPCClient(baseURL: settings.baseURL)
        ).run()
    }

    /// Whether any group is still worth waking up for. An archived group is not: archiving is
    /// how a group is asked to stop asking for attention.
    private var anyGroupWantsNotifications: Bool {
        guard let settings, let recentGroups else { return false }
        return recentGroups.groups.contains { group in
            !group.isArchived && (group.notificationLevel ?? settings.notificationLevel) != .nothing
        }
    }

    /// What a screen calls after changing a level: ask for permission if this is the first time
    /// anybody has asked for anything, then re-arm or withdraw the refresh to match.
    func preferencesDidChange(wants: Bool) async {
        if wants { await requestAuthorizationIfNeeded() }
        await scheduleNextRefresh()
    }
}

/// Where a tapped notification goes.
///
/// `nonisolated` because `UNUserNotificationCenterDelegate` is, and because this has to be in
/// place before the app finishes launching: a tap on the lock screen starts the app *and*
/// delivers the response, and a delegate set later than that misses it.
///
/// It writes to the router rather than navigating, for the same reason an App Intent does — the
/// group list reads the destination whenever it next draws, which may be a moment later or after
/// a cold launch.
private nonisolated final class NotificationTapHandler: NSObject, UNUserNotificationCenterDelegate {

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let groupID = response.notification.request.content
            .userInfo[ActivityNotifier.groupIDKey] as? String
        guard let groupID else { return }
        await MainActor.run { Router.shared.go(to: .group(id: groupID)) }
    }
}
