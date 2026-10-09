import XCTest
@testable import MealShuffler

/// How much the app is allowed to interrupt a household.
///
/// Four kinds of reminder were added independently, each defensible on its own, and nobody
/// counted the total: a household with all of them on received a dinner reminder and a
/// start-cooking nudge about the *same meal*, plus a shopping nudge and a plan-next-week
/// nudge landing on the same day. These tests hold the cap at one a day.
final class ReminderVolumeTests: XCTestCase {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        // weekStart below is a Monday. Keep the test's week numbering independent of
        // the simulator locale, where a Gregorian calendar may start on Sunday.
        calendar.firstWeekday = 2
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    /// Monday of a fixed week, so the assertions do not drift with the real date.
    private var weekStart: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 5          // a Monday
        components.hour = 0
        return calendar.date(from: components)!
    }

    private var now: Date { calendar.date(byAdding: .hour, value: 6, to: weekStart)! }

    private func makeSchedule(
        dinner: Bool = true,
        prep: Bool = false,
        grocery: Bool = false,
        groceryWeekday: Weekday = .saturday,
        nextWeek: Bool = false
    ) -> ReminderSchedule {
        let meals = Array(SampleMeals.all.prefix(7))
        let plan = WeeklyPlan(
            startDate: weekStart,
            meals: Weekday.ordered(calendar: calendar).enumerated().map { index, day in
                PlannedMeal(day: day, mealID: meals[index % meals.count].id, isLocked: false)
            }
        )
        var schedule = ReminderSchedule.empty
        schedule.plan = plan
        schedule.meals = meals
        schedule.dinnerEnabled = dinner
        schedule.dinnerHour = 16
        schedule.prepLeadEnabled = prep
        schedule.groceryEnabled = grocery
        schedule.groceryWeekday = groceryWeekday
        schedule.groceryHour = 10
        if nextWeek {
            schedule.nextWeekPlan = WeeklyPlan(
                startDate: calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart)!,
                meals: plan.meals
            )
        }
        return schedule
    }

    private func chosen(_ schedule: ReminderSchedule) -> [DinnerReminderService.Candidate] {
        DinnerReminderService.oneADay(
            DinnerReminderService.candidates(for: schedule, calendar: calendar, now: now),
            schedule: schedule,
            calendar: calendar
        )
    }

    private func days(_ candidates: [DinnerReminderService.Candidate]) -> [String] {
        candidates.map(\.stamp)
    }

    // MARK: - The cap

    func testNoMoreThanOneReminderADay() {
        let schedule = makeSchedule(prep: true, grocery: true, nextWeek: false)
        let stamps = days(chosen(schedule))
        XCTAssertEqual(Set(stamps).count, stamps.count, "A day may carry at most one reminder")
    }

    /// The specific complaint: two pushes about one dinner.
    func testTheStartCookingNudgeReplacesTheFixedHourReminder() throws {
        let both = chosen(makeSchedule(prep: true))
        let onePerDay = Dictionary(grouping: both, by: \.stamp)
        for (stamp, candidates) in onePerDay {
            XCTAssertEqual(candidates.count, 1, "\(stamp) scheduled more than one reminder")
        }
        XCTAssertTrue(
            both.allSatisfy { $0.kind == .prep || $0.kind == .planNextWeek || $0.kind == .newWeek },
            "With prep timing on, it should win over the fixed-hour reminder"
        )
    }

    func testWithoutPrepTimingTheDinnerReminderStillFires() {
        let picked = chosen(makeSchedule(prep: false))
        XCTAssertTrue(picked.contains { $0.kind == .dinner })
        XCTAssertFalse(picked.contains { $0.kind == .prep })
    }

    /// Shopping day leads its day, and carries the evening's dinner instead of silencing it.
    /// It used to drop that day's dinner reminder every week, even hours apart.
    func testShoppingDayCarriesTheDinnerInsteadOfDroppingIt() throws {
        let schedule = makeSchedule(prep: true, grocery: true, groceryWeekday: .saturday)
        let saturday = schedule.plan.date(for: .saturday, calendar: calendar)
        let picked = chosen(schedule).filter { calendar.isDate($0.fireDate, inSameDayAs: saturday) }
        XCTAssertEqual(picked.count, 1, "Still one notification that day")
        let lead = try XCTUnwrap(picked.first)
        XCTAssertEqual(lead.kind, .grocery)
        XCTAssertEqual(lead.item?.day, .saturday, "The shopping reminder knows what is for dinner")
        let content = try XCTUnwrap(DinnerReminderService.content(for: lead, schedule: schedule, calendar: calendar))
        XCTAssertTrue(content.body.contains("\n"), "A list line and a tonight line")
        XCTAssertEqual(content.destination, .shop)
    }

    /// The nudge never fired: it always lost to the last day's dinner reminder, and the old
    /// test only checked it *if* it existed. It now rides on that reminder.
    func testTheEmptyNextWeekNudgeIsAlwaysSaid() throws {
        let schedule = makeSchedule(prep: false)
        let picked = chosen(schedule)
        let lastDay = try XCTUnwrap(Weekday.ordered(calendar: calendar).last)
        let lastDate = schedule.plan.date(for: lastDay, calendar: calendar)
        let lead = try XCTUnwrap(picked.first { calendar.isDate($0.fireDate, inSameDayAs: lastDate) })
        XCTAssertEqual(lead.kind, .dinner, "The concrete reminder still leads")
        XCTAssertTrue(lead.mentionsEmptyNextWeek, "The household hears that next week is empty")
        let content = try XCTUnwrap(DinnerReminderService.content(for: lead, schedule: schedule, calendar: calendar))
        XCTAssertGreaterThan(content.body.components(separatedBy: "\n").count, 1)
        XCTAssertEqual(Set(days(picked)).count, days(picked).count, "And each day still carries exactly one thing")
    }

    func testAShoppingDayWithNothingToShopForSaysNothing() {
        var schedule = makeSchedule(dinner: false, grocery: true, groceryWeekday: .saturday)
        schedule.plan = WeeklyPlan(startDate: weekStart, meals: [])
        let picked = chosen(schedule)
        XCTAssertTrue(picked.allSatisfy { DinnerReminderService.content(for: $0, schedule: schedule, calendar: calendar) == nil })
    }

    /// Takeaway and leftovers have nothing for "We cooked this" to record.
    func testOnlyCookingDaysCarryTheCookingButtons() throws {
        var schedule = makeSchedule()
        var friday = try XCTUnwrap(schedule.plan[.friday])
        friday.kind = .takeaway
        friday.mealID = nil
        schedule.plan[.friday] = friday
        for candidate in chosen(schedule) where candidate.kind == .dinner {
            let content = try XCTUnwrap(DinnerReminderService.content(for: candidate, schedule: schedule, calendar: calendar))
            if candidate.item?.day == .friday {
                XCTAssertEqual(content.categoryIdentifier, DinnerReminderService.infoCategoryIdentifier)
            } else if !candidate.mentionsEmptyNextWeek {
                XCTAssertEqual(content.categoryIdentifier, DinnerReminderService.categoryIdentifier)
            }
        }
    }

    /// A freezer dinner gets the evening before to thaw, said on that evening's reminder.
    func testAFreezerDinnerIsAnnouncedTheEveningBefore() throws {
        var schedule = makeSchedule()
        let recipe = try XCTUnwrap(schedule.meals.first)
        var thursday = try XCTUnwrap(schedule.plan[.thursday])
        thursday.kind = .leftovers(sourceDay: .monday)
        thursday.freezerBatch = FreezerBatch(recipe: recipe, portions: 4, label: "")
        schedule.plan[.thursday] = thursday
        let wednesday = schedule.plan.date(for: .wednesday, calendar: calendar)
        let lead = try XCTUnwrap(chosen(schedule).first { calendar.isDate($0.fireDate, inSameDayAs: wednesday) })
        let content = try XCTUnwrap(DinnerReminderService.content(for: lead, schedule: schedule, calendar: calendar))
        XCTAssertTrue(content.body.contains(recipe.name), "Wednesday says to take Thursday's dinner out")
    }

    /// A week nobody planned still gets one reminder on its first evening.
    func testAnUnplannedWeekStillGetsItsFirstEvening() {
        let picked = chosen(makeSchedule(nextWeek: false))
        let nextMonday = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart)!
        XCTAssertTrue(picked.contains { $0.kind == .newWeek && calendar.isDate($0.fireDate, inSameDayAs: nextMonday) })
        XCTAssertFalse(chosen(makeSchedule(nextWeek: true)).contains { $0.kind == .newWeek })
    }

    func testOpeningAReminderGoesSomewhereUseful() {
        XCTAssertEqual(DinnerReminderService.destination(forActionIdentifier: "com.apple.UNNotificationDefaultActionIdentifier",
                                                         userInfo: ["destination": "shop"]), .shop)
        XCTAssertEqual(DinnerReminderService.destination(forActionIdentifier: DinnerReminderService.planNextWeekActionIdentifier,
                                                         userInfo: [:]), .nextWeek)
        XCTAssertNil(DinnerReminderService.destination(forActionIdentifier: DinnerReminderService.cookedActionIdentifier,
                                                       userInfo: [:]), "Handled without opening the app")
    }

    // MARK: - Nothing is scheduled when nothing was asked for

    func testDisablingDinnerRemindersSilencesEverythingDated() {
        XCTAssertTrue(chosen(makeSchedule(dinner: false, prep: true)).isEmpty)
    }

    func testAPreparedNextWeekIsStillCoveredButStillCapped() {
        let picked = chosen(makeSchedule(prep: true, nextWeek: true))
        let stamps = days(picked)
        XCTAssertEqual(Set(stamps).count, stamps.count, "Two weeks of reminders, still one a day")
        XCTAssertGreaterThan(stamps.count, 7, "A prepared next week should extend the horizon")
        XCTAssertFalse(
            picked.contains { $0.kind == .planNextWeek },
            "Nothing to nudge about once next week exists"
        )
    }

    func testOnlyFutureRemindersAreScheduled() {
        let picked = chosen(makeSchedule(prep: true))
        XCTAssertTrue(picked.allSatisfy { $0.fireDate > now }, "A reminder in the past helps nobody")
    }
}
