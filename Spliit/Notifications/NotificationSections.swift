import SpliitAPI
import SpliitCore
import SwiftUI
import UIKit
import UserNotifications

extension NotificationLevel {
    /// What the level is called on screen. In the app's catalogue rather than the package's:
    /// these are the words on a control, not a rule the package enforces.
    var name: String {
        switch self {
        case .everything: String(localized: "Everything")
        case .involvingMe: String(localized: "Only what involves me")
        case .nothing: String(localized: "Nothing")
        }
    }
}

/// The app-wide default, on the settings sheet.
///
/// The default rather than a master switch: a group that has said what it wants keeps it, and
/// changing this moves only the groups that never said. That is what makes it possible to be
/// told everything about the trip you are on and nothing about the flatshare you left.
struct DefaultNotificationSection: View {

    @Environment(AppModel.self) private var app
    private var notifications: ActivityNotifications { .shared }

    /// The picker deals in optionals so that one control can serve both screens; here there is
    /// no default to fall back to, and the "Same as default" row that would produce nil is not
    /// offered, so the coalescing below never runs.
    private var level: Binding<NotificationLevel?> {
        Binding(
            get: { app.settings.notificationLevel },
            set: { app.settings.notificationLevel = $0 ?? SettingsStore.defaultNotificationLevel }
        )
    }

    var body: some View {
        Section {
            NotificationLevelPicker(
                selection: level,
                followsDefault: nil,
                identifier: AccessibilityID.Notifications.defaultLevel
            )
            NotificationPermissionRow(wants: app.settings.notificationLevel != .nothing)
        } header: {
            Text("Notifications")
        } footer: {
            Text("What a group tells you about when it hasn’t been given a setting of its own. Archived groups never do. Spliit checks for changes in the background, and iOS decides how often that happens — so a notification can arrive a while after what it describes.")
        }
        .onChange(of: app.settings.notificationLevel) { _, new in
            Task { await notifications.preferencesDidChange(wants: new != .nothing) }
        }
        .task { await notifications.refresh() }
    }
}

/// One group's own setting, on its information tab.
struct GroupNotificationSection: View {

    @Environment(AppModel.self) private var app
    let groupID: String
    /// The group's participants, which is what says whether "only what involves me" has anybody
    /// to match against.
    let participants: [Participant]

    private var notifications: ActivityNotifications { .shared }

    private var chosen: NotificationLevel? {
        app.recentGroups.notificationLevel(inGroup: groupID)
    }

    /// What this group will actually do — the app-wide default applied, and then the widening
    /// that happens when there is no participant to filter against.
    private var effective: NotificationLevel {
        app.recentGroups.effectiveNotificationLevel(
            inGroup: groupID,
            default: app.settings.notificationLevel,
            participants: participants
        )
    }

    /// The narrow level was asked for and cannot be honoured, because nobody has said which
    /// participant this phone belongs to here. Said out loud rather than left to be noticed: a
    /// filter that silently stopped filtering is the kind of thing people blame the app for.
    private var cannotNarrow: Bool {
        (chosen ?? app.settings.notificationLevel) == .involvingMe && effective == .everything
    }

    var body: some View {
        Section {
            NotificationLevelPicker(
                selection: Binding(
                    get: { chosen },
                    set: { app.recentGroups.setNotificationLevel($0, groupId: groupID) }
                ),
                followsDefault: app.settings.notificationLevel,
                identifier: AccessibilityID.Notifications.groupLevel
            )
            NotificationPermissionRow(wants: effective != .nothing)
        } header: {
            Text("Notifications")
        } footer: {
            if cannotNarrow {
                Text("Until you say which participant you are above, there is nobody to match expenses against — so this group tells you about everything.")
                    .accessibilityIdentifier(AccessibilityID.Notifications.identityNeeded)
            } else {
                Text("What this group tells you about. Spliit checks for changes in the background, and iOS decides how often that happens — so a notification can arrive a while after what it describes.")
            }
        }
        // Only a change made *here* is allowed to ask iOS for permission, because it is the only
        // one where somebody has just said they want to be told something. Answering "You" above
        // changes what this group will do as well, and prompting for that would be a prompt
        // nobody went looking for.
        .onChange(of: chosen) { _, new in
            Task {
                await notifications.preferencesDidChange(
                    wants: (new ?? app.settings.notificationLevel) != .nothing
                )
            }
        }
        .onChange(of: effective) { _, _ in
            Task { await notifications.scheduleNextRefresh() }
        }
        .task { await notifications.refresh() }
    }
}

/// The three levels, plus the fourth answer a group has: whatever the app-wide default says.
private struct NotificationLevelPicker: View {

    @Binding var selection: NotificationLevel?
    /// What "Same as default" currently resolves to, spelled out on the row. Nil on the screen
    /// that *is* the default, where following it would mean following itself.
    let followsDefault: NotificationLevel?
    let identifier: String

    var body: some View {
        Picker("Notify me about", selection: $selection) {
            if let followsDefault {
                Text("Same as default (\(followsDefault.name))")
                    .tag(NotificationLevel?.none)
            }
            ForEach(NotificationLevel.allCases, id: \.self) { level in
                Text(level.name).tag(NotificationLevel?.some(level))
            }
        }
        // Pushed rather than a menu: four rows with a sentence for a label do not fit a popup,
        // and this tab has no room for three lines of segmented control.
        .pickerStyle(.navigationLink)
        .accessibilityIdentifier(identifier)
    }
}

/// The row that appears only when iOS is the thing standing in the way.
///
/// Two ways it can be. Nobody has been asked yet — which is where anyone who leaves the levels
/// alone stays, since the prompt goes with choosing one — and the row asks. Or somebody said no,
/// and that cannot be undone from inside the app, because the one prompt iOS allows has been
/// spent; the only honest thing left to offer is the way to the place where it can be undone.
private struct NotificationPermissionRow: View {

    /// Whether anything here is asking to be delivered. There is nothing to say when the answer
    /// is "nothing", however firmly iOS has been told either way.
    let wants: Bool

    @Environment(\.openURL) private var openURL
    private var notifications: ActivityNotifications { .shared }

    var body: some View {
        if wants, notifications.hasCheckedAuthorization {
            switch notifications.authorization {
            case .notDetermined:
                Button("Turn on notifications", systemImage: "bell.badge") {
                    Task { await notifications.preferencesDidChange(wants: true) }
                }
                .accessibilityIdentifier(AccessibilityID.Notifications.permissionButton)
            case .denied:
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Label(
                        "Notifications are off for Spliit in iOS Settings",
                        systemImage: "exclamationmark.triangle"
                    )
                }
                .accessibilityIdentifier(AccessibilityID.Notifications.permissionWarning)
            default:
                EmptyView()
            }
        }
    }
}
