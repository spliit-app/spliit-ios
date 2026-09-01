#if DEBUG
import Foundation
import SpliitCore
import UIKit

/// Test-only hooks, compiled out of release builds.
///
/// UI tests need to control what the app starts from: an empty list, a seeded one, or — for
/// the upgrade test — a planted React Native store to migrate. Everything is driven by launch
/// arguments so the app itself has no idea it is under test.
///
/// The base URL needs nothing here: `-baseURL <value>` lands in `UserDefaults`' argument
/// domain on its own.
enum UITestSupport {

    enum Argument {
        /// Present on every launch a UI test makes, seeding one or not. It is what says the
        /// recent-groups list must stay on this device: a simulator signed into an iCloud
        /// account would otherwise merge somebody's real groups into a seeded list.
        static let uiTestRun = "-uiTestRun"
        /// Wipe local state so the run starts from a known-empty app.
        static let resetState = "-uiTestResetState"
        /// A JSON array of `{groupId, groupName}` to pre-populate recent groups with.
        /// `isStarred` and `isArchived` are optional, so a test can start from a list that has
        /// already been organised.
        static let seedRecentGroups = "-uiTestRecentGroups"
        /// A JSON object of AsyncStorage key/value pairs, written out in the legacy on-disk
        /// format so the real migration path runs against it.
        static let plantLegacyStore = "-uiTestLegacyStore"
        /// A group ID to route to at launch, standing in for `OpenGroupIntent`.
        static let openGroup = "-uiTestOpenGroup"
        /// A group ID to open the expense form in, standing in for `AddExpenseIntent`. The
        /// title and amount it would carry follow as two more arguments.
        static let addExpense = "-uiTestAddExpense"
        /// A URL to deliver as if the system had just opened the app with it.
        static let openURL = "-uiTestOpenURL"
        /// The rate every currency lookup should answer with, or "none" to make them all fail.
        static let exchangeRate = "-uiTestExchangeRate"
        /// Take the receipt the app draws for itself wherever a photograph is asked for —
        /// scanning one, and attaching one — instead of opening a camera the simulator has not
        /// got or a library with nothing in it. Present with no value.
        static let receiptSample = "-uiTestReceiptSample"
    }

    /// Whether the app is being driven by the end-to-end suite.
    static var isRunningUITests: Bool {
        ProcessInfo.processInfo.arguments.contains(Argument.uiTestRun)
    }

    /// Whether this run supplies a drawn receipt rather than a photographed one. Asked on every
    /// pass through the form's body, so it stays a look at the launch arguments.
    static var usesSampleReceipt: Bool {
        ProcessInfo.processInfo.arguments.contains(Argument.receiptSample)
    }

    /// A receipt to scan or to attach, for a suite with no camera and an empty photo library.
    ///
    /// Drawn rather than stubbed, and fed through the real `RecognizeDocumentsRequest` and the
    /// real parser: the interesting half of receipt scanning is whether text recognition and the
    /// rules that read it still agree, and a canned `ReceiptScan` would assert nothing at all.
    /// The on-device model is skipped for the same run — a generative answer is not a fixture.
    ///
    /// Nil unless the launch argument is present, so the app is otherwise untouched.
    static func sampleReceipt() -> ReceiptPhoto? {
        guard usesSampleReceipt else { return nil }

        let lines = SampleReceipt.lines
        // Big, black on white, and monospaced: a photograph is what text recognition is usually
        // up against, and a drawing that gives it a hard time on top of that would only make the
        // suite flaky about something it is not testing.
        let font = UIFont.monospacedSystemFont(ofSize: 44, weight: .regular)
        let size = CGSize(width: 800, height: CGFloat(lines.count) * 60 + 80)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            for (index, line) in lines.enumerated() {
                line.draw(
                    at: CGPoint(x: 40, y: 40 + CGFloat(index) * 60),
                    withAttributes: [.font: font, .foregroundColor: UIColor.black]
                )
            }
        }
        return ReceiptPhoto(image)
    }

    /// A rates service that answers from a launch argument instead of the network.
    ///
    /// Rates are the one thing in the app that comes from somewhere other than the Spliit
    /// instance under test, and a suite that reached for the real one would be as reliable as the
    /// runner's connection. Nil when the argument is absent, so the app is otherwise untouched.
    static func stubbedExchangeRates() -> ExchangeRates? {
        guard let value = value(for: Argument.exchangeRate, in: ProcessInfo.processInfo.arguments)
        else { return nil }

        guard value != "none" else {
            return ExchangeRates { _ in throw URLError(.notConnectedToInternet) }
        }
        return ExchangeRates { url in
            let target = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "symbols" }?.value ?? ""
            let day = url.pathComponents.last ?? ""
            return Data(
                #"{"amount":1.0,"base":"X","date":"\#(day)","rates":{"\#(target)":\#(value)}}"#.utf8
            )
        }
    }

    static func applyLaunchArguments() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains(where: { $0.hasPrefix("-uiTest") }) else { return }

        if arguments.contains(Argument.resetState) {
            resetState()
        }
        if let json = value(for: Argument.plantLegacyStore, in: arguments) {
            plantLegacyStore(json)
        }
        if let json = value(for: Argument.seedRecentGroups, in: arguments) {
            seedRecentGroups(json)
        }
        applyRoute(from: arguments)
    }

    /// Puts a destination in the router exactly as an App Intent would.
    ///
    /// The intents themselves cannot be driven from XCUITest — they are run by the system, from
    /// Siri or Spotlight, outside any app the test controls. What *can* break silently is the
    /// half on this side: whether a destination left in the router actually opens the group and
    /// the form. That is what this exposes.
    @MainActor
    private static func applyRoute(from arguments: [String]) {
        if let groupID = value(for: Argument.openGroup, in: arguments) {
            Router.shared.go(to: .group(id: groupID))
        }
        // A UI test cannot make the system open a URL against the app under test, so the URL is
        // handed to the router instead. Everything past that point — parsing, joining a group
        // the device does not know, opening it — is the code that actually runs in the field.
        if let text = value(for: Argument.openURL, in: arguments), let url = URL(string: text) {
            Router.shared.deliver(url)
        }
        if let groupID = value(for: Argument.addExpense, in: arguments) {
            let index = arguments.firstIndex(of: Argument.addExpense)!
            Router.shared.go(
                to: .newExpense(
                    groupID: groupID,
                    title: arguments.indices.contains(index + 2) ? arguments[index + 2] : nil,
                    amount: arguments.indices.contains(index + 3) ? arguments[index + 3] : nil
                )
            )
        }
    }

    private static func value(for argument: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: argument),
              arguments.indices.contains(index + 1)
        else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func resetState() {
        let defaults = UserDefaults.standard
        for key in ["didMigrateFromReactNative", SettingsStore.Key.baseURL] {
            defaults.removeObject(forKey: key)
        }
        try? FileManager.default.removeItem(at: RecentGroupsStore.defaultFileURL())
        try? FileManager.default.removeItem(at: legacyStoreDirectory())
    }

    private static func seedRecentGroups(_ json: String) {
        guard let groups = try? JSONDecoder().decode([RecentGroup].self, from: Data(json.utf8))
        else {
            return
        }
        let url = RecentGroupsStore.defaultFileURL()
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? JSONEncoder().encode(groups).write(to: url)
    }

    /// Recreates the exact layout AsyncStorage would have left behind, including spilling
    /// values past 1024 characters into MD5-named sidecar files — the path a user with a long
    /// group list actually takes.
    private static func plantLegacyStore(_ json: String) {
        guard let values = try? JSONSerialization.jsonObject(with: Data(json.utf8))
            as? [String: String]
        else {
            return
        }

        let directory = legacyStoreDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var manifest: [String: Any] = [:]
        for (key, value) in values {
            if value.count <= 1024 {
                manifest[key] = value
            } else {
                manifest[key] = NSNull()
                try? Data(value.utf8).write(to: directory.appending(path: md5Hex(key)))
            }
        }
        try? JSONSerialization.data(withJSONObject: manifest)
            .write(to: directory.appending(path: "manifest.json"))
    }

    private static func legacyStoreDirectory() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        return base
            .appending(path: Bundle.main.bundleIdentifier ?? "app.spliit.spliitmobile")
            .appending(path: "RCTAsyncLocalStorage_V1")
    }

    private static func md5Hex(_ text: String) -> String {
        LegacyAsyncStorage.md5Hex(text)
    }
}
#endif
