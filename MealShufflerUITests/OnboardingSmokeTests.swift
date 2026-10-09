import XCTest

/// A fresh install: welcome, taste cards, the first week, and into the Week tab.
final class OnboardingSmokeTests: SmokeTestCase {
    override var flowName: String { "onboarding" }

    @MainActor
    func testFreshInstallOnboarding() {
        launch(skipOnboarding: false)

        step("Welcome") {
            let getStarted = firstExisting([
                app.buttons["onboarding.getStarted"],
                app.buttons["Get started"],
            ], timeout: 30)
            XCTAssertNotNil(getStarted, "Onboarding did not start. Is the -ui-testing launch hook resetting state?")
            screenshot("welcome")
            if let getStarted { tap(getStarted) }
        }

        step("Taste cards") {
            let skip = firstExisting([
                app.buttons["onboarding.skipRemaining"],
                app.buttons["Skip remaining"],
            ], timeout: 10)
            screenshot("taste-card")

            // One opinion by swipe and one by button, so both paths are exercised before
            // skipping the rest of the deck.
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.45))
            start.press(forDuration: 0.05, thenDragTo: end)
            pause(1)

            let like = button(labelEndingWith: "Like")
            if like.waitForExistence(timeout: 3) {
                tap(like)
                pause(1)
                screenshot("taste-card-after-like")
            } else {
                note("Like button not found")
            }

            if let skip, skip.exists {
                tap(skip)
            } else if !tapFirst([app.buttons["onboarding.skipRemaining"], app.buttons["Skip remaining"]],
                                "Skip remaining", timeout: 3) {
                // Answer the rest of the deck instead; the flow moves on after the last card.
                for _ in 0..<10 where like.exists {
                    tap(like)
                    pause(0.6)
                }
            }
        }

        step("First week") {
            let startPlanning = firstExisting([
                app.buttons["onboarding.startPlanning"],
                app.buttons["Start planning"],
            ], timeout: 20)
            XCTAssertNotNil(startPlanning, "The first-week step never appeared")
            pause(1)
            screenshot("first-week")

            // The rule composer and reminder offer sit below the week.
            app.swipeUp()
            pause(0.8)
            screenshot("first-week-rules")

            if let startPlanning { tap(startPlanning) }
        }

        step("Week tab") {
            assertMainTabsVisible()
            pause(1.5)
            screenshot("week-tab")
        }
    }
}
