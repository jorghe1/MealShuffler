import XCTest
@testable import MealShuffler

final class PlanningReliabilityTests: XCTestCase {
    func testSearchRepairsCompetitionForTheOnlyFastFishDinner() {
        let fast = meal("Fast fish", tags: [.fish])
        let slow = Meal(name: "Slow fish", subtitle: "", emoji: "", prepMinutes: 60, tags: [.fish], ingredients: [])
        let veg = meal("Vegetables", tags: [.vegetarian])
        let library = [fast, slow, veg]
        let rules = [
            PlanningRule(title: "Two fish", constraint: .minimumPerWeek(matcher: .tag(.fish), count: 2)),
            PlanningRule(title: "Tuesday veg", constraint: .requiredOn(day: .day(.tuesday), matcher: .tag(.vegetarian))),
            PlanningRule(title: "No repeat", constraint: .noRepeatWithin(weeks: 1)),
            PlanningRule(title: "Fast Monday", constraint: .maximumPrepTime(day: .day(.monday), minutes: 25)),
        ]
        for seed in UInt64(0)..<30 {
            let result = MealPlanGenerator(random: SeededRandomSource(seed: seed), orderedDays: [.wednesday, .tuesday, .monday]).generate(
                preferredMeals: library, allMeals: library, rules: rules,
                contexts: contexts(cooking: [.monday, .tuesday, .wednesday]))
            XCTAssertEqual(result.plan[.monday]?.mealID, fast.id)
            XCTAssertEqual(result.plan[.tuesday]?.mealID, veg.id)
            XCTAssertEqual(result.plan[.wednesday]?.mealID, slow.id)
            XCTAssertTrue(result.conflicts.isEmpty)
        }
    }

    func testExclusionsAlsoValidateLeftoverDinners() {
        let fish = meal("Fish", tags: [.fish])
        let rule = PlanningRule(title: "No fish Tuesday", constraint: .excludedOn(day: .day(.tuesday), matcher: .tag(.fish)))
        let plan = WeeklyPlan(meals: [
            PlannedMeal(day: .monday, mealID: fish.id, isLocked: true, servings: 8),
            PlannedMeal(day: .tuesday, mealID: fish.id, isLocked: true, servings: 4, kind: .leftovers(sourceDay: .monday))
        ])
        let conflicts = MealPlanGenerator(orderedDays: [.monday, .tuesday]).validate(plan: plan, allMeals: [fish], rules: [rule],
            contexts: [.monday: DayPlanContext(diners: 4, extraServings: 4), .tuesday: DayPlanContext(mode: .leftovers)],
            taste: .empty, context: .empty)
        XCTAssertTrue(conflicts.contains { $0.ruleID == rule.id })
    }

    private func meal(_ name: String, tags: Set<MealTag>) -> Meal {
        Meal(name: name, subtitle: "", emoji: "", prepMinutes: 20, tags: tags, ingredients: [])
    }

    private func contexts(cooking days: Set<Weekday>) -> [Weekday: DayPlanContext] {
        Dictionary(uniqueKeysWithValues: Weekday.allCases.map { day in
            (day, DayPlanContext(mode: days.contains(day) ? .cook : .away))
        })
    }

    func testNeverRuleCannotBeRelaxedWhenLibraryHasNoAlternative() {
        let fish = meal("Fish", tags: [.fish])
        let rule = PlanningRule(title: "Never fish", constraint: .maximumPerWeek(matcher: .tag(.fish), count: 0))
        let result = MealPlanGenerator(random: SeededRandomSource(seed: 1)).generate(
            preferredMeals: [fish], allMeals: [fish], rules: [rule])
        XCTAssertFalse(result.plan.meals.contains { $0.mealID == fish.id })
        XCTAssertFalse(result.conflicts.isEmpty)
    }

    func testRepeatRuleCannotBeRelaxedForSmallLibrary() {
        let fish = meal("Fish", tags: [.fish])
        let rule = PlanningRule(title: "No repeats", constraint: .noRepeatWithin(weeks: 1))
        let result = MealPlanGenerator(random: SeededRandomSource(seed: 1)).generate(
            preferredMeals: [fish], allMeals: [fish], rules: [rule])
        XCTAssertLessThanOrEqual(result.plan.meals.filter { $0.mealID == fish.id }.count, 1)
        XCTAssertFalse(result.conflicts.isEmpty)
    }

    func testConsecutiveRuleDoesNotBridgeAnAwayDay() {
        let fish = meal("Fish", tags: [.fish])
        let rule = PlanningRule(title: "Space fish", constraint: .notOnConsecutiveDays(matcher: .tag(.fish)))
        let result = MealPlanGenerator(random: SeededRandomSource(seed: 1), orderedDays: Weekday.allCases).generate(
            preferredMeals: [fish], allMeals: [fish], rules: [rule], contexts: contexts(cooking: [.monday, .wednesday]))
        XCTAssertEqual(result.plan[.monday]?.mealID, fish.id)
        XCTAssertEqual(result.plan[.wednesday]?.mealID, fish.id)
        XCTAssertFalse(result.conflicts.contains { $0.ruleID == rule.id })
    }

    func testInteractingMinimumsAreSatisfiedWithoutBreakingTimeLimits() {
        let fish = meal("Fish", tags: [.fish])
        let veg = meal("Veg", tags: [.vegetarian])
        let rules = [
            PlanningRule(title: "Fish", constraint: .minimumPerWeek(matcher: .tag(.fish), count: 1)),
            PlanningRule(title: "Veg", constraint: .minimumPerWeek(matcher: .tag(.vegetarian), count: 1)),
        ]
        for seed in UInt64(1)...10 {
            let result = MealPlanGenerator(random: SeededRandomSource(seed: seed)).generate(
                preferredMeals: [fish, veg], allMeals: [fish, veg], rules: rules,
                contexts: contexts(cooking: [.monday, .tuesday]))
            XCTAssertEqual(Set(result.plan.meals.compactMap(\.mealID)), [fish.id, veg.id])
            XCTAssertTrue(result.conflicts.isEmpty)
        }
    }

    func testTwoLeftoverDaysCannotSpendTheSamePortions() {
        let soup = meal("Soup", tags: [.soup])
        var days = contexts(cooking: [.monday])
        days[.monday] = DayPlanContext(diners: 4, extraServings: 4)
        days[.tuesday] = DayPlanContext(diners: 4, mode: .leftovers, leftoverSourceDay: .monday)
        days[.wednesday] = DayPlanContext(diners: 4, mode: .leftovers, leftoverSourceDay: .monday)
        let result = MealPlanGenerator(random: SeededRandomSource(seed: 1), orderedDays: Weekday.allCases).generate(
            preferredMeals: [soup], allMeals: [soup], rules: [], contexts: days)
        XCTAssertFalse(result.conflicts.isEmpty)
    }

    func testAttendanceLimitsPersonalExclusions() {
        let member = UUID()
        let fish = meal("Fish", tags: [.fish])
        let rule = PlanningRule(title: "Personal taste", constraint: .excludedOn(day: .everyDay, matcher: .dislikedBy(memberID: member)))
        let context = MealMatcher.MatchContext(dislikes: [member: [fish.id]], attendance: [.monday: []])
        let result = MealPlanGenerator(random: SeededRandomSource(seed: 1)).generate(
            preferredMeals: [fish], allMeals: [fish], rules: [rule], contexts: contexts(cooking: [.monday]), matchContext: context)
        XCTAssertEqual(result.plan[.monday]?.mealID, fish.id)
    }

    func testAlternatingWeekAndCustomDaysRoundTrip() throws {
        var rule = PlanningRule(title: "Shift", constraint: .dinnerMode(day: .selected([.tuesday, .wednesday]), mode: .away))
        rule.firstWeek = WeekAnchor.startOfCurrentWeek()
        rule.repeatEveryWeeks = 2
        let next = WeekAnchor.startOfNextWeek(after: rule.firstWeek!)
        XCTAssertTrue(rule.isActive(inWeek: rule.firstWeek!))
        XCTAssertFalse(rule.isActive(inWeek: next))
        XCTAssertTrue(rule.isActive(inWeek: WeekAnchor.startOfNextWeek(after: next)))
        XCTAssertEqual(try JSONDecoder().decode(PlanningRule.self, from: JSONEncoder().encode(rule)), rule)
    }
}
