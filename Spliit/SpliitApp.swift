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
        model.prepare()
        _model = State(initialValue: model)
    }

    var body: some Scene {
        WindowGroup {
            GroupsListView()
                .environment(model)
        }
    }
}
