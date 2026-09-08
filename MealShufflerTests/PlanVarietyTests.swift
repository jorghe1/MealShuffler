import XCTest
@testable import MealShuffler

/// Guards the property the app is named after: that shuffling actually varies.
///
/// The previous scorer took `max(by:)` over scores carrying only a small random jitter, so a
/// household with a few weeks of history converged on one meal per day. These tests pin the
/// sampling with a seeded source so the assertions are reproducible.
final class PlanVarietyTests: XCTestCase {
    private let meals = SampleMeals.all

    private func generator(seed: UInt64) -> MealPlanGenerator {
        MealPlanGenerator(random: SeededRandomSource(seed: seed))
    }

    private func mondayMeals(taste: TasteProfile, runs: Int = 60) -> [UUID] {
        (0..<runs).compactMap { seed in
            let result = generator(seed: UInt64(seed) &* 2_654_435_761)
                .generate(preferredMeals: meals, allMeals: meals, rules: [], taste: taste)
            return result.plan[.monday]?.mealID
        }
    }

    /// How many of `runs` generated weeks contain `mealID` on any day.
    ///
    /// Seven observations per generated week instead of one, which is what makes a taste
    /// signal measurable. Sampling a single weekday was fine against fourteen meals, where a
    /// favourite landed on Monday about a third of the time; against forty it lands there
    /// twice in sixty weeks, and comparing two numbers that small is a coin toss.
    private func weeksContaining(_ mealID: UUID, taste: TasteProfile, runs: Int) -> Int {
        (0..<runs).filter { seed in
            let result = generator(seed: UInt64(seed) &* 2_654_435_761)
                .generate(preferredMeals: meals, allMeals: meals, rules: [], taste: taste)
            return result.plan.meals.contains { $0.mealID == mealID }
        }.count
    }

    /// Share of the single most frequently chosen meal.
    private func topShare(_ picks: [UUID]) -> Double {
        guard !picks.isEmpty else { return 1 }
        let counts = Dictionary(picks.map { ($0, 1) }, uniquingKeysWith: +)
        return Double(counts.values.max() ?? 0) / Double(picks.count)
    }

    func testShuffleStaysVariedForAHouseholdWithStrongHistory() {
        let taco = meals.first { $0.name == "Taco" }!
        let bolognese = meals.first { $0.name == "Spaghetti bolognese" }!
        // The profile that used to collapse selection onto a single meal.
        let taste = TasteProfile(
            favoriteMealIDs: [taco.id],
            learnedScores: [taco.id: 10, bolognese.id: 8]
        )

        let picks = mondayMeals(taste: taste)
        XCTAssertEqual(picks.count, 60)
        XCTAssertGreaterThanOrEqual(Set(picks).count, 4, "A strong profile should still reach several meals")
        XCTAssertLessThan(topShare(picks), 0.75, "No single meal should dominate the shuffle")
    }

    /// A hearted, often-cooked meal must reach the table more often than an anonymous one.
    ///
    /// Measured over whole weeks with a margin, not as a bare greater-than on two counts:
    /// favourite (+18) and a full learned score (10 x 3) is +48, which at the scorer's
    /// temperature of 30 is roughly a five-fold weight. That is a large, real effect and it
    /// should clear the margin comfortably -- while a genuine regression, where the signal
    /// stops reaching the scorer at all, lands the two counts on top of each other and fails.
    func testLearnedPreferenceStillBiasesSelection() {
        let taco = meals.first { $0.name == "Taco" }!
        let runs = 150

        let neutral = weeksContaining(taco.id, taste: .empty, runs: runs)
        let biased = weeksContaining(
            taco.id,
            taste: TasteProfile(favoriteMealIDs: [taco.id], learnedScores: [taco.id: 10]),
            runs: runs
        )

        XCTAssertGreaterThan(
            biased, neutral + runs / 20,
            "Taste signals must still change the outcome: \(taco.name) reached "
                + "\(neutral) of \(runs) neutral weeks and \(biased) of \(runs) biased ones"
        )
    }

    func testSameSeedProducesSamePlan() {
        let first = generator(seed: 99).generate(preferredMeals: meals, allMeals: meals, rules: [])
        let second = generator(seed: 99).generate(preferredMeals: meals, allMeals: meals, rules: [])
        XCTAssertEqual(first.plan, second.plan)
    }

    func testWeekDoesNotRepeatAMealWhenTheLibraryIsLargeEnough() {
        for seed in UInt64(0)..<20 {
            let result = generator(seed: seed).generate(preferredMeals: meals, allMeals: meals, rules: [])
            let cooked = result.plan.meals.compactMap { $0.kind == .meal ? $0.mealID : nil }
            XCTAssertEqual(Set(cooked).count, cooked.count, "Seed \(seed) repeated a meal within one week")
        }
    }

    /// The flip side of making no-repeat a hard constraint: a library too small to fill a
    /// week must still produce seven dinners, not five and two blanks.
    func testASmallLibraryStillFillsTheWeek() throws {
        let threeMeals = Array(meals.prefix(3))
        for seed in UInt64(0)..<10 {
            let result = generator(seed: seed)
                .generate(preferredMeals: threeMeals, allMeals: threeMeals, rules: [])
            let cooked = result.plan.meals.compactMap { $0.kind == .meal ? $0.mealID : nil }
            XCTAssertEqual(cooked.count, 7, "Seed \(seed) left a day unplanned")
            XCTAssertTrue(
                cooked.allSatisfy { id in threeMeals.contains { $0.id == id } },
                "Only meals from the library may be planned"
            )
        }
    }

    /// A required rule outranks the no-repeat constraint. If the only meal that satisfies
    /// Saturday's rule was already used earlier, it is used again rather than breaking
    /// the rule.
    func testARequiredRuleWinsOverAvoidingARepeat() throws {
        let pizza = try XCTUnwrap(meals.first { $0.tags.contains(.pizza) })
        let rules = [
            PlanningRule(title: "Pizza Friday", constraint: .requiredOn(day: .day(.friday), matcher: .exactMeal(pizza.id))),
            PlanningRule(title: "Pizza Saturday", constraint: .requiredOn(day: .day(.saturday), matcher: .exactMeal(pizza.id)))
        ]
        let result = generator(seed: 42).generate(preferredMeals: meals, allMeals: meals, rules: rules)
        XCTAssertEqual(result.plan[.friday]?.mealID, pizza.id)
        XCTAssertEqual(result.plan[.saturday]?.mealID, pizza.id)
        XCTAssertTrue(result.conflicts.isEmpty, "Satisfying both rules is not a conflict")
    }

    func testDislikedMealsArePenalisedInTheFallbackPool() {
        let salmon = meals.first { $0.tags.contains(.fish) }!
        // Only fish is allowed on Tuesday, so the pool is small and the penalty must show.
        let rules = [PlanningRule(title: "Fish Tuesday", constraint: .requiredOn(day: .day(.tuesday), matcher: .tag(.fish)))]
        var picks: [UUID] = []
        for seed in UInt64(0)..<40 {
            let result = generator(seed: seed).generate(
                preferredMeals: meals,
                allMeals: meals,
                rules: rules,
                taste: TasteProfile(dislikedMealIDs: [salmon.id])
            )
            if let id = result.plan[.tuesday]?.mealID { picks.append(id) }
        }
        XCTAssertFalse(picks.isEmpty)
        let salmonShare = Double(picks.filter { $0 == salmon.id }.count) / Double(picks.count)
        XCTAssertLessThan(salmonShare, 0.4, "A disliked meal should be uncommon even when it fits the rule")
    }
}
