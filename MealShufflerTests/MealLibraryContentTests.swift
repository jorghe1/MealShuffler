import XCTest
@testable import MealShuffler

/// Invariants of the built-in library.
///
/// The library is data, and data drifts silently. These are the properties the rest of the
/// app quietly depends on: Cook Mode needs instructions, the starter rules need enough fish
/// and pizza to be satisfiable, and every id has to stay put or a household loses its
/// favourites and its history.
final class MealLibraryContentTests: XCTestCase {
    private let meals = SampleMeals.all

    func testTheLibraryIsBigEnoughToShuffle() {
        XCTAssertGreaterThanOrEqual(meals.count, 40)
    }

    func testEveryMealHasIdentity() {
        for meal in meals {
            XCTAssertFalse(meal.name.trimmingCharacters(in: .whitespaces).isEmpty)
            XCTAssertFalse(meal.subtitle.trimmingCharacters(in: .whitespaces).isEmpty)
            XCTAssertFalse(meal.emoji.isEmpty)
            XCTAssertFalse(meal.tags.isEmpty, "\(meal.name) has no tags, so no rule can ever match it")
            XCTAssertTrue(meal.isBuiltIn)
        }
    }

    func testIdsAreUnique() {
        XCTAssertEqual(Set(meals.map(\.id)).count, meals.count)
    }

    /// Favourites, history and customised copies all reference these. Renumbering them is
    /// indistinguishable from deleting somebody's library.
    func testTheOriginalFourteenIdsAreUnchanged() {
        for index in 1...14 {
            let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))
            XCTAssertNotNil(id)
            XCTAssertTrue(
                meals.contains { $0.id == id },
                "Meal id \(index) disappeared; existing installs reference it"
            )
        }
    }

    /// Cook Mode is a full screen with step progress, scaled ingredients and a screen that
    /// stays awake. Without this it answered "No steps saved for this meal" for every meal a
    /// new household had.
    func testEveryMealCanBeCooked() {
        for meal in meals {
            XCTAssertGreaterThanOrEqual(
                meal.instructions.count, 3,
                "\(meal.name) has too few steps for Cook Mode to be worth opening"
            )
            XCTAssertFalse(
                meal.instructions.contains { $0.trimmingCharacters(in: .whitespaces).isEmpty },
                "\(meal.name) has a blank step"
            )
        }
    }

    func testMealsStayWeeknightSized() {
        for meal in meals {
            XCTAssertTrue(
                (4...9).contains(meal.ingredients.count),
                "\(meal.name) has \(meal.ingredients.count) ingredients"
            )
            XCTAssertTrue((10...90).contains(meal.prepMinutes), "\(meal.name) takes \(meal.prepMinutes) min")
            if meal.tags.contains(.quick) {
                XCTAssertLessThanOrEqual(meal.prepMinutes, 25, "\(meal.name) is tagged quick")
            }
        }
    }

    func testIngredientsAreShoppable() {
        for meal in meals {
            for ingredient in meal.ingredients {
                XCTAssertFalse(ingredient.name.trimmingCharacters(in: .whitespaces).isEmpty)
                XCTAssertGreaterThan(ingredient.quantity, 0, "\(meal.name): \(ingredient.name)")
            }
        }
    }

    /// The same ingredient must carry the same aisle everywhere, or the grocery list shows
    /// "Potatoes" twice under two different headings.
    func testAnIngredientAlwaysComesFromTheSameAisle() {
        var aisles: [String: GroceryAisle] = [:]
        for meal in meals {
            for ingredient in meal.ingredients {
                let key = ingredient.name.lowercased()
                if let known = aisles[key] {
                    XCTAssertEqual(known, ingredient.aisle, "\(ingredient.name) is filed in two aisles")
                } else {
                    aisles[key] = ingredient.aisle
                }
            }
        }
    }

    // MARK: - Enough of everything for the rules that ship

    func testTheStarterRulesAreSatisfiableWithRoomToSpare() {
        let fish = meals.filter { $0.tags.contains(.fish) }
        let pizza = meals.filter { $0.tags.contains(.pizza) }
        let chicken = meals.filter { $0.tags.contains(.chicken) }

        // Fish is required on two named days, and a week must not repeat a meal.
        XCTAssertGreaterThanOrEqual(fish.count, 4, "Two fish days with no repeats needs real choice")
        // Saturday used to be pinned to a single pizza for the life of the install.
        XCTAssertGreaterThanOrEqual(pizza.count, 3, "Saturday should not be the same dinner every week")
        XCTAssertGreaterThanOrEqual(chicken.count, 4)
    }

    func testEveryTagCanBeCookedAtLeastTwice() {
        for tag in MealTag.allCases {
            let count = meals.filter { $0.tags.contains(tag) }.count
            XCTAssertGreaterThanOrEqual(
                count, 2,
                "\(tag.rawValue) has \(count) meals, so a rule about it has almost no choice"
            )
        }
    }

    /// Enough non-repeating dinners to fill a week without reaching for the relaxed pool.
    func testAWeekOfStarterRulesGeneratesCleanlyAcrossManySeeds() {
        let rules = PlanningRule.starterRules()
        for seed in UInt64(0)..<40 {
            let generator = MealPlanGenerator(random: SeededRandomSource(seed: seed &* 2_654_435_761))
            let result = generator.generate(preferredMeals: meals, allMeals: meals, rules: rules)

            let cooked = result.plan.meals.compactMap { $0.kind == .meal ? $0.mealID : nil }
            XCTAssertEqual(cooked.count, 7, "Seed \(seed) left a day unplanned")
            XCTAssertEqual(Set(cooked).count, 7, "Seed \(seed) repeated a dinner")
            XCTAssertTrue(
                result.conflicts.filter { $0.severity == .blocking }.isEmpty,
                "Seed \(seed): \(result.conflicts.map(\.message))"
            )
        }
    }

    /// Forty meals is only worth having if the shuffle actually reaches them.
    func testShufflingReachesMostOfTheLibraryOverAMonth() {
        var seen = Set<UUID>()
        for seed in UInt64(0)..<40 {
            let generator = MealPlanGenerator(random: SeededRandomSource(seed: seed &* 6_364_136_223))
            let result = generator.generate(preferredMeals: meals, allMeals: meals, rules: [])
            seen.formUnion(result.plan.meals.compactMap { $0.mealID })
        }
        XCTAssertGreaterThanOrEqual(
            seen.count, meals.count / 2,
            "Only \(seen.count) of \(meals.count) meals ever appeared"
        )
    }

    // MARK: - Composition

    func testCategoryPrecedenceFollowsTheProtein() {
        for meal in meals {
            let category = WeekCompositionView.Category.of(meal)
            switch category {
            case .fish: XCTAssertTrue(meal.tags.contains(.fish))
            case .chicken: XCTAssertTrue(meal.tags.contains(.chicken))
            case .meat: XCTAssertTrue(meal.tags.contains(.meat))
            case .vegetarian: XCTAssertTrue(meal.tags.contains(.vegetarian))
            case .other:
                XCTAssertTrue(meal.tags.isDisjoint(with: [.fish, .chicken, .meat, .vegetarian]))
            }
        }
    }

    func testSearchLooksInsideIngredients() {
        let spinachDishes = meals.filter { $0.matches(searchText: "spinach") }
        XCTAssertFalse(spinachDishes.isEmpty, "\"What can I make with spinach\" is the real question")
        XCTAssertTrue(meals.allSatisfy { $0.matches(searchText: "") }, "An empty search hides nothing")
    }

    func testFiltersSelectWhatTheyClaimTo() {
        let favourites: Set<UUID> = meals.first.map { [$0.id] } ?? []

        XCTAssertTrue(meals.allSatisfy { MealFilter.all.matches($0, favorites: favourites) })
        XCTAssertEqual(meals.filter { MealFilter.favourites.matches($0, favorites: favourites) }.count, 1)
        XCTAssertTrue(
            meals.filter { MealFilter.mine.matches($0, favorites: favourites) }.isEmpty,
            "Nothing built in is the household's own"
        )
    }
}
