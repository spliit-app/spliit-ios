import AppIntents
import SpliitUI
import SwiftUI

@main
struct SpliitApp: App {
    var body: some Scene {
        WindowGroup {
            SpliitUIRootView()
        }
    }
}

// Include the shared module's intents in the app's extracted metadata.
struct SpliitHostIntentsPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [SpliitUI.SpliitAppIntentsPackage.self]
    }
}
