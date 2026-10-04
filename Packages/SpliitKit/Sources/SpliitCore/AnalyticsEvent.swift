import Foundation

/// One thing worth reporting, and the whole of what leaves the device for it.
///
/// Screen and event names match the React Native app's, so the existing Plausible dashboard
/// reads continuously across the rewrite rather than starting again at zero. Umami receives the
/// same names, so the two dashboards can be compared while both are fed and Plausible dropped
/// once Umami's numbers are trusted — the move the web app made in spliit#651.
///
/// The payload carries a name and a screen path and nothing else. Plausible's custom
/// properties and Umami's `data` are the places a group or expense ID could ride along, and
/// there is no parameter anywhere in this type to put one in — an ID cannot be sent by
/// accident, because there is nothing to send it with. That is a stronger guarantee than a rule
/// everyone has to remember at each call site, which is how group IDs got attached in the
/// first place.
public struct AnalyticsEvent: Equatable, Sendable {

    /// The same Plausible site the old app reported to.
    public static let domain = "spliit.app/mobile"

    /// The app's own website in Umami, kept apart from the web app's as Plausible's site is.
    /// Nil sends nothing to Umami at all.
    public static let umamiWebsiteID: String? = "54b61b68-c7bc-4604-9d89-fe42b66b2034"

    /// What Umami files every event under. It is the same for each and says only which product
    /// the event came from.
    public static let umamiHostname = "spliit.app"

    public enum Screen: String, CaseIterable, Sendable {
        case home
        case about
        case createGroup = "create-group"
        case addGroupByURL = "add-group-by-url"
        // A screen of its own here, where the web app has a second mode inside its
        // add-by-URL popover: on a phone the camera is the whole screen, so counting it as one
        // is what says how many people actually reach for it.
        case addGroupByQRCode = "add-group-by-qr-code"
        case groupExpenses = "group-expenses"
        case groupBalances = "group-balances"
        // None of these four was a React Native screen. Search is a name of our own; the
        // information, stats and activity screens borrow the web app's route names, so the
        // mobile site and the web one can be read side by side even though they are separate
        // Plausible sites.
        case groupSearch = "group-search"
        case groupInformation = "group-information"
        case groupStats = "group-stats"
        case groupActivity = "group-activity"
        case groupSettings = "group-settings"
        case groupCreateExpense = "group-create-expense"
        case groupEditExpense = "group-edit-expense"
    }

    public enum Action: String, CaseIterable, Sendable {
        case createGroup = "create-group"
        case createExpense = "create-expense"
        // The web app counts this as "expense: scan receipt"; the two products report to
        // separate Plausible sites, and this one names its events the way the rest of this
        // enum does.
        case scanReceipt = "scan-receipt"
        // "expense: attach document" on the web app's site.
        case attachDocument = "attach-document"
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

    /// The request Umami receives, in full.
    ///
    /// Three fields the web tracker fills in are left out on purpose. `title` and `referrer`
    /// can carry a group's name or ID on the web, and there is nothing worth sending in them
    /// here. `id` is Umami's slot for a persistent identifier per person; without one, Umami
    /// tells sessions apart as Plausible does, from the address and the User-Agent under a salt
    /// it rotates, and nothing on the phone has to remember anyone.
    public func umamiRequest(websiteID: String, device: AnalyticsDevice) -> UmamiRequest {
        UmamiRequest(
            payload: UmamiRequest.Payload(
                website: websiteID,
                hostname: Self.umamiHostname,
                url: "/\(path)",
                name: name == "pageview" ? nil : name,
                language: device.language,
                screen: device.screen
            )
        )
    }
}

/// The body of Umami's `POST /api/send`.
public struct UmamiRequest: Encodable, Equatable, Sendable {
    public var type = "event"
    public let payload: Payload

    public struct Payload: Encodable, Equatable, Sendable {
        public let website: String
        public let hostname: String
        public let url: String
        /// Absent for a screen view: Umami records an event without a name as a pageview.
        public let name: String?
        public let language: String
        public let screen: String
    }
}

/// What Umami learns about the phone — no more than a browser would have told it.
public struct AnalyticsDevice: Equatable, Sendable {
    public var isPad: Bool
    /// As `UIDevice.systemVersion` gives it: `26.0.1`.
    public var systemVersion: String
    public var appVersion: String
    /// In points, as a browser's `window.screen` is: Umami tells a phone from a tablet by the
    /// width.
    public var screenWidth: Int
    public var screenHeight: Int
    /// A BCP 47 tag, such as `fr-CA`.
    public var language: String

    public init(
        isPad: Bool,
        systemVersion: String,
        appVersion: String,
        screenWidth: Int,
        screenHeight: Int,
        language: String
    ) {
        self.isPad = isPad
        self.systemVersion = systemVersion
        self.appVersion = appVersion
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
        self.language = language
    }

    var screen: String { "\(screenWidth)x\(screenHeight)" }

    /// Shaped like an in-app web view's, because Umami reads the OS from it and silently drops
    /// whatever `isbot` flags — answering 200 all the same. `Spliit iOS`, which Plausible
    /// receives, is flagged: every event sent with it would vanish without a trace.
    public var userAgent: String {
        let model = isPad ? "iPad; CPU OS" : "iPhone; CPU iPhone OS"
        let version = systemVersion.replacingOccurrences(of: ".", with: "_")
        return "Mozilla/5.0 (\(model) \(version) like Mac OS X) AppleWebKit/605.1.15 "
            + "(KHTML, like Gecko) Mobile/15E148 Spliit/\(appVersion)"
    }
}
