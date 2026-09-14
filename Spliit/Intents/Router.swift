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
        case newExpense(groupID: String, prefill: ExpensePrefill)

        var groupID: String {
            switch self {
            case .group(let id): id
            case .newExpense(let groupID, _): groupID
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

/// What an intent knew about an expense before the form opened.
///
/// Everything is optional because a shortcut fills in what it has: a card tapped at a till knows
/// the merchant and the amount, and nothing else unless whoever built it said so.
struct ExpensePrefill: Equatable {
    var title: String?
    /// As text, not a number: it is typed into the amount field, which parses it in the user's
    /// locale — the one place in the app that knows whether a comma is a decimal separator.
    var amount: String?
    /// One the group's own instance answered with. `CategoryEntityQuery` resolves it against that
    /// server each time the shortcut runs, so an ID that gets here is one the group can use.
    var categoryID: Int?
    var notes: String?
    /// Photographs to attach, uploaded once the form is up — that being the first moment anything
    /// knows which instance's bucket they go to.
    var photos: [ReceiptPhoto] = []
}
