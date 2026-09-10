import XCTest
@testable import MealShuffler

final class RecipeReliabilityTests: XCTestCase {
    func testBackupRejectsInvalidScalingAndUnsafeImagePaths() throws {
        var meal = Meal(name: "Soup", subtitle: "", emoji: "", prepMinutes: 20, tags: [],
                        ingredients: [Ingredient(name: "Salt", quantity: -1, unit: "g", aisle: .pantry)])
        XCTAssertThrowsError(try RecipeLibraryArchive(meals: [meal], images: [:]).validate())
        meal = SampleMeals.all[0]
        XCTAssertThrowsError(try RecipeLibraryArchive(meals: [meal], images: ["../source-photo.jpg": Data()]).validate())
        XCTAssertNoThrow(try RecipeLibraryArchive(meals: [meal], images: [:]).validate())
    }

    func testArchivedRecipeRetainsIngredientsAfterLibraryChanges() throws {
        let original = SampleMeals.all[0]
        let plan = WeeklyPlan(meals: [PlannedMeal(day: .monday, mealID: original.id, isLocked: false)])
        let archive = ArchivedWeek(plan: plan, recipes: [original])
        let restored = try JSONDecoder().decode(ArchivedWeek.self, from: JSONEncoder().encode(archive))
        XCTAssertEqual(restored.recipeSnapshots?.first?.ingredients, original.ingredients)
    }
    func testMixedFractionsAndAttachedUnits() throws {
        let flour = try XCTUnwrap(IngredientParser.parse("1 1/2 cups flour"))
        XCTAssertEqual(flour.quantity, 1.5)
        XCTAssertEqual(flour.unit, "cups")
        XCTAssertEqual(flour.name, "Flour")
        XCTAssertEqual(IngredientParser.parse("1½ cups flour")?.quantity, 1.5)
        let chicken = try XCTUnwrap(IngredientParser.parse("• 500g chicken"))
        XCTAssertEqual(chicken.quantity, 500)
        XCTAssertEqual(chicken.unit, "g")
        XCTAssertEqual(chicken.name, "Chicken")
    }

    func testRangesPackagesAndMissingAmounts() throws {
        let garlic = try XCTUnwrap(IngredientParser.parse("2–3 cloves garlic"))
        XCTAssertEqual(garlic.quantity, 2)
        XCTAssertEqual(garlic.upperQuantity, 3)
        let cans = try XCTUnwrap(IngredientParser.parse("2 × 400 g cans tomatoes"))
        XCTAssertEqual(cans.quantity, 2)
        XCTAssertEqual(cans.packageQuantity, 400)
        XCTAssertEqual(cans.packageUnit, "g")
        XCTAssertEqual(cans.unit, "cans")
        let salt = try XCTUnwrap(IngredientParser.parse("Salt to taste"))
        XCTAssertFalse(salt.hasKnownQuantity)
        XCTAssertEqual(salt.quantity, 0)
        XCTAssertEqual(salt.originalText, "Salt to taste")
    }

    func testYieldAndTimeSurviveTextExtraction() throws {
        let draft = try RecipeTextStructurer.draft(fromPastedText: """
        Tomato soup
        Serves 2
        Total time: 45 minutes
        Ingredients
        400 g tomatoes
        Method
        Simmer.
        """)
        XCTAssertEqual(draft.servings, 2)
        XCTAssertTrue(draft.servingsConfirmed)
        XCTAssertEqual(draft.prepMinutes, 45)
        XCTAssertEqual(draft.instructions, ["Simmer."])
    }

    func testMissingYieldRequiresReview() throws {
        let draft = try RecipeTextStructurer.draft(fromPastedText: "Soup\nIngredients\n1 onion\nMethod\nCook.")
        XCTAssertFalse(draft.servingsConfirmed)
    }

    func testEditingOneLinePreservesOtherCorrectionsAndPrecision() {
        let precise = Ingredient(name: "Salt", quantity: 0.123456, unit: "g", aisle: .produce)
        let lines = [precise.editableLine, "2 eggs"]
        let ingredients = [precise, Ingredient(name: "Eggs", quantity: 2, unit: "", aisle: .dairy)]
        let result = IngredientParser.reconcile(lines: [lines[0], "3 eggs"], originalLines: lines, ingredients: ingredients)
        XCTAssertEqual(result[0], precise)
        XCTAssertEqual(result[1].quantity, 3)
    }

    func testRepeatedIngredientRowsHaveDistinctIdentityAndRoundTrip() throws {
        let rows = IngredientParser.parse(lines: ["Sauce:", "1 g salt", "Filling:", "1 g salt"])
        XCTAssertEqual(rows.count, 2)
        XCTAssertNotEqual(rows[0].id, rows[1].id)
        XCTAssertEqual(rows.map(\.section), ["Sauce", "Filling"])
        XCTAssertEqual(try JSONDecoder().decode([Ingredient].self, from: JSONEncoder().encode(rows)), rows)
    }

    func testNormalizedManualItemsMergeAndRemainIdentifiable() {
        let meal = Meal(name: "Bread", subtitle: "", emoji: "", prepMinutes: 20, tags: [],
                        ingredients: [Ingredient(name: "Flour", quantity: 500, unit: "g", aisle: .pantry)])
        let manual = ManualGroceryItem(name: "Flour", quantity: 1, unit: "kg", aisle: .pantry)
        let plan = WeeklyPlan(meals: [PlannedMeal(day: .monday, mealID: meal.id, isLocked: false)])
        let list = GroceryListBuilder.build(plan: plan, meals: [meal], manualItems: [manual])
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.quantity, 1500)
        XCTAssertEqual(list.first?.id, manual.groceryID)
    }
}
