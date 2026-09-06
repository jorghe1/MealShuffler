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

    func testLearnedPreferenceStillBiasesSelection() {
        let taco = meals.first { $0.name == "Taco" }!
        let neutral = mondayMeals(taste: .empty)
        let biased = mondayMeals(taste: TasteProfile(favoriteMealIDs: [taco.id], learnedScores: [taco.id: 10]))

        let neutralTacos = neutral.filter { $0 == taco.id }.count
        let biasedTacos = biased.filter { $0 == taco.id }.count
        XCTAssertGreaterThan(biasedTacos, neutralTacos, "Taste signals must still change the outcome")
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

    func testDislikedMealsArePenalisedInTheFallbackPool() {
        let salmon = meals.first { $0.tags.contains(.fish) }!
        // Only fish is allowed on Tuesday, so the pool is small and the penalty must show.
        let rules = [PlanningRule(title: "Fish Tuesday", constraint: .requiredOn(day: .tuesday, matcher: .tag(.fish)))]
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
