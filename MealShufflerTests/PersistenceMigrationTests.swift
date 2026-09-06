import XCTest
@testable import MealShuffler

/// Migrations are the one thing that gets more expensive with every installed user, so the
/// v1 -> v2 path is pinned here.
///
/// The legacy payload is built from v1-shaped `Encodable` mirrors rather than a JSON string
/// literal: Swift encodes dictionaries with non-string keys as flat arrays, so a hand-written
/// fixture would be testing the author's memory of that rule instead of the migration.
final class PersistenceMigrationTests: XCTestCase {
    private let stateKey = "meal-shuffler-state-v1"

    // MARK: - v1 shapes

    /// The plan as it was before the week carried a date.
    private struct LegacyPlan: Encodable {
        let meals: [PlannedMeal]
    }

    /// The meal as it was before sync stamps and the currency rename.
    private struct LegacyMeal: Encodable {
        let id: UUID
        let name: String
        let subtitle: String
        let emoji: String
        let prepMinutes: Int
        let tags: Set<MealTag>
        let ingredients: [Ingredient]
        let defaultServings: Int
        let estimatedCostNOK: Int
        let instructions: [String]
        let source: MealSource
    }

    private struct LegacyState: Encodable {
        let hasCompletedOnboarding: Bool
        let preferences: [UUID: MealPreference]
        let rules: [PlanningRule]
        let plan: LegacyPlan
        let checkedGroceryIDs: Set<String>
        let customMeals: [LegacyMeal]
        let favoriteMealIDs: Set<UUID>
        let dayContexts: [Weekday: DayPlanContext]
        let feedbackEvents: [MealFeedbackEvent]
        let householdSize: Int
        let household: Household
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suite = "PersistenceMigrationTests-\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: suite)), suite)
    }

    private func writeLegacyState(
        into defaults: UserDefaults,
        ownerID: UUID,
        mealID: UUID
    ) throws {
        let household = Household(
            name: "Legacy family",
            members: [HouseholdMember(id: ownerID, displayName: "Me", role: .owner)]
        )
        let state = LegacyState(
            hasCompletedOnboarding: true,
            preferences: [mealID: .liked],
            rules: [],
            plan: LegacyPlan(meals: [
                PlannedMeal(day: .monday, mealID: mealID, isLocked: true, servings: 4)
            ]),
            checkedGroceryIDs: [],
            customMeals: [
                LegacyMeal(
                    id: mealID, name: "Legacy stew", subtitle: "From v1", emoji: "🍲",
                    prepMinutes: 40, tags: [], ingredients: [], defaultServings: 4,
                    estimatedCostNOK: 180, instructions: [], source: .manual
                )
            ],
            favoriteMealIDs: [],
            dayContexts: [:],
            feedbackEvents: [],
            householdSize: 5,
            household: household
        )
        defaults.set(try JSONEncoder().encode(state), forKey: stateKey)
    }

    // MARK: - Tests

    @MainActor
    func testLegacyStateIsMigratedWithoutLosingUserData() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let ownerID = UUID(), mealID = UUID()
        try writeLegacyState(into: defaults, ownerID: ownerID, mealID: mealID)

        let store = AppStore(defaults: defaults, random: SeededRandomSource(seed: 1))

        XCTAssertTrue(store.hasCompletedOnboarding)
        XCTAssertEqual(store.householdSize, 5, "Household size must survive the migration")
        XCTAssertEqual(store.household.name, "Legacy family")

        // The flat v1 preference map is attributed to the owner, not dropped.
        XCTAssertEqual(store.memberPreferences[ownerID]?[mealID], .liked)
        XCTAssertEqual(store.preferences[mealID], .liked)

        // The pre-rename cost key is still read.
        let migrated = try XCTUnwrap(store.customMeals.first(where: { $0.id == mealID }))
        XCTAssertEqual(migrated.estimatedCost, 180)
        XCTAssertEqual(migrated.name, "Legacy stew")
        XCTAssertFalse(migrated.isDeleted)
    }

    @MainActor
    func testUndatedLegacyPlanIsAdoptedIntoARealWeek() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        try writeLegacyState(into: defaults, ownerID: UUID(), mealID: UUID())

        let store = AppStore(defaults: defaults, random: SeededRandomSource(seed: 2))

        XCTAssertEqual(store.plan.startDate, WeekAnchor.startOfCurrentWeek())
        XCTAssertFalse(store.plan.isStale(), "A freshly migrated plan must not be stale")
    }

    @MainActor
    func testMigratedStateRoundTripsAtTheNewVersion() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let ownerID = UUID(), mealID = UUID()
        try writeLegacyState(into: defaults, ownerID: ownerID, mealID: mealID)

        let first = AppStore(defaults: defaults, random: SeededRandomSource(seed: 3))
        first.setHouseholdSize(7)
        first.flushPendingWrites()

        let second = AppStore(defaults: defaults, random: SeededRandomSource(seed: 3))
        XCTAssertEqual(second.householdSize, 7)
        XCTAssertEqual(second.memberPreferences[ownerID]?[mealID], .liked)
        XCTAssertEqual(second.customMeals.first?.estimatedCost, 180)
    }

    @MainActor
    func testDeletingACustomMealLeavesATombstone() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppStore(defaults: defaults, random: SeededRandomSource(seed: 4))

        let meal = Meal(name: "Trial", subtitle: "", emoji: "🍲", prepMinutes: 20,
                        tags: [], ingredients: [], source: .manual)
        store.saveMeal(meal)
        XCTAssertEqual(store.activeCustomMeals.count, 1)

        store.deleteMeal(meal)
        XCTAssertTrue(store.activeCustomMeals.isEmpty, "Deleted meals leave the library")
        XCTAssertEqual(store.customMeals.count, 1, "…but a tombstone is retained for sync")
        XCTAssertNotNil(store.customMeals.first?.deletedAt)
        XCTAssertFalse(store.meals.contains { $0.id == meal.id })
    }

    @MainActor
    func testStalePlanRollsOverAndIsArchived() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppStore(defaults: defaults, random: SeededRandomSource(seed: 5))
        store.completeOnboarding()

        // Push the current plan two weeks into the past, then roll the calendar forward.
        let staleStart = Calendar.current.date(byAdding: .weekOfYear, value: -2,
                                               to: WeekAnchor.startOfCurrentWeek())!
        store.plan = store.plan.anchored(to: staleStart)
        XCTAssertTrue(store.plan.isStale())

        store.rollOverIfNeeded()

        XCTAssertEqual(store.plan.startDate, WeekAnchor.startOfCurrentWeek())
        XCTAssertEqual(store.archivedWeeks.count, 1)
        XCTAssertEqual(store.archivedWeeks.first?.startDate, staleStart)
    }

    @MainActor
    func testPreparedNextWeekIsPromotedOnRollover() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppStore(defaults: defaults, random: SeededRandomSource(seed: 6))
        store.completeOnboarding()

        // Stand where last week's plan is current and this week's is already prepared.
        let lastWeek = Calendar.current.date(byAdding: .weekOfYear, value: -1,
                                             to: WeekAnchor.startOfCurrentWeek())!
        store.plan = store.plan.anchored(to: lastWeek)
        store.planNextWeek()
        let preparedMeals = try XCTUnwrap(store.nextWeekPlan).meals

        store.rollOverIfNeeded()

        XCTAssertNil(store.nextWeekPlan, "The prepared week is consumed, not left behind")
        XCTAssertEqual(store.plan.startDate, WeekAnchor.startOfCurrentWeek())
        XCTAssertEqual(store.plan.meals, preparedMeals, "The prepared plan is promoted as-is")
    }
}
