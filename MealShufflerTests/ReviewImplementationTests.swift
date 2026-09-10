import XCTest
@testable import MealShuffler

@MainActor
final class ReviewImplementationTests: XCTestCase {
    func testNorwegianOvenTemperatureIsNeverARecipeYield() throws {
        let draft = try RecipeTextStructurer.draft(fromPastedText: "Suppe\nIngredienser\n1 løk\nSlik gjør du\nVarm ovnen til 200 grader.")
        XCTAssertFalse(draft.servingsConfirmed)
        XCTAssertNotEqual(draft.servings, 200)
    }

    func testPrepTimeIsDistinctFromTotalTimeAndHoursAreAdded() {
        let prep = RecipeTextStructurer.metadata(in: "Forberedelsestid: 15 minutter\nSteketid: 40 minutter")
        XCTAssertNil(prep.minutes)
        XCTAssertEqual(prep.activeMinutes, 15)
        let total = RecipeTextStructurer.metadata(in: "Serves 6\nTotal time: 1 hour 30 minutes\nPrep time: 1 minute")
        XCTAssertEqual(total.minutes, 90)
        XCTAssertEqual(total.activeMinutes, 1)
        XCTAssertEqual(total.servings, 6)
    }

    func testNorwegianPackagesAndMissingAmountsRemainDistinct() throws {
        let tomatoes = try XCTUnwrap(IngredientParser.parse("2 bokser à 400 g tomater"))
        XCTAssertEqual(tomatoes.quantity, 2)
        XCTAssertEqual(tomatoes.unit, "bokser")
        XCTAssertEqual(tomatoes.packageQuantity, 400)
        XCTAssertEqual(tomatoes.packageUnit, "g")
        XCTAssertEqual(IngredientUnits.normalize(quantity: 2, unit: "flasker").unit, "bottle")
        let unknown = try XCTUnwrap(IngredientParser.parse("Salt"))
        let taste = try XCTUnwrap(IngredientParser.parse("Salt etter smak"))
        XCTAssertNil(unknown.amountNote)
        XCTAssertEqual(taste.amountNote, L10n.string("To taste"))
        XCTAssertEqual(unknown.name, taste.name)
    }

    func testWrappedIngredientQuantityJoinsItsName() throws {
        let draft = try RecipeTextStructurer.draft(fromPastedText: "Soup\nIngredients\n400 g\ntomatoes\nMethod\nSimmer.")
        XCTAssertEqual(draft.parsedIngredients?.count, 1)
        XCTAssertEqual(draft.parsedIngredients?.first?.quantity, 400)
        XCTAssertEqual(draft.parsedIngredients?.first?.name, "Tomatoes")
    }

    func testPageIdentityWinsOverLongerRelatedRecipe() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/soup?utm_source=email"))
        let html = #"<script type="application/ld+json">[{"@type":"Recipe","url":"https://example.com/soup","name":"Soup","recipeIngredient":["1 onion"]},{"@type":"Recipe","url":"https://example.com/other","name":"Other","recipeIngredient":["1 egg","1 apple","2 carrots"]}]</script>"#
        XCTAssertEqual(RecipeImportService.extractRecipeObject(from: html, pageURL: url)?["name"] as? String, "Soup")
        XCTAssertEqual(RecipeURLIdentity.normalized(url), "https://example.com/soup")
    }

    func testFractionalPortionsScaleShoppingAcrossRecipeYields() {
        let recipe = Meal(name: "Soup", subtitle: "", emoji: "", prepMinutes: 20, tags: [],
            ingredients: [Ingredient(name: "Tomatoes", quantity: 800, unit: "g", aisle: .produce)], defaultServings: 4)
        for portions in [1.0, 1.5, 2, 4, 6] {
            let item = PlannedMeal(day: .monday, mealID: recipe.id, isLocked: false, servings: 4, portionScale: portions / 4)
            let list = GroceryListBuilder.build(plan: WeeklyPlan(meals: [item]), meals: [recipe])
            XCTAssertEqual(list.first?.quantity, portions * 200)
        }
    }

    func testAutomaticLeftoversChooseCapacityRatherThanJustTheNewestMeal() {
        let a = SampleMeals.all[0], b = SampleMeals.all[1]
        let plan = WeeklyPlan(meals: [
            PlannedMeal(day: .monday, mealID: a.id, isLocked: true, servings: 8),
            PlannedMeal(day: .tuesday, mealID: b.id, isLocked: true, servings: 4),
            PlannedMeal(day: .wednesday, mealID: b.id, isLocked: false, servings: 4, kind: .leftovers(sourceDay: .tuesday))
        ])
        let contexts: [Weekday: DayPlanContext] = [.monday: DayPlanContext(diners: 4, extraServings: 4), .tuesday: DayPlanContext(diners: 4), .wednesday: DayPlanContext(mode: .leftovers)]
        let resolved = MealPlanGenerator(orderedDays: [.monday, .tuesday, .wednesday]).resolvingLeftovers(in: plan, contexts: contexts, allMeals: [a, b])
        XCTAssertEqual(resolved[.wednesday]?.mealID, a.id)
        XCTAssertEqual(resolved[.wednesday]?.kind, .leftovers(sourceDay: .monday))
    }

    func testConsecutiveRuleIncludesThePreviousWeek() {
        let fish = SampleMeals.all.first { $0.tags.contains(.fish) }!
        let rule = PlanningRule(title: "Spread fish", constraint: .notOnConsecutiveDays(matcher: .tag(.fish)))
        let plan = WeeklyPlan(meals: [PlannedMeal(day: .monday, mealID: fish.id, isLocked: true)])
        let result = MealPlanGenerator(orderedDays: [.monday]).validate(plan: plan, allMeals: [fish], rules: [rule], contexts: [:], taste: TasteProfile(previousWeekDinner: fish), context: .empty)
        XCTAssertTrue(result.contains { $0.ruleID == rule.id })
    }

    func testFreezerReservationsDoNotCreateGroceriesAndDetectShortages() {
        let recipe = SampleMeals.all[0]
        let batch = FreezerBatch(recipe: recipe, portions: 3, label: "Soup")
        var item = PlannedMeal(day: .monday, mealID: recipe.id, isLocked: true, servings: 4, kind: .leftovers(sourceDay: .monday))
        item.freezerBatch = batch
        let plan = WeeklyPlan(meals: [item])
        XCTAssertTrue(GroceryListBuilder.build(plan: plan, meals: [recipe]).isEmpty)
        let problems = MealPlanGenerator(orderedDays: [.monday]).validate(plan: plan, allMeals: [recipe], rules: [], contexts: [:], taste: TasteProfile(freezerBatches: [batch]), context: .empty)
        XCTAssertEqual(problems.count, 1)
    }

    func testExportIncludesEveryDatedDayEvenWhenUnplanned() {
        let plan = WeeklyPlan(meals: [])
        let text = PlanTextExporter.weeklyPlan(plan, meals: [])
        XCTAssertEqual(text.components(separatedBy: L10n.string("Not planned")).count - 1, 7)
        XCTAssertTrue(text.contains(WeekAnchor.label(forWeekStarting: plan.startDate)))
    }

    func testNorwegianTakeawaySentenceAndSingularGrammar() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "nb", ofType: "lproj"))
        let bundle = try XCTUnwrap(Bundle(path: path))
        let format = bundle.localizedString(forKey: "We order takeaway %@.", value: nil, table: nil)
        let day = bundle.localizedString(forKey: "on Mondays", value: nil, table: nil)
        XCTAssertEqual(String(format: format, day), "Vi bestiller takeaway på mandager.")
        XCTAssertEqual(bundle.localizedString(forKey: "%ld serving", value: nil, table: nil), "%ld porsjon")
        XCTAssertEqual(bundle.localizedString(forKey: "unit.clove", value: nil, table: nil), "fedd")
    }

    @MainActor func testDatedCookingIsIdempotentAndShufflePreservesIt() throws {
        let store = try makeStore()
        store.rules = []; store.shuffleAll()
        let day = try XCTUnwrap(Weekday.ordered().first { Calendar.current.isDateInToday(store.plan.date(for: $0)) })
        let recipe = try XCTUnwrap(store.plan[day]?.mealID.flatMap { store.meal(id: $0) })
        let date = store.plan.date(for: day)
        store.handleReminderAction(.cooked(mealID: recipe.id, day: day, date: date))
        store.handleReminderAction(.cooked(mealID: recipe.id, day: day, date: date))
        XCTAssertEqual(store.feedbackEvents.filter { $0.kind == .cooked }.count, 1)
        store.shuffleAll()
        XCTAssertEqual(store.plan[day]?.mealID, recipe.id)
        let before = store.plan
        store.handleReminderAction(.somethingElse(mealID: recipe.id, day: day, date: date.addingTimeInterval(-7 * 86400)))
        XCTAssertEqual(store.plan, before)
    }

    @MainActor func testFullBackupRoundTripAndPersonalSyncState() throws {
        let store = try makeStore()
        store.rules = []; store.shuffleAll()
        store.householdTools.dinnerHour = 19
        store.householdTools.cooking["example"] = CookingProgress(step: 2, gathered: ["salt"])
        let state = store.makeSnapshot()
        let document = try DeviceBackupDocument(state: state, files: [:])
        let restored = try DeviceBackupDocument(wrapper: document.wrapper())
        XCTAssertEqual(restored.state.tools, state.tools)
        var remote = state
        remote.tools.cooking = [:]
        XCTAssertTrue(CloudHouseholdSync.equivalent(state, remote), "Cooking progress is personal")
        remote.tools.dinnerHour = 20
        XCTAssertFalse(CloudHouseholdSync.equivalent(state, remote), "Household dinner time is shared")
        XCTAssertFalse(DeviceBackupDocument.validName("library__../state.json"))
    }

    @MainActor func testDeletingCustomizationHidesStarterUntilExplicitReset() throws {
        let store = try makeStore()
        let original = SampleMeals.all[0]
        store.deleteMeal(original)
        XCTAssertFalse(store.meals.contains { $0.id == original.id })
        store.resetRecipeToOriginal(original)
        XCTAssertTrue(store.meals.contains { $0.id == original.id })
    }

    func testMissingFreezerBatchDoesNotSelectOrdinaryLeftovers() {
        let recipe = SampleMeals.all[0]
        let context = DayPlanContext(mode: .leftovers, freezerBatchID: UUID())
        let plan = WeeklyPlan(meals: [PlannedMeal(day: .monday, mealID: recipe.id, isLocked: true, servings: 8)])
        let result = MealPlanGenerator(orderedDays: [.monday, .tuesday]).generate(preferredMeals: [recipe], allMeals: [recipe], rules: [], contexts: [.tuesday: context], existingPlan: plan)
        XCTAssertNil(result.plan[.tuesday]?.mealID)
        XCTAssertFalse(result.conflicts.isEmpty)
    }

    func testRemovedMemberLosesPreferencesRulesAndAttendanceInBothWeeks() throws {
        let store = try makeStore()
        store.addHouseholdMember(named: "Emma")
        let index = store.household.members.count - 1
        let member = store.household.members[index]
        let recipe = SampleMeals.all[0]
        store.setPreference(.disliked, for: recipe, member: member.id)
        store.rules = [PlanningRule(title: "Emma", constraint: .excludedOn(day: .everyDay, matcher: .dislikedBy(memberID: member.id)))]
        store.dayContexts[.monday] = DayPlanContext(attendingMemberIDs: [member.id])
        store.nextWeekContexts[.monday] = DayPlanContext(attendingMemberIDs: [member.id])
        store.removeHouseholdMembers(at: IndexSet(integer: index))
        XCTAssertNil(store.memberPreferences[member.id])
        XCTAssertTrue(store.rules.isEmpty)
        XCTAssertFalse(store.dayContexts[.monday]?.attendingMemberIDs?.contains(member.id) ?? true)
        XCTAssertFalse(store.nextWeekContexts[.monday]?.attendingMemberIDs?.contains(member.id) ?? true)
    }

    func testFreezerCookingAndUndoRestoreTheSameInventory() throws {
        let store = try makeStore()
        let recipe = SampleMeals.all[0]
        let batch = FreezerBatch(recipe: recipe, portions: 6, label: "Dinner")
        store.householdTools.freezer = [batch]
        var item = PlannedMeal(day: .monday, mealID: recipe.id, isLocked: true, servings: 4, kind: .leftovers(sourceDay: .monday))
        item.freezerBatch = batch
        store.plan = WeeklyPlan(meals: [item])
        store.markCooked(recipe, on: .monday)
        XCTAssertEqual(store.householdTools.freezer.first?.portions, 2)
        store.undoLastChange()
        XCTAssertEqual(store.householdTools.freezer.first?.portions, 6)
        XCTAssertFalse(store.isCompleted(on: .monday))
        store.markCooked(recipe, on: .monday)
        store.clearCompletion(on: .monday)
        XCTAssertEqual(store.householdTools.freezer.first?.portions, 6)
    }

    func testLateDraftWritesCannotReplaceNewerDraftOrResurrectSavedRecipe() throws {
        var draft = ImportedRecipeDraft(name: "Earlier")
        defer { RecipeLibraryStorage.removeDraft(draft.id) }
        let earlier = RecipeLibraryStorage.beginDraftSave(draft.id)
        draft.name = "Latest"
        try RecipeLibraryStorage.saveDraft(draft)
        var stale = draft; stale.name = "Earlier"
        try RecipeLibraryStorage.saveDraft(stale, revision: earlier)
        XCTAssertEqual(RecipeLibraryStorage.drafts().first { $0.id == draft.id }?.name, "Latest")
        RecipeLibraryStorage.removeDraft(draft.id)
        try RecipeLibraryStorage.saveDraft(stale, revision: earlier)
        XCTAssertFalse(RecipeLibraryStorage.drafts().contains { $0.id == draft.id })
    }

    func testInvalidIngredientRangeRetainsReviewFlagThroughCodable() throws {
        let ingredient = try XCTUnwrap(IngredientParser.parse("4–2 g salt"))
        XCTAssertTrue(ingredient.needsAmountReview)
        XCTAssertFalse(ingredient.hasKnownQuantity)
        let restored = try JSONDecoder().decode(Ingredient.self, from: JSONEncoder().encode(ingredient))
        XCTAssertTrue(restored.requiresReview == true)
    }

    func testRuleChangesRevalidateNextWeekWithoutReplacingItsChoices() throws {
        let store = try makeStore()
        store.rules = []
        store.planNextWeek()
        let fish = try XCTUnwrap(store.meals.first { $0.tags.contains(.fish) })
        store.setNextWeekMeal(fish, on: .monday)
        let original = store.nextWeekPlan
        let rule = PlanningRule(title: "No fish", constraint: .excludedOn(day: .everyDay, matcher: .tag(.fish)))
        XCTAssertEqual(store.addRule(rule), .added)
        XCTAssertEqual(store.nextWeekPlan, original)
        XCTAssertTrue(store.nextWeekConflicts.contains { $0.ruleID == rule.id })
    }

    func testInactiveShoppingPeriodReopensItemsWhoseAmountsIncreased() throws {
        let store = try makeStore()
        let recipe = SampleMeals.all[0]
        store.rules = []
        store.plan = WeeklyPlan(meals: [PlannedMeal(day: .monday, mealID: recipe.id, isLocked: true, servings: 4)])
        let start = store.plan.startDate
        let end = Calendar.current.date(byAdding: .day, value: 6, to: start)!
        store.setShoppingPeriod(from: start, through: end)
        let item = try XCTUnwrap(store.groceryItems.first { $0.quantity > 0 })
        store.toggleGroceryItem(item)
        store.setShoppingPeriod(from: start.addingTimeInterval(7 * 86400), through: end.addingTimeInterval(7 * 86400))
        store.plan[.monday]?.servings = 8
        store.setShoppingPeriod(from: start, through: end)
        XCTAssertFalse(store.checkedGroceryIDs.contains(item.id))
    }

    func testFixedEnglishAndNorwegianMetadataCorpus() {
        let cases: [(String, Int?, Int?, Int?)] = [
            ("Forvarm ovnen til 200 grader.", nil, nil, nil),
            ("Til 6 personer", 6, nil, nil),
            ("Porsjoner: 4", 4, nil, nil),
            ("Serves 2", 2, nil, nil),
            ("Total time: 1 hour 30 minutes", nil, 90, nil),
            ("Totalt: 1 time og 15 minutter", nil, 75, nil),
            ("Prep time: 15 minutes", nil, nil, 15),
            ("Forberedelsestid: 10 minutter\nSteketid: 40 minutter", nil, nil, 10)
        ]
        for (source, servings, total, active) in cases {
            let actual = RecipeTextStructurer.metadata(in: source)
            XCTAssertEqual(actual.servings, servings, source)
            XCTAssertEqual(actual.minutes, total, source)
            XCTAssertEqual(actual.activeMinutes, active, source)
        }
    }

    @MainActor private func makeStore() throws -> AppStore {
        let name = "ReviewImplementationTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return AppStore(defaults: defaults, random: SeededRandomSource(seed: 19))
    }
}
