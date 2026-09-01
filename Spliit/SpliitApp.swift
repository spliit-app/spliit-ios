import SwiftUI

@main
struct SpliitApp: App {

    @State private var model: AppModel

    init() {
        #if DEBUG
        // Must happen before any store reads its backing file.
        UITestSupport.applyLaunchArguments()
        #endif

        let model = AppModel()
        model.migrateFromReactNativeIfNeeded()
        _model = State(initialValue: model)
    }

    var body: some Scene {
        WindowGroup {
            GroupsListView()
                // Inside `.environment(model)`, not outside it: a modifier reads the
                // environment from where it sits, and this one needs the app model.
                .reviewPromptOnActivation()
                .environment(model)
        }
    }
}
