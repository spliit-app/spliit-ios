import StoreKit
import SwiftUI

/// Fires an armed review prompt the next time the app comes to the front.
///
/// The decision itself belongs to ``ReviewPromptStore``; all that happens here is the asking,
/// and the one piece of timing that has to be a view's business: the moment the app is on
/// screen and idle. Nothing that earns a prompt is interrupted by one — see the store for why.
private struct ReviewPromptModifier: ViewModifier {

    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview

    /// A UI test must never be asked. The dialog is a real system alert, it lands on top of
    /// whatever the suite was doing, and nothing in the test's reach can dismiss it. The gates
    /// in the store would already keep a fresh simulator from qualifying; this makes it a
    /// guarantee rather than an arithmetic coincidence.
    private static let isUITesting = ProcessInfo.processInfo.arguments.contains {
        $0.hasPrefix("-uiTest")
    }

    func body(content: Content) -> some View {
        content
            // `initial: true` is what makes a cold launch count. Without it the first
            // activation of every run is missed — `onChange` reports changes, and the phase is
            // already `.active` by the time this view is in the hierarchy — so the session
            // count would lag by one launch and an armed prompt would wait for a *second* one.
            .onChange(of: scenePhase, initial: true) { _, phase in
                guard phase == .active, !Self.isUITesting else { return }
                guard app.reviewPrompt.recordActivation() else { return }

                Task {
                    // The prompt needs a scene that is actually foregrounded, and this runs at
                    // the moment it becomes one. A beat's wait is also the difference between a
                    // dialog on the app and a dialog on a half-drawn launch.
                    try? await Task.sleep(for: .seconds(1))
                    requestReview()
                }
            }
    }
}

extension View {
    /// Asks for an App Store review when something has earned one, and never otherwise.
    func reviewPromptOnActivation() -> some View {
        modifier(ReviewPromptModifier())
    }
}
