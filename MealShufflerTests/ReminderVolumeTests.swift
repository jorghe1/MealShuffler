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
            both.allSatisfy { $0.kind == .prep || $0.kind == .planNextWeek },
            "With prep timing on, it should win over the fixed-hour reminder"
        )
    }

    func testWithoutPrepTimingTheDinnerReminderStillFires() {
        let picked = chosen(makeSchedule(prep: false))
        XCTAssertTrue(picked.contains { $0.kind == .dinner })
        XCTAssertFalse(picked.contains { $0.kind == .prep })
    }

    /// Shopping day is weekly and time-critical, so it keeps its day to itself.
    func testShoppingDayIsNotDoubledUpWithADinnerReminder() throws {
        let schedule = makeSchedule(prep: true, grocery: true, groceryWeekday: .saturday)
        let saturday = schedule.plan.date(for: .saturday, calendar: calendar)
        let saturdayStamp = String(
            format: "%04d-%02d-%02d",
            calendar.component(.year, from: saturday),
            calendar.component(.month, from: saturday),
            calendar.component(.day, from: saturday)
        )
        XCTAssertFalse(
            days(chosen(schedule)).contains(saturdayStamp),
            "The weekly grocery reminder already owns that day"
        )
    }

    func testTheNudgeNeverDisplacesAConcreteReminder() {
        // No next week prepared, so the plan-next-week nudge is a candidate.
        let picked = chosen(makeSchedule(prep: false))

        if let nudge = picked.first(where: { $0.kind == .planNextWeek }) {
            // Stamps are YYYY-MM-DD, so the lexicographic maximum is the latest day.
            XCTAssertEqual(nudge.stamp, days(picked).max(),
                           "The nudge belongs on the last day of the week")
        }
        XCTAssertEqual(Set(days(picked)).count, days(picked).count,
                       "And that day still carries exactly one thing")
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
