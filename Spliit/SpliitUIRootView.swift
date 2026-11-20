import SkipFuse
import SwiftUI

/* SKIP @bridge */ public struct SpliitUIRootView: View {
    @State var model: AppModel

    /* SKIP @bridge */ public init() {
        _model = State(initialValue: Self.sharedModel)
    }

    // The app model and launch setup are shared by every window in this process.
    private static let sharedModel: AppModel = {
        #if DEBUG && os(iOS)
        // Must happen before any store reads its backing file.
        UITestSupport.applyLaunchArguments()
        #endif

        let model = AppModel()
        model.prepare()
        return model
    }()

    public var body: some View {
        GroupsListView()
            #if os(iOS)
            // This modifier reads the app model from its environment.
            .reviewPromptOnActivation()
            #endif
            .environment(model)
    }
}
