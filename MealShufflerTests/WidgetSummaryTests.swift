import XCTest
@testable import MealShuffler

/// The small contract between the app and the widget process: the inbox a widget button
/// writes to, the summary the app writes for the widget, and the cook the widget names.
final class WidgetSummaryTests: XCTestCase {

    private func makeDefaults(_ name: String) throws -> (UserDefaults, String) {
        let suite = "\(name)-\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: suite)), suite)
    }

    // MARK: - Inbox

    func testInboxKeepsEachNoteOnceAndDrainsInOrder() throws {
        let (defaults, suite) = try makeDefaults("WidgetInboxTests")
        defer { defaults.removePersistentDomain(forName: suite) }

        // Whole seconds, so the dates compare equal after a JSON round trip.
        let first = WidgetActionInbox.CookedNote(
            mealID: UUID(), day: .tuesday, date: Date(timeIntervalSince1970: 1_760_000_000)
        )
        let second = WidgetActionInbox.CookedNote(
            mealID: UUID(), day: .wednesday, date: Date(timeIntervalSince1970: 1_760_086_400)
        )

        WidgetActionInbox.add(first, defaults: defaults)
        // A double tap on the widget button must not record the dinner twice.
        WidgetActionInbox.add(first, defaults: defaults)
        XCTAssertEqual(WidgetActionInbox.all(defaults: defaults), [first])

        WidgetActionInbox.add(second, defaults: defaults)
        XCTAssertEqual(WidgetActionInbox.all(defaults: defaults), [first, second])

        XCTAssertEqual(WidgetActionInbox.drain(defaults: defaults), [first, second])
        XCTAssertTrue(WidgetActionInbox.all(defaults: defaults).isEmpty, "Draining empties the inbox")
        XCTAssertTrue(WidgetActionInbox.drain(defaults: defaults).isEmpty, "A second drain finds nothing")
    }

    func testInboxStartsEmpty() throws {
        let (defaults, suite) = try makeDefaults("WidgetInboxEmptyTests")
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertTrue(WidgetActionInbox.all(defaults: defaults).isEmpty)
        XCTAssertTrue(WidgetActionInbox.drain(defaults: defaults).isEmpty)
    }

    // MARK: - Summary

    func testSummaryRoundTripsThroughDefaults() throws {
        let (defaults, suite) = try makeDefaults("WidgetSummaryTests")
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(WidgetSummary.load(from: defaults), .empty, "Nothing written reads as empty")

        let summary = WidgetSummary(
            groceryRemaining: 12,
            groceryPreview: ["Rømme", "lime", "tortilla"],
            cookedStamps: ["2026-10-06", "2026-10-07"]
        )
        summary.save(to: defaults)
        XCTAssertEqual(WidgetSummary.load(from: defaults), summary)

        var ticked = summary
        ticked.cookedStamps.insert("2026-10-08")
        ticked.save(to: defaults)
        XCTAssertEqual(WidgetSummary.load(from: defaults).cookedStamps.count, 3)
    }

    func testStampIsAZeroPaddedCalendarDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Oslo"))

        let evening = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 18)))
        XCTAssertEqual(WidgetSummary.stamp(for: evening, calendar: calendar), "2026-03-07")

        // Any time on the same day gives the same stamp; the next day does not.
        let morning = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 0, minute: 5)))
        XCTAssertEqual(WidgetSummary.stamp(for: morning, calendar: calendar), "2026-03-07")
        let nextDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: evening))
        XCTAssertEqual(WidgetSummary.stamp(for: nextDay, calendar: calendar), "2026-03-08")
    }

    // MARK: - Reader

    @MainActor
    func testReaderNamesTonightsCookFromTheDayContext() throws {
        let (defaults, suite) = try makeDefaults("WidgetCookTests")
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = UserDefaultsStateRepository(defaults: defaults)

        let store = AppStore(repository: repository, random: SeededRandomSource(seed: 21))
        store.completeOnboarding()

        let today = try XCTUnwrap(
            Weekday.ordered().first { Calendar.current.isDateInToday(store.plan.date(for: $0)) }
        )
        let meal = try XCTUnwrap(MealCatalog.resolve(custom: []).first)
        store.plan[today] = PlannedMeal(day: today, mealID: meal.id, isLocked: true)

        let cook = HouseholdMember(displayName: "Kari")
        store.household.members.append(cook)
        var context = store.dayContexts[today] ?? DayPlanContext()
        context.mode = .cook
        context.cookMemberID = cook.id
        store.dayContexts[today] = context
        store.flushPendingWrites()

        let tonight = try XCTUnwrap(PlannedDinnerReader(repository: repository).upcoming().first)
        XCTAssertEqual(tonight.day, today)
        XCTAssertTrue(tonight.isCooking)
        XCTAssertEqual(tonight.cook, "Kari")
        XCTAssertEqual(tonight.mealID, meal.id, "The widget button needs the recipe it marks cooked")
    }

    @MainActor
    func testReaderNamesNoCookForAMemberWhoHasLeft() throws {
        let (defaults, suite) = try makeDefaults("WidgetCookGoneTests")
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = UserDefaultsStateRepository(defaults: defaults)

        let store = AppStore(repository: repository, random: SeededRandomSource(seed: 22))
        store.completeOnboarding()

        let today = try XCTUnwrap(
            Weekday.ordered().first { Calendar.current.isDateInToday(store.plan.date(for: $0)) }
        )
        let meal = try XCTUnwrap(MealCatalog.resolve(custom: []).first)
        store.plan[today] = PlannedMeal(day: today, mealID: meal.id, isLocked: true)

        var context = store.dayContexts[today] ?? DayPlanContext()
        context.mode = .cook
        context.cookMemberID = UUID()
        store.dayContexts[today] = context
        store.flushPendingWrites()

        let tonight = try XCTUnwrap(PlannedDinnerReader(repository: repository).upcoming().first)
        XCTAssertEqual(tonight.day, today)
        XCTAssertNil(tonight.cook)
    }

    @MainActor
    func testReaderTakesNextWeeksCookFromNextWeeksContexts() throws {
        let (defaults, suite) = try makeDefaults("WidgetNextWeekCookTests")
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = UserDefaultsStateRepository(defaults: defaults)

        let store = AppStore(repository: repository, random: SeededRandomSource(seed: 23))
        store.completeOnboarding()

        let nextStart = WeekAnchor.startOfNextWeek(after: store.plan.startDate)
        let firstDay = try XCTUnwrap(Weekday.ordered().first)
        let meal = try XCTUnwrap(MealCatalog.resolve(custom: []).first)
        store.nextWeekPlan = WeeklyPlan(
            startDate: nextStart,
            meals: [PlannedMeal(day: firstDay, mealID: meal.id, isLocked: false)]
        )

        let thisWeeksCook = HouseholdMember(displayName: "Ola")
        let nextWeeksCook = HouseholdMember(displayName: "Kari")
        store.household.members.append(contentsOf: [thisWeeksCook, nextWeeksCook])

        var thisWeek = store.dayContexts[firstDay] ?? DayPlanContext()
        thisWeek.cookMemberID = thisWeeksCook.id
        store.dayContexts[firstDay] = thisWeek

        var nextWeek = DayPlanContext()
        nextWeek.mode = .cook
        nextWeek.cookMemberID = nextWeeksCook.id
        store.nextWeekContexts[firstDay] = nextWeek
        store.flushPendingWrites()

        let reader = PlannedDinnerReader(repository: repository)
        let dinner = try XCTUnwrap(reader.upcoming(from: nextStart.addingTimeInterval(3_600)).first)
        XCTAssertEqual(dinner.day, firstDay)
        XCTAssertEqual(dinner.cook, "Kari", "Next week's day must not borrow this week's cook")
    }
}
