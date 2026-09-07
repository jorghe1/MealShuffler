import XCTest
@testable import MealShuffler

/// Covers the store-side behaviour behind the interface work: aisle ordering, library
/// filtering, and onboarding no longer discarding the week it just showed.
final class InterfaceStateTests: XCTestCase {

    @MainActor
    private func makeStore(seed: UInt64 = 11) throws -> (AppStore, UserDefaults, String) {
        let suite = "InterfaceStateTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let repository = UserDefaultsStateRepository(defaults: defaults)
        return (AppStore(repository: repository, random: SeededRandomSource(seed: seed)), defaults, suite)
    }

    // MARK: - Onboarding

    @MainActor
    func testCompletingOnboardingKeepsThePreviewedWeek() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        // The last onboarding step generates and shows a real week.
        store.shuffleAll()
        let shown = store.plan.meals

        store.completeOnboarding()

        XCTAssertTrue(store.hasCompletedOnboarding)
        XCTAssertEqual(store.plan.meals, shown, "The approved week must not be re-rolled")
    }

    @MainActor
    func testCompletingOnboardingStillBuildsAWeekIfNoneExists() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertTrue(store.plan.meals.isEmpty)
        store.completeOnboarding()
        XCTAssertFalse(store.plan.meals.isEmpty)
    }

    // MARK: - Aisle order

    @MainActor
    func testAisleOrderStartsAtTheDefaultAndCanBeReordered() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(store.aisleOrder, GroceryAisle.allCases)

        // Move frozen to the front, as anyone who has melted ice cream once would.
        let frozenIndex = try XCTUnwrap(store.aisleOrder.firstIndex(of: .frozen))
        store.moveAisles(from: IndexSet(integer: frozenIndex), to: 0)

        XCTAssertEqual(store.aisleOrder.first, .frozen)
        XCTAssertEqual(Set(store.aisleOrder), Set(GroceryAisle.allCases), "No aisle may be lost")
        XCTAssertEqual(store.aisleOrder.count, GroceryAisle.allCases.count)

        store.resetAisleOrder()
        XCTAssertEqual(store.aisleOrder, GroceryAisle.allCases)
    }

    @MainActor
    func testAisleOrderSurvivesARelaunch() throws {
        let suite = "AisleOrderPersistence-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = UserDefaultsStateRepository(defaults: defaults)

        let first = AppStore(repository: repository, random: SeededRandomSource(seed: 12))
        let frozenIndex = try XCTUnwrap(first.aisleOrder.firstIndex(of: .frozen))
        first.moveAisles(from: IndexSet(integer: frozenIndex), to: 0)
        first.flushPendingWrites()

        let second = AppStore(repository: repository, random: SeededRandomSource(seed: 12))
        XCTAssertEqual(second.aisleOrder.first, .frozen)
    }

    /// A stored order written before an aisle existed must not make that aisle disappear
    /// from the shopping list.
    func testStoredOrderIsCompletedWithAnyMissingAisles() {
        let partial: [GroceryAisle] = [.frozen, .dairy]
        let completed = AppStore.completeAisleOrder(partial)

        XCTAssertEqual(Array(completed.prefix(2)), partial, "Stored preference leads")
        XCTAssertEqual(Set(completed), Set(GroceryAisle.allCases), "Everything else is appended")
        XCTAssertEqual(completed.count, GroceryAisle.allCases.count)
    }

    // MARK: - Export follows the user's order

    @MainActor
    func testSharedListFollowsTheUsersAisleOrder() throws {
        let (store, defaults, suite) = try makeStore(seed: 13)
        defer { defaults.removePersistentDomain(forName: suite) }
        store.completeOnboarding()

        let frozenIndex = try XCTUnwrap(store.aisleOrder.firstIndex(of: .frozen))
        store.moveAisles(from: IndexSet(integer: frozenIndex), to: 0)

        let text = PlanTextExporter.groceryList(store.groceryItems, aisleOrder: store.aisleOrder)
        let present = store.aisleOrder.filter { aisle in
            store.groceryItems.contains { $0.aisle == aisle }
        }
        let positions = present.compactMap { text.range(of: $0.name.uppercased())?.lowerBound }
        XCTAssertEqual(positions, positions.sorted(), "Sections must appear in the chosen order")
    }
}
