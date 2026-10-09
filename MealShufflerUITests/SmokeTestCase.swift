import XCTest

/// Shared plumbing for the smoke flows.
///
/// These tests exist mainly to produce screenshots of every main screen on each CI run, so a
/// missing optional element is noted in the report rather than failing the flow. Only the
/// things a flow cannot continue without -- the app launching, the tab bar appearing -- are
/// asserted.
///
/// The app is launched with `-ui-testing`, which makes it start from an empty, in-memory state
/// and never ask for notification permission, and with English forced so the labels below
/// match whatever language the simulator happens to be set to.
class SmokeTestCase: XCTestCase {
    /// Prefixes every screenshot of a test, so exported files sort by flow.
    var flowName: String { "smoke" }

    private var screenshotIndex = 0
    private var launchedApp: XCUIApplication?

    override func setUpWithError() throws {
        try super.setUpWithError()
        // Smoke tests: keep going and collect the remaining screenshots after a failure.
        continueAfterFailure = true
        screenshotIndex = 0
    }

    // MARK: - Launch

    @MainActor
    var app: XCUIApplication {
        guard let launchedApp else {
            XCTFail("launch(skipOnboarding:) must be called before using app")
            return XCUIApplication()
        }
        return launchedApp
    }

    @MainActor
    @discardableResult
    func launch(skipOnboarding: Bool) -> XCUIApplication {
        let application = XCUIApplication()
        var arguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if skipOnboarding { arguments.append("-ui-testing-skip-onboarding") }
        application.launchArguments += arguments

        // Belt and braces: the app should never ask in UI-test mode, but a system alert left
        // on screen would otherwise swallow every tap that follows.
        addUIInterruptionMonitor(withDescription: "System permission alert") { alert in
            for label in ["Don’t Allow", "Don't Allow", "Not Now", "Cancel", "OK"] {
                let button = alert.buttons[label]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }

        application.launch()
        launchedApp = application
        return application
    }

    // MARK: - Screenshots

    /// Attaches a screenshot of the whole screen, kept even when the test passes.
    @MainActor
    func screenshot(_ name: String) {
        screenshotIndex += 1
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = String(format: "%@-%02d-%@", flowName, screenshotIndex, name)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Steps

    /// Groups a part of a flow in the test report.
    @MainActor
    func step(_ name: String, _ body: () -> Void) {
        XCTContext.runActivity(named: name) { _ in body() }
    }

    /// Records something optional that was not found, without failing the test.
    @MainActor
    func note(_ message: String) {
        XCTContext.runActivity(named: "Note: \(message)") { _ in }
    }

    /// Waits without blocking the run loop the app's accessibility snapshots depend on.
    func pause(_ seconds: TimeInterval) {
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "pause \(seconds)s")], timeout: seconds)
    }

    // MARK: - Finding things

    /// The first of several candidates to appear, or nil once `timeout` has passed.
    ///
    /// Candidates are tried in order, so put an accessibility identifier first and a label
    /// fallback after it: the test keeps working before the identifier lands in the app.
    @MainActor
    func firstExisting(_ candidates: [XCUIElement], timeout: TimeInterval = 10) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for candidate in candidates where candidate.exists {
                return candidate
            }
            pause(0.25)
        } while Date() < deadline
        return nil
    }

    @MainActor
    func button(labelBeginningWith prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    @MainActor
    func button(labelEndingWith suffix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", suffix)).firstMatch
    }

    @MainActor
    func staticText(containing text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// Swipes `container` up until `element` exists, for rows a `List` has not created yet.
    @MainActor
    @discardableResult
    func scrollUntilExists(_ element: XCUIElement, in container: XCUIElement? = nil, maxSwipes: Int = 6) -> Bool {
        if element.waitForExistence(timeout: 2) { return true }
        let scrollable = container ?? app
        for _ in 0..<maxSwipes {
            scrollable.swipeUp()
            if element.waitForExistence(timeout: 1) { return true }
        }
        return element.exists
    }

    // MARK: - Acting

    /// Taps an element that may be partly off screen.
    ///
    /// A plain `tap()` on an element that cannot be scrolled into view records a failure, so
    /// this scrolls a little first and falls back to tapping its centre by coordinate.
    @MainActor
    func tap(_ element: XCUIElement) {
        var swipes = 0
        while element.exists, !element.isHittable, swipes < 3 {
            app.swipeUp()
            swipes += 1
        }
        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    /// Finds and taps the first candidate that appears. Returns false, and notes it, if none did.
    @MainActor
    @discardableResult
    func tapFirst(_ candidates: [XCUIElement], _ what: String, timeout: TimeInterval = 10) -> Bool {
        guard let element = firstExisting(candidates, timeout: timeout) else {
            note("\(what) not found")
            return false
        }
        tap(element)
        return true
    }

    /// Selects a tab by its English title.
    @MainActor
    @discardableResult
    func openTab(_ title: String) -> Bool {
        tapFirst([app.tabBars.buttons[title], app.buttons[title]], "\(title) tab", timeout: 15)
    }

    /// Leaves a pushed screen with the navigation bar's back button.
    @MainActor
    func goBack(to title: String) {
        let back = app.navigationBars.buttons[title]
        if back.exists {
            back.tap()
        } else if app.navigationBars.buttons.firstMatch.exists {
            app.navigationBars.buttons.firstMatch.tap()
        } else {
            note("No back button to \(title)")
        }
    }

    /// Dismisses a sheet: its own button if there is one, otherwise a swipe down.
    @MainActor
    func dismissSheet(using candidates: [XCUIElement]) {
        if let button = firstExisting(candidates, timeout: 3) {
            tap(button)
        } else {
            note("No dismiss button found; swiping the sheet down")
            app.swipeDown(velocity: .fast)
        }
        pause(0.8)
    }

    /// Waits for the main tab bar, which means onboarding is over and the app is usable.
    @MainActor
    func assertMainTabsVisible(file: StaticString = #filePath, line: UInt = #line) {
        let week = firstExisting([app.tabBars.buttons["Week"], app.buttons["Week"]], timeout: 30)
        XCTAssertNotNil(week, "The Week tab never appeared", file: file, line: line)
    }
}
