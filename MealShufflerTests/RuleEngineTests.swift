import XCTest
@testable import MealShuffler

/// The new constraints, exercised through the generator and the store that feeds it.
@MainActor
final class RuleEngineTests: XCTestCase {
    private let meals = SampleMeals.all

    private func generator(seed: UInt64 = 7) -> MealPlanGenerator {
        MealPlanGenerator(random: SeededRandomSource(seed: seed))
    }

    private func makeStore(seed: UInt64 = 21) throws -> (AppStore, UserDefaults, String) {
        let suite = "RuleEngineTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let store = AppStore(
            repository: UserDefaultsStateRepository(defaults: defaults),
            random: SeededRandomSource(seed: seed),
            widgetRefresher: RecordingWidgetRefresher(),
            reminderService: RecordingReminderScheduler()
        )
        return (store, defaults, suite)
    }

    private func cooked(_ result: GenerationResult) -> [Meal] {
        result.plan.meals.compactMap { item in
            guard item.kind == .meal, let id = item.mealID else { return nil }
            return meals.first { $0.id == id }
        }
    }

    // MARK: - Not two days running

    func testConsecutiveRuleKeepsAMatchedPairApart() {
        let rules = [PlanningRule(title: "Spread pasta", constraint: .notOnConsecutiveDays(matcher: .tag(.pasta)))]
        for seed in UInt64(0)..<25 {
            let result = generator(seed: seed).generate(preferredMeals: meals, allMeals: meals, rules: rules)
            let ordered = Weekday.ordered().compactMap { day -> Meal? in
                guard let item = result.plan[day], item.kind == .meal, let id = item.mealID else { return nil }
                return meals.first { $0.id == id }
            }
            for index in ordered.indices.dropFirst() {
                XCTAssertFalse(
                    ordered[index].tags.contains(.pasta) && ordered[index - 1].tags.contains(.pasta),
                    "Seed \(seed) put pasta on two days running"
                )
            }
            XCTAssertTrue(result.conflicts.filter { $0.severity == .blocking }.isEmpty)
        }
    }

    // MARK: - Repeat windows

    /// A meal planned last week is out of the running when the window is longer than a week.
    func testNoRepeatWithinKeepsARecentMealOffThePlan() throws {
        let recent = try XCTUnwrap(meals.first { $0.tags.contains(.pizza) })
        let rules = [PlanningRule(title: "Varied", constraint: .noRepeatWithin(weeks: 4))]
        let taste = TasteProfile(weeksSinceLastPlanned: [recent.id: 1])

        for seed in UInt64(0)..<20 {
            let result = generator(seed: seed)
                .generate(preferredMeals: meals, allMeals: meals, rules: rules, taste: taste)
            XCTAssertFalse(
                cooked(result).contains { $0.id == recent.id },
                "Seed \(seed) served something planned last week"
            )
        }
    }

    func testARepeatWindowOnlyReachesBackAsFarAsItSays() throws {
        let old = try XCTUnwrap(meals.first { $0.tags.contains(.pizza) })
        let rules = [PlanningRule(title: "Varied", constraint: .noRepeatWithin(weeks: 2))]
        // Planned five weeks ago: outside the window, so it is allowed again.
        let taste = TasteProfile(weeksSinceLastPlanned: [old.id: 5])
        let saturdayPizza = [
            PlanningRule(title: "Pizza", constraint: .requiredOn(day: .day(.saturday), matcher: .tag(.pizza)))
        ]
        let result = generator(seed: 3).generate(
            preferredMeals: meals, allMeals: meals, rules: rules + saturdayPizza, taste: taste
        )
        XCTAssertTrue(cooked(result).contains { $0.tags.contains(.pizza) })
    }

    // MARK: - Bring it back

    /// Nothing matching has been planned inside the window, so the week must make room.
    func testRequiredEveryFitsAnOverdueCategoryIn() {
        let rules = [
            PlanningRule(title: "Soup sometimes", constraint: .requiredEvery(weeks: 3, matcher: .tag(.soup)))
        ]
        for seed in UInt64(0)..<15 {
            let result = generator(seed: seed).generate(preferredMeals: meals, allMeals: meals, rules: rules)
            XCTAssertTrue(
                cooked(result).contains { $0.tags.contains(.soup) },
                "Seed \(seed) left an overdue category out"
            )
        }
    }

    func testRequiredEveryStaysQuietWhenItWasRecentlyServed() throws {
        let soup = try XCTUnwrap(meals.first { $0.tags.contains(.soup) })
        let rules = [
            PlanningRule(title: "Soup sometimes", constraint: .requiredEvery(weeks: 4, matcher: .tag(.soup)))
        ]
        let taste = TasteProfile(weeksSinceLastPlanned: [soup.id: 1])
        let result = generator(seed: 11)
            .generate(preferredMeals: meals, allMeals: meals, rules: rules, taste: taste)
        XCTAssertTrue(result.conflicts.filter { $0.severity == .blocking }.isEmpty)
    }

    // MARK: - Ingredient rules

    func testAnIngredientRuleKeepsThatIngredientOffThePlan() {
        let rules = [
            PlanningRule(title: "No salmon", constraint: .excludedOn(day: .everyDay, matcher: .ingredient("salmon")))
        ]
        for seed in UInt64(0)..<15 {
            let result = generator(seed: seed).generate(preferredMeals: meals, allMeals: meals, rules: rules)
            for meal in cooked(result) {
                XCTAssertFalse(
                    meal.ingredients.contains { $0.name.localizedCaseInsensitiveContains("salmon") },
                    "Seed \(seed) served \(meal.name)"
                )
            }
        }
    }

    // MARK: - Scoped rules

    func testAWeekdayScopedTimeLimitAppliesToFiveDaysAtOnce() {
        let rules = [PlanningRule(title: "School nights", constraint: .maximumPrepTime(day: .weekdays, minutes: 30))]
        let result = generator(seed: 6).generate(preferredMeals: meals, allMeals: meals, rules: rules)
        for day in DayScope.weekdays.days() {
            guard let item = result.plan[day], item.kind == .meal, let id = item.mealID,
                  let meal = meals.first(where: { $0.id == id }) else { continue }
            XCTAssertLessThanOrEqual(meal.prepMinutes, 30, "\(day.name) took too long")
        }
    }

    // MARK: - The day plan as a rule

    func testADinnerModeRuleDecidesTheDayWithoutTouchingPlanThisDay() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        // These assertions concern upcoming dinners, regardless of the day CI runs.
        store.plan = store.plan.anchored(to: WeekAnchor.startOfNextWeek(after: store.plan.startDate))
        store.completeOnboarding()

        XCTAssertEqual(store.addRule(PlanningRule(
            title: "Eating out",
            constraint: .dinnerMode(day: .day(.friday), mode: .takeaway)
        )), .added)

        XCTAssertEqual(store.plan[.friday]?.kind, .takeaway)
        XCTAssertNotNil(store.dinnerModeRule(for: .friday))
        XCTAssertNil(store.dinnerModeRule(for: .monday))

        // Turning it off hands the day back.
        store.setRule(try XCTUnwrap(store.rules.last), enabled: false)
        XCTAssertEqual(store.plan[.friday]?.kind, .meal)
    }

    func testAWeekendScopedDinnerRuleCoversBothDays() throws {
        let (store, defaults, suite) = try makeStore(seed: 33)
        defer { defaults.removePersistentDomain(forName: suite) }
        // In Sunday-first locales, this week's Sunday may already be in the past.
        store.plan = store.plan.anchored(to: WeekAnchor.startOfNextWeek(after: store.plan.startDate))
        store.completeOnboarding()

        // "Saturday pizza" is a starter rule, and a dinner required on a day nobody is home
        // is a contradiction the store is right to refuse. Retire it first -- and read the
        // answer, rather than assuming the rule went in.
        let pizza = try XCTUnwrap(store.rules.first { rule in
            if case .requiredOn(_, .tag(.pizza)) = rule.constraint { return true }
            return false
        })
        store.setRule(pizza, enabled: false)

        XCTAssertEqual(
            store.addRule(PlanningRule(title: "Away", constraint: .dinnerMode(day: .weekend, mode: .away))),
            .added
        )
        XCTAssertEqual(store.plan[.saturday]?.kind, .away)
        XCTAssertEqual(store.plan[.sunday]?.kind, .away)
        XCTAssertEqual(store.plan[.monday]?.kind, .meal)
    }

    func testADinnerModeRulePreservesPastDinners() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.completeOnboarding()
        let previousWeek = try XCTUnwrap(Calendar.current.date(
            byAdding: .weekOfYear, value: -1, to: WeekAnchor.startOfCurrentWeek()
        ))
        store.plan = store.plan.anchored(to: previousWeek)
        let before = store.plan

        XCTAssertEqual(store.addRule(PlanningRule(
            title: "Friday takeaway", constraint: .dinnerMode(day: .day(.friday), mode: .takeaway)
        )), .added)

        XCTAssertNotNil(store.dinnerModeRule(for: .friday))
        XCTAssertEqual(store.plan, before, "A new standing rule must not rewrite past dinners")
    }

    // MARK: - Adding a rule

    func testTheSameRuleCannotBeAddedTwice() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.completeOnboarding()
        let before = store.rules.count

        let rule = PlanningRule(title: "Taco Friday", constraint: .requiredOn(day: .day(.friday), matcher: .tag(.taco)))
        XCTAssertEqual(store.addRule(rule), .added)
        guard case .duplicate = store.addRule(rule) else {
            return XCTFail("A second identical rule was accepted")
        }
        XCTAssertEqual(store.rules.count, before + 1)
    }

    func testAFlatContradictionIsRefusedAtTheMomentOfAsking() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.completeOnboarding()

        store.addRule(PlanningRule(title: "Taco Friday", constraint: .requiredOn(day: .day(.friday), matcher: .tag(.taco))))
        let opposite = PlanningRule(title: "No taco", constraint: .excludedOn(day: .weekdays, matcher: .tag(.taco)))
        guard case .contradiction = store.addRule(opposite) else {
            return XCTFail("A contradiction was accepted")
        }
        XCTAssertFalse(store.rules.contains { $0.title == "No taco" })
    }

    // MARK: - Pantry staples

    func testAStapleLeavesTheShoppingListAndStays() throws {
        let (store, defaults, suite) = try makeStore(seed: 44)
        defer { defaults.removePersistentDomain(forName: suite) }
        store.completeOnboarding()

        let item = try XCTUnwrap(store.groceryItems.first)
        store.toggleGroceryItem(item)
        store.setStaple(item, isStaple: true)

        XCTAssertFalse(store.groceryItems.contains { $0.id == item.id })
        XCTAssertFalse(store.stockedItems.contains { $0.id == item.id }, "A staple is not merely set aside")
        XCTAssertFalse(store.checkedGroceryIDs.contains(item.id), "Its tick goes with it")

        // Unlike setting something aside, it survives a whole new week.
        store.shuffleAll()
        XCTAssertFalse(store.groceryItems.contains { AppStore.stapleKey($0.name) == AppStore.stapleKey(item.name) })

        store.removeStaples([AppStore.stapleKey(item.name)])
        XCTAssertTrue(store.pantryStaples.isEmpty)
    }

    // MARK: - Cost

    // MARK: - History feeding the rules

    func testWeeksSinceLastPlannedReadsTheArchive() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.completeOnboarding()

        let meal = try XCTUnwrap(store.meals.first)
        let calendar = Calendar.current
        let twoWeeksAgo = calendar.date(
            byAdding: .weekOfYear, value: -2, to: WeekAnchor.startOfCurrentWeek()
        ) ?? .now
        store.archivedWeeks = [ArchivedWeek(plan: WeeklyPlan(
            startDate: twoWeeksAgo,
            meals: [PlannedMeal(day: .monday, mealID: meal.id, isLocked: false)]
        ))]

        XCTAssertEqual(store.weeksSinceLastPlanned[meal.id], 2)
    }
}
