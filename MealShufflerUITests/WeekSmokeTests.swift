import XCTest

/// The Week tab: shuffle, open a day, and next week.
final class WeekSmokeTests: SmokeTestCase {
    override var flowName: String { "week" }

    @MainActor
    func testShuffleOpenDayAndNextWeek() {
        launch(skipOnboarding: true)
        assertMainTabsVisible()
        openTab("Week")
        pause(1)

        step("This week") {
            screenshot("this-week")
        }

        step("Shuffle") {
            // Hidden when nothing is left to change, late on a Sunday for instance.
            let shuffled = tapFirst([
                app.buttons["week.shuffle"],
                button(labelBeginningWith: "Shuffle"),
            ], "Floating shuffle button", timeout: 8)
            if shuffled {
                // The reels settle top to bottom in about two seconds.
                pause(3)
                screenshot("after-shuffle")
            }
        }

        step("Open a day") {
            if let day = firstDayRow() {
                tap(day)
                let sheetVisible = firstExisting([
                    app.buttons["Plan this day"],
                    app.buttons["daySheet.done"],
                ], timeout: 5) != nil
                if !sheetVisible { note("Day sheet did not appear") }
                pause(0.8)
                screenshot("day-sheet")
                dismissSheet(using: [
                    app.buttons["daySheet.done"],
                    app.navigationBars.buttons["Done"],
                ])
            } else {
                note("No day row found")
            }
        }

        step("Next week") {
            let opened = tapFirst([
                app.segmentedControls["week.weekPicker"].buttons.element(boundBy: 1),
                app.segmentedControls.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Next week")).firstMatch,
                button(labelBeginningWith: "Next week"),
            ], "Next week segment", timeout: 8)
            guard opened else { return }
            pause(1)
            screenshot("next-week")

            if tapFirst([app.buttons["week.shuffle"], button(labelBeginningWith: "Shuffle")],
                        "Shuffle next week", timeout: 5) {
                pause(3)
                screenshot("next-week-shuffled")
            }
        }
    }

    /// The first day of the week as a row, by identifier if the app has one and otherwise by
    /// the weekday abbreviation its label starts with.
    @MainActor
    private func firstDayRow() -> XCUIElement? {
        let days = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
        var candidates = days.map { app.buttons["week.day.\($0)"] }
        let byLabel = NSPredicate(format: "label MATCHES[c] %@", "(?s)(MON|TUE|WED|THU|FRI|SAT|SUN)\\b.*")
        candidates.append(app.buttons.matching(byLabel).firstMatch)
        candidates.append(app.cells.buttons.matching(byLabel).firstMatch)
        return firstExisting(candidates, timeout: 8)
    }
}
