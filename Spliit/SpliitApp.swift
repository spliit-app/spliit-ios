import SwiftUI

@main
struct SpliitApp: App {

    @State private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        // Must happen before any store reads its backing file.
        UITestSupport.applyLaunchArguments()
        #endif

        let model = AppModel()
        model.migrateFromReactNativeIfNeeded()
        // Here rather than in a view: a process iOS started for a background refresh alone has
        // no window, and a tap on a notification is delivered before the first one appears.
        ActivityNotifications.shared.configure(
            settings: model.settings, recentGroups: model.recentGroups
        )
        _model = State(initialValue: model)
    }

    var body: some Scene {
        WindowGroup {
            GroupsListView()
                .environment(model)
        }
        // The only way anything reaches a lock screen: Spliit has nothing to push with, so it
        // reads each group's activity log for itself whenever iOS lets it.
        .backgroundTask(.appRefresh(ActivityNotifications.taskIdentifier)) {
            await ActivityNotifications.handleBackgroundRefresh()
        }
        .onChange(of: scenePhase) { _, phase in
            // Asked for on the way out rather than at launch. Which groups want what can change
            // right up to the moment the app is put away, and there is nothing to schedule for
            // an app that is already on screen.
            guard phase == .background else { return }
            Task { await ActivityNotifications.shared.scheduleNextRefresh() }
        }
    }
}
