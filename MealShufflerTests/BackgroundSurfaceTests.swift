import XCTest
@testable import MealShuffler

/// The surfaces the household sees when the app is closed: the home-screen widget and the
/// dinner reminder.
///
/// Both were driven from whichever mutating method happened to remember to call them. The
/// widget had no such call anywhere, and swapping two days skipped the reminder refresh, so
/// both announced meals that had already been replaced. They are driven from the single
/// write funnel now, and these tests hold that line.
@MainActor
final class BackgroundSurfaceTests: XCTestCase {

    private struct Harness {
        let store: AppStore
        let widgets: RecordingWidgetRefresher
        let reminders: RecordingReminderScheduler
        let defaults: UserDefaults
        let suite: String
    }

    private func makeHarness(seed: UInt64 = 31) throws -> Harness {
        let suite = "BackgroundSurfaceTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let widgets = RecordingWidgetRefresher()
        let reminders = RecordingReminderScheduler()
        let store = AppStore(
            repository: UserDefaultsStateRepository(defaults: defaults),
            random: SeededRandomSource(seed: seed),
            widgetRefresher: widgets,
            reminderService: reminders
        )
        return Harness(store: store, widgets: widgets, reminders: reminders, defaults: defaults, suite: suite)
    }

    /// Rescheduling happens in a detached task, so a bare assertion races it.
    private func waitUntil(
        _ condition: @escaping () -> Bool,
        timeout: TimeInterval = 2
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    // MARK: - The widget

    func testShufflingAsksTheWidgetToReload() throws {
        let harness = try makeHarness()
        defer { harness.defaults.removePersistentDomain(forName: harness.suite) }

        harness.store.completeOnboarding()
        harness.store.flushPendingWrites()
        let before = harness.widgets.reloadCount

        harness.store.shuffleAll()
        harness.store.flushPendingWrites()

        XCTAssertGreaterThan(
            harness.widgets.reloadCount, before,
            "A reshuffled week must reach the home screen"
        )
    }

    func testTickingOffAGroceryItemDoesNotDisturbTheWidget() throws {
        let harness = try makeHarness()
        defer { harness.defaults.removePersistentDomain(forName: harness.suite) }

        harness.store.completeOnboarding()
        harness.store.flushPendingWrites()
        let before = harness.widgets.reloadCount

        let item = try XCTUnwrap(harness.store.groceryItems.first)
        harness.store.toggleGroceryItem(item)
        harness.store.flushPendingWrites()

        XCTAssertEqual(
            harness.widgets.reloadCount, before,
            "Shopping progress does not change what is for dinner"
        )
    }

    // MARK: - Reminders

    /// The defect this whole seam exists for: `swapMeals` changed two dinners and told the
    /// notification layer nothing, so both days announced the meal they no longer had.
    func testSwappingTwoDaysReschedulesReminders() async throws {
        let harness = try makeHarness()
        defer { harness.defaults.removePersistentDomain(forName: harness.suite) }

        harness.store.completeOnboarding()
        harness.store.flushPendingWrites()
        _ = await waitUntil { harness.reminders.rescheduleCount > 0 }
        let before = harness.reminders.rescheduleCount

        let monday = try XCTUnwrap(harness.store.plan[.monday]?.mealID)
        let wednesday = try XCTUnwrap(harness.store.plan[.wednesday]?.mealID)
        harness.store.swapMeals(between: .monday, and: .wednesday)
        harness.store.flushPendingWrites()

        let rescheduled = await waitUntil { harness.reminders.rescheduleCount > before }
        XCTAssertTrue(rescheduled, "Swapping days must reschedule the reminders")

        let schedule = try XCTUnwrap(harness.reminders.lastSchedule)
        XCTAssertEqual(schedule.plan[.monday]?.mealID, wednesday)
        XCTAssertEqual(schedule.plan[.wednesday]?.mealID, monday)
    }

    func testTheScheduleCarriesNextWeekOnceItIsPlanned() async throws {
        let harness = try makeHarness()
        defer { harness.defaults.removePersistentDomain(forName: harness.suite) }

        harness.store.completeOnboarding()
        harness.store.planNextWeek()
        harness.store.flushPendingWrites()

        let arrived = await waitUntil { harness.reminders.lastSchedule?.nextWeekPlan != nil }
        XCTAssertTrue(arrived, "A prepared week must be schedulable, or the app goes quiet on Monday")
    }

    // MARK: - Notification actions

    /// Pins the wire format. These keys live in a request's `userInfo` and are read back on
    /// a device that may be running a different build than the one that scheduled it.
    func testReminderActionsDecodeFromTheirUserInfo() {
        let mealID = UUID()
        let info: [AnyHashable: Any] = ["day": "tuesday", "mealID": mealID.uuidString]

        XCTAssertEqual(
            DinnerReminderService.action(
                forActionIdentifier: DinnerReminderService.cookedActionIdentifier, userInfo: info
            ),
            .cooked(mealID: mealID, day: .tuesday)
        )
        XCTAssertEqual(
            DinnerReminderService.action(
                forActionIdentifier: DinnerReminderService.somethingElseActionIdentifier, userInfo: info
            ),
            .somethingElse(mealID: mealID, day: .tuesday)
        )
        XCTAssertNil(
            DinnerReminderService.action(forActionIdentifier: "default", userInfo: info),
            "Tapping the body of the notification is not an action"
        )
        XCTAssertNil(
            DinnerReminderService.action(
                forActionIdentifier: DinnerReminderService.cookedActionIdentifier,
                userInfo: ["day": "tuesday"]
            ),
            "The plan-next-week nudge carries no meal"
        )
    }

    func testCookedActionRecordsHistoryWithoutOpeningTheApp() throws {
        let harness = try makeHarness()
        defer { harness.defaults.removePersistentDomain(forName: harness.suite) }
        harness.store.completeOnboarding()

        let mealID = try XCTUnwrap(harness.store.plan[.tuesday]?.mealID)
        harness.store.handleReminderAction(.cooked(mealID: mealID, day: .tuesday))

        XCTAssertTrue(
            harness.store.feedbackEvents.contains { $0.mealID == mealID && $0.kind == .cooked },
            "The button on the notification is the cheapest moment to record a meal"
        )
    }

    func testSomethingElseActionReplacesThatDaysDinner() throws {
        let harness = try makeHarness()
        defer { harness.defaults.removePersistentDomain(forName: harness.suite) }
        harness.store.completeOnboarding()

        let before = try XCTUnwrap(harness.store.plan[.wednesday]?.mealID)
        harness.store.handleReminderAction(.somethingElse(mealID: before, day: .wednesday))

        XCTAssertNotEqual(harness.store.plan[.wednesday]?.mealID, before)
        XCTAssertTrue(harness.store.feedbackEvents.contains { $0.mealID == before && $0.kind == .skipped })
    }

    // MARK: - Undo

    func testUndoRestoresTheWeekAfterAShuffle() throws {
        let harness = try makeHarness()
        defer { harness.defaults.removePersistentDomain(forName: harness.suite) }

        harness.store.completeOnboarding()
        let before = harness.store.plan
        XCTAssertFalse(harness.store.canUndo, "Nothing has been changed yet")

        harness.store.shuffleAll()
        XCTAssertTrue(harness.store.canUndo)
        XCTAssertNotNil(harness.store.undoLabel)

        harness.store.undoLastChange()
        XCTAssertEqual(harness.store.plan, before)
        XCTAssertFalse(harness.store.canUndo, "Undo is a single step, not a stack")
    }

    /// Snoozing writes a feedback event and then re-rolls the day. Restoring only the plan
    /// would leave the meal suppressed for four weeks with nothing on screen to explain it.
    func testUndoRestoresTheFeedbackASnoozeWrote() throws {
        let harness = try makeHarness()
        defer { harness.defaults.removePersistentDomain(forName: harness.suite) }

        harness.store.completeOnboarding()
        let mealID = try XCTUnwrap(harness.store.plan[.tuesday]?.mealID)
        let meal = try XCTUnwrap(harness.store.meal(id: mealID))

        harness.store.snooze(meal, on: .tuesday)
        XCTAssertTrue(harness.store.activeSnoozedMealIDs.contains(mealID))

        harness.store.undoLastChange()
        XCTAssertFalse(
            harness.store.activeSnoozedMealIDs.contains(mealID),
            "Undoing a snooze must un-snooze it"
        )
        XCTAssertEqual(harness.store.plan[.tuesday]?.mealID, mealID)
    }

    func testRollingOverAWeekClearsUndo() throws {
        let harness = try makeHarness()
        defer { harness.defaults.removePersistentDomain(forName: harness.suite) }

        harness.store.completeOnboarding()
        harness.store.shuffleAll()
        XCTAssertTrue(harness.store.canUndo)

        let nextWeek = WeekAnchor.startOfNextWeek(after: harness.store.plan.startDate)
        harness.store.rollOverIfNeeded(now: nextWeek)

        XCTAssertFalse(harness.store.canUndo, "You cannot undo back into a week that has passed")
    }

    // MARK: - Choosing a dinner

    func testChoosingAMealPutsItOnTheDayAndLocksIt() throws {
        let harness = try makeHarness()
        defer { harness.defaults.removePersistentDomain(forName: harness.suite) }
        harness.store.completeOnboarding()

        let chosen = try XCTUnwrap(harness.store.meals.first { $0.tags.contains(.soup) })
        harness.store.setMeal(chosen, on: .thursday)

        XCTAssertEqual(harness.store.plan[.thursday]?.mealID, chosen.id)
        XCTAssertEqual(harness.store.plan[.thursday]?.kind, .meal)
        XCTAssertEqual(harness.store.plan[.thursday]?.isLocked, true)

        harness.store.shuffleAll()
        XCTAssertEqual(
            harness.store.plan[.thursday]?.mealID, chosen.id,
            "A dinner chosen by hand must survive the next shuffle"
        )
    }

    func testChoosingAMealTurnsANightOffBackIntoCooking() throws {
        let harness = try makeHarness()
        defer { harness.defaults.removePersistentDomain(forName: harness.suite) }
        harness.store.completeOnboarding()

        var context = harness.store.context(for: .friday)
        context.mode = .away
        harness.store.updateContext(context, for: .friday)
        XCTAssertEqual(harness.store.plan[.friday]?.kind, .away)

        let chosen = try XCTUnwrap(harness.store.meals.first { $0.tags.contains(.pizza) })
        harness.store.setMeal(chosen, on: .friday)

        XCTAssertEqual(harness.store.plan[.friday]?.kind, .meal)
        XCTAssertEqual(harness.store.context(for: .friday).mode, .cook)
        XCTAssertGreaterThan(harness.store.plan[.friday]?.servings ?? 0, 0)
    }

    func testChoosingAMealIsUndoable() throws {
        let harness = try makeHarness()
        defer { harness.defaults.removePersistentDomain(forName: harness.suite) }
        harness.store.completeOnboarding()

        let before = harness.store.plan[.monday]?.mealID
        let chosen = try XCTUnwrap(harness.store.meals.first { $0.tags.contains(.taco) })
        harness.store.setMeal(chosen, on: .monday)
        harness.store.undoLastChange()

        XCTAssertEqual(harness.store.plan[.monday]?.mealID, before)
    }
}
