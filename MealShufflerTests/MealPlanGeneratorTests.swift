import XCTest
@testable import MealShuffler

final class MealPlanGeneratorTests: XCTestCase {
    private let meals = SampleMeals.all
    private let generator = MealPlanGenerator()

    func testStarterRulesAreRespected() throws {
        let result = generator.generate(preferredMeals: meals, allMeals: meals, rules: PlanningRule.starterRules(meals: meals))
        XCTAssertTrue(try meal(on: .tuesday, in: result.plan).tags.contains(.fish))
        XCTAssertTrue(try meal(on: .thursday, in: result.plan).tags.contains(.fish))
        XCTAssertTrue(try meal(on: .saturday, in: result.plan).tags.contains(.pizza))

        let planned = result.plan.meals.compactMap { item -> Meal? in
            guard let id = item.mealID else { return nil }
            return meals.first(where: { $0.id == id })
        }
        XCTAssertLessThanOrEqual(planned.filter { $0.tags.contains(.chicken) }.count, 2)
        XCTAssertTrue(result.conflicts.isEmpty)
    }

    func testLockedMealSurvivesShuffle() throws {
        let taco = try XCTUnwrap(meals.first(where: { $0.tags.contains(.taco) }))
        let existing = WeeklyPlan(meals: [PlannedMeal(day: .friday, mealID: taco.id, isLocked: true)])
        let result = generator.generate(
            preferredMeals: meals,
            allMeals: meals,
            rules: PlanningRule.starterRules(meals: meals),
            existingPlan: existing
        )
        XCTAssertEqual(result.plan[.friday]?.mealID, taco.id)
        XCTAssertEqual(result.plan[.friday]?.isLocked, true)
    }

    func testContradictingHardRulesProduceReadableConflict() {
        let rules = [
            PlanningRule(title: "Fish on Tuesday", constraint: .requiredOn(day: .tuesday, matcher: .tag(.fish))),
            PlanningRule(title: "No fish on Tuesday", constraint: .excludedOn(day: .tuesday, matcher: .tag(.fish)))
        ]
        let result = generator.generate(preferredMeals: meals, allMeals: meals, rules: rules)
        XCTAssertFalse(result.conflicts.isEmpty)
        XCTAssertTrue(result.conflicts.contains(where: { $0.ruleID != nil }))
    }

    func testSoftRuleNeverCreatesHardConflict() {
        let rules = [
            PlanningRule(title: "Fish on Tuesday", constraint: .requiredOn(day: .tuesday, matcher: .tag(.fish))),
            PlanningRule(title: "Preferably no fish", strength: .preferred, constraint: .excludedOn(day: .tuesday, matcher: .tag(.fish)))
        ]
        let result = generator.generate(preferredMeals: meals, allMeals: meals, rules: rules)
        XCTAssertTrue(result.conflicts.isEmpty)
        XCTAssertTrue((try? meal(on: .tuesday, in: result.plan).tags.contains(.fish)) == true)
    }

    func testQuickerSwapReturnsQuickerMealWhenAvailable() throws {
        let current = try XCTUnwrap(meals.first(where: { $0.name == "Spaghetti bolognese" }))
        let result = generator.generate(
            preferredMeals: meals,
            allMeals: meals,
            rules: [],
            avoidingMealOnDay: [.monday: current.id],
            swapIntents: [.monday: .quicker]
        )
        XCTAssertLessThan(try meal(on: .monday, in: result.plan).prepMinutes, current.prepMinutes)
    }

    func testLeftoversAreNotAddedTwiceToGroceryList() throws {
        let soup = meals[7]
        let rules = [PlanningRule(title: "Soup on Monday", constraint: .requiredOn(day: .monday, matcher: .exactMeal(soup.id)))]
        let contexts: [Weekday: DayPlanContext] = [
            .monday: DayPlanContext(diners: 4, extraServings: 4),
            .tuesday: DayPlanContext(diners: 4, mode: .leftovers, leftoverSourceDay: .monday),
            .wednesday: DayPlanContext(diners: 4, mode: .away),
            .thursday: DayPlanContext(diners: 4, mode: .away),
            .friday: DayPlanContext(diners: 4, mode: .away),
            .saturday: DayPlanContext(diners: 4, mode: .away),
            .sunday: DayPlanContext(diners: 4, mode: .away)
        ]
        let result = generator.generate(preferredMeals: meals, allMeals: meals, rules: rules, contexts: contexts)
        let list = GroceryListBuilder.build(plan: result.plan, meals: meals)
        let tomatoes = try XCTUnwrap(list.first(where: { $0.name == soup.ingredients[0].name }))
        XCTAssertEqual(tomatoes.quantity, 6)
        XCTAssertEqual(result.plan[.tuesday]?.kind, .leftovers(sourceDay: .monday))
        XCTAssertEqual(result.plan[.wednesday]?.kind, .away)
    }

    func testGroceryListScalesAndNormalizesUnits() {
        let meal = Meal(
            name: "Test", subtitle: "", emoji: "🍽️", prepMinutes: 10, tags: [],
            ingredients: [Ingredient(name: "Flour", quantity: 1, unit: "kg", aisle: .pantry)],
            defaultServings: 4
        )
        let plan = WeeklyPlan(meals: [PlannedMeal(day: .monday, mealID: meal.id, isLocked: false, servings: 2)])
        let item = GroceryListBuilder.build(plan: plan, meals: [meal]).first
        XCTAssertEqual(item?.quantity, 500)
        XCTAssertEqual(item?.unit, "g")
    }

    private func meal(on day: Weekday, in plan: WeeklyPlan) throws -> Meal {
        let id = try XCTUnwrap(plan[day]?.mealID)
        return try XCTUnwrap(meals.first(where: { $0.id == id }))
    }
}
