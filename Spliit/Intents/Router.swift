import Observation
import SwiftUI

/// Where something outside the app has asked it to go.
///
/// A shared instance, which the rest of the app deliberately is not. App Intents are built by
/// the system, not by this app: an intent runs before — or entirely without — the view hierarchy
/// that owns `AppModel`, and has nowhere to be handed a dependency. So it writes a destination
/// here and the app reads it whenever it next draws, whether that is a moment later or after a
/// cold launch.
///
/// Consumed on arrival: a destination that survived being navigated to would fire again on every
/// return to the list.
@MainActor
@Observable
final class Router {

    static let shared = Router()

    enum Destination: Equatable {
        case group(id: String)
        /// The group's expense form, opened and prefilled with whatever the intent was given.
        case newExpense(groupID: String, title: String?, amount: String?)

        var groupID: String {
            switch self {
            case .group(let id): id
            case .newExpense(let groupID, _, _): groupID
            }
        }
    }

    private(set) var destination: Destination?

    /// A link waiting to be read, for the case where one arrives before there is a view to read
    /// it. `onOpenURL` on a cold launch is delivered once, and if the list has not appeared yet
    /// there is nobody to hear it.
    private(set) var pendingURL: URL?

    private init() {}

    func deliver(_ url: URL) {
        pendingURL = url
    }

    func takePendingURL() -> URL? {
        defer { pendingURL = nil }
        return pendingURL
    }

    func go(to destination: Destination) {
        self.destination = destination
    }

    /// Hands over the destination if it is for `groupID`, and clears it.
    func takeDestination(for groupID: String) -> Destination? {
        guard let destination, destination.groupID == groupID else { return nil }
        self.destination = nil
        return destination
    }

    /// Hands over the group to push, leaving the rest of the destination in place for the group
    /// screen to pick up once it exists.
    func groupToOpen() -> String? {
        destination?.groupID
    }

    func clear() {
        destination = nil
    }
}
