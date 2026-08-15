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
    ///   - serverURL: point the app somewhere other than the test server, to exercise what
    ///     happens when it cannot be reached.
    @MainActor
    func launchApp(
        recentGroups: String? = nil,
        legacyStore: [String: String]? = nil,
        resetState: Bool = true,
        overrideBaseURL: Bool = true,
        serverURL: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = overrideBaseURL ? ["-baseURL", serverURL ?? baseURL] : []

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

    var api: SpliitTestAPI {
        SpliitTestAPI(baseURL: URL(string: baseURL)!)
    }

    /// Clears a text field and types something new.
    ///
    /// Every trap here fails silently — you get wrong input rather than an error.
    /// `typeText` appends instead of replacing. A plain `tap()` leaves the cursor wherever the
    /// tap landed, so backspaces from there do nothing and new text lands mid-value. Focusing
    /// raises the keyboard, which reflows the form under any coordinate taken beforehand. And
    /// the amount fields are trailing-aligned, so a tap even slightly short of the edge lands
    /// *before* the last character. So: clear, verify, and fall back to the edit menu.
    @MainActor
    func replaceText(in field: XCUIElement, with text: String) {
        let app = XCUIApplication()
        field.tap()
        _ = app.keyboards.element.waitForExistence(timeout: 5)

        if !isEffectivelyEmpty(field) {
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
            // Over-deleting is harmless; extra backspaces on an empty field do nothing.
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 32))
        }

        if !isEffectivelyEmpty(field) {
            field.press(forDuration: 1.2)
            let selectAll = app.menuItems["Select All"]
            if selectAll.waitForExistence(timeout: 3) { selectAll.tap() }
        }

        field.typeText(text)
    }

    /// A field with no content reports its placeholder as its value.
    @MainActor
    private func isEffectivelyEmpty(_ field: XCUIElement) -> Bool {
        let value = (field.value as? String) ?? ""
        return value.isEmpty || value == field.placeholderValue
    }

    /// Saves a screenshot into the result bundle, so a failing run can be looked at without
    /// re-running it, and so the flow can be reviewed without a Mac in front of you.
    @MainActor
    func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Fails with a useful message instead of timing out somewhere deeper in the test.
    ///
    /// The timeout is generous because CI runners are markedly slower than a development
    /// machine, and a long timeout costs nothing on a passing run — it is only ever reached
    /// when the test is going to fail anyway.
    @MainActor
    func assertExists(
        _ element: XCUIElement,
        _ message: String,
        timeout: TimeInterval = 30,
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
