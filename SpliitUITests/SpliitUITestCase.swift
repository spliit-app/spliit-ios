import XCTest

/// Shared setup for the end-to-end suites.
///
/// Every test launches the app against the throwaway instance from `make e2e-up`, with local
/// state controlled explicitly — no test inherits what a previous one left behind.
class SpliitUITestCase: XCTestCase {

    /// Where the disposable Spliit instance is listening. Set by the scheme; overridable so a
    /// run can point somewhere else.
    var baseURL: String {
        ProcessInfo.processInfo.environment["SPLIIT_E2E_BASE_URL"] ?? "http://localhost:3009/"
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// - Parameters:
    ///   - recentGroups: JSON array of `{groupId, groupName}` to start with.
    ///   - legacyStore: AsyncStorage key/value pairs to plant before launch, for upgrade tests.
    ///   - overrideBaseURL: pass `false` to let the app decide its own address. `-baseURL`
    ///     lands in `UserDefaults`' argument domain, which outranks every stored value — so a
    ///     test that checks what the app *chose* must not also be forcing the choice.
    @MainActor
    func launchApp(
        recentGroups: String? = nil,
        legacyStore: [String: String]? = nil,
        resetState: Bool = true,
        overrideBaseURL: Bool = true
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = overrideBaseURL ? ["-baseURL", baseURL] : []

        if resetState {
            app.launchArguments.append("-uiTestResetState")
        }
        if let legacyStore {
            let json = try! JSONSerialization.data(withJSONObject: legacyStore)
            app.launchArguments += ["-uiTestLegacyStore", String(decoding: json, as: UTF8.self)]
        }
        if let recentGroups {
            app.launchArguments += ["-uiTestRecentGroups", recentGroups]
        }

        app.launch()
        return app
    }

    /// Fails with a useful message instead of timing out somewhere deeper in the test.
    @MainActor
    func assertExists(
        _ element: XCUIElement,
        _ message: String,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            element.waitForExistence(timeout: timeout),
            message,
            file: file,
            line: line
        )
    }
}
