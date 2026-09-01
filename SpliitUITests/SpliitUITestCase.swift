import UIKit
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
    ///   - textSize: launch as if the user had chosen this size in Settings. UIKit reads the
    ///     preference from the argument domain, so this needs no host configuration and does
    ///     not leak into the next test.
    ///   - openGroup: launch as if `OpenGroupIntent` had just run for this group.
    ///   - addExpense: launch as if `AddExpenseIntent` had just run with these values.
    ///   - receiptSample: make both "Scan receipt" and "Attach documents" take a receipt the
    ///     app draws for itself, rather than open a camera the simulator does not have. What
    ///     happens to the picture afterwards is real either way — Vision and the parser on one
    ///     path, a genuine upload to the harness's bucket on the other. Only the on-device
    ///     model is skipped, since its answer is not a fixture.
    @MainActor
    func launchApp(
        recentGroups: String? = nil,
        legacyStore: [String: String]? = nil,
        resetState: Bool = true,
        overrideBaseURL: Bool = true,
        serverURL: String? = nil,
        textSize: UIContentSizeCategory? = nil,
        openGroup: String? = nil,
        addExpense: (groupID: String, title: String, amount: String)? = nil,
        openURL: String? = nil,
        exchangeRate: String? = nil,
        receiptSample: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = overrideBaseURL ? ["-baseURL", serverURL ?? baseURL] : []
        // On every launch, including the relaunches that seed nothing: it is what keeps the
        // recent-groups list off iCloud, so a simulator that happens to be signed into an
        // account can't add groups this suite never asked for.
        app.launchArguments.append("-uiTestRun")

        if let textSize {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName", textSize.rawValue
            ]
        }

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
        if let openGroup {
            app.launchArguments += ["-uiTestOpenGroup", openGroup]
        }
        if let addExpense {
            app.launchArguments += [
                "-uiTestAddExpense", addExpense.groupID, addExpense.title, addExpense.amount,
            ]
        }
        if let openURL {
            app.launchArguments += ["-uiTestOpenURL", openURL]
        }
        if let exchangeRate {
            app.launchArguments += ["-uiTestExchangeRate", exchangeRate]
        }
        if receiptSample {
            app.launchArguments.append("-uiTestReceiptSample")
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
        focus(field)

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

    /// Taps a field until it actually holds keyboard focus.
    ///
    /// A single `tap()` is not enough on a slow machine: a sheet still animating swallows the
    /// tap, and `typeText` then fails with "neither element nor any descendant has keyboard
    /// focus" — after the test has already done real work. Waiting for a keyboard to exist
    /// isn't sufficient either, since one may be up for a *different* field.
    @MainActor
    private func focus(_ field: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: 15), "The field never appeared.")

        for attempt in 1...3 {
            field.tap()
            _ = XCUIApplication().keyboards.element.waitForExistence(timeout: 5)

            // `hasKeyboardFocus` is not public API, but it is the only direct read of the state
            // that actually matters here. If it ever stops resolving, fall back to assuming the
            // tap worked rather than failing outright.
            guard let hasFocus = field.value(forKey: "hasKeyboardFocus") as? Bool else { return }
            if hasFocus { return }

            XCTAssertLessThan(attempt, 3, "The field never took keyboard focus.")
        }
    }

    /// A field with no content reports its placeholder as its value.
    @MainActor
    private func isEffectivelyEmpty(_ field: XCUIElement) -> Bool {
        let value = (field.value as? String) ?? ""
        return value.isEmpty || value == field.placeholderValue
    }

    /// Scrolls until `element` can be tapped, and does not say so while it is still moving.
    ///
    /// `app.swipeUp()` throws the scroll view and lets it coast. XCUITest answers `isHittable`
    /// only once the app looks idle, so while a form is gliding every query burns its whole
    /// quiescence budget — thirteen seconds each — and then answers anyway, about a row that has
    /// moved on by the time the tap arrives. The tap lands on the row above, or on nothing.
    ///
    /// A form short enough to reach its bottom stop hides all of this, because the scroll ends
    /// dead against it. That is why it surfaced the day the expense form grew another section:
    /// one test went from passing in 20 seconds to failing in 135, in two different places on
    /// two different runs. A slow swipe barely coasts, and waiting for the frame to stop moving
    /// covers what is left.
    @MainActor
    func scrollUntilHittable(
        _ element: XCUIElement, in app: XCUIApplication, swipes: Int = 15
    ) {
        for _ in 0..<swipes where !element.isHittable {
            app.swipeUp(velocity: .slow)
        }
        waitUntilStill(element)
    }

    /// Waits for an element to stop moving, so a tap lands where the check said it would.
    @MainActor
    func waitUntilStill(_ element: XCUIElement, timeout: TimeInterval = 5) {
        guard element.exists else { return }
        var previous = element.frame
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
            guard element.exists else { return }
            let current = element.frame
            if current == previous { return }
            previous = current
        }
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
