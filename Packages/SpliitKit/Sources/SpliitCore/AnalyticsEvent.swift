import Foundation

/// One thing worth reporting, and the whole of what leaves the device for it.
///
/// Screen and event names match the React Native app's, so the existing Plausible dashboard
/// reads continuously across the rewrite rather than starting again at zero.
///
/// The payload carries a name and a screen path and nothing else. Plausible's custom
/// properties are the one place a group or expense ID could ride along, and there is no
/// parameter anywhere in this type to put one in — an ID cannot be sent by accident, because
/// there is nothing to send it with. That is a stronger guarantee than a rule everyone has to
/// remember at each call site, which is how group IDs got attached in the first place.
public struct AnalyticsEvent: Equatable, Sendable {

    /// The same Plausible site the old app reported to.
    public static let domain = "spliit.app/mobile"

    public enum Screen: String, CaseIterable, Sendable {
        case home
        case about
        case createGroup = "create-group"
        case addGroupByURL = "add-group-by-url"
        case groupExpenses = "group-expenses"
        case groupBalances = "group-balances"
        // None of these three was a React Native screen. Search is a name of our own; the
        // information and stats tabs borrow the web app's route names, so the mobile site and
        // the web one can be read side by side even though they are separate Plausible sites.
        case groupSearch = "group-search"
        case groupInformation = "group-information"
        case groupStats = "group-stats"
        case groupSettings = "group-settings"
        case groupCreateExpense = "group-create-expense"
        case groupEditExpense = "group-edit-expense"
    }

    public enum Action: String, CaseIterable, Sendable {
        case createGroup = "create-group"
        case createExpense = "create-expense"
    }

    /// Plausible's event name. `pageview` is the one it treats as a screen view.
    public let name: String

    /// The path appended to the domain. Empty for an action, which is counted wherever the
    /// person happened to be.
    public let path: String

    public static func screen(_ screen: Screen) -> AnalyticsEvent {
        AnalyticsEvent(name: "pageview", path: screen.rawValue)
    }

    public static func action(_ action: Action) -> AnalyticsEvent {
        AnalyticsEvent(name: action.rawValue, path: "")
    }

    /// The JSON body Plausible receives, in full.
    public var body: [String: String] {
        [
            "name": name,
            "domain": Self.domain,
            "url": "https://\(Self.domain)/\(path)",
        ]
    }
}
