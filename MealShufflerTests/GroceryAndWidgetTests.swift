import XCTest
@testable import MealShuffler

/// Covers the Phase 6 additions: items the user adds themselves, items set aside as already
/// owned, and the reader the widget uses to answer "what is for dinner" from another process.
final class GroceryAndWidgetTests: XCTestCase {

    private func makeStore() throws -> (AppStore, UserDefaults, String) {
        let suite = "GroceryWidgetTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let repository = UserDefaultsStateRepository(defaults: defaults)
        return (AppStore(repository: repository, random: SeededRandomSource(seed: 7)), defaults, suite)
    }

    // MARK: - Manual items

    @MainActor
    func testManualItemAppearsOnTheList() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.addGroceryItem(name: "Milk", quantity: 2, unit: "l", aisle: .dairy)
        let milk = try XCTUnwrap(store.groceryItems.first { $0.name == "Milk" })
        XCTAssertTrue(milk.isManual)
        XCTAssertEqual(milk.aisle, .dairy)
        // 2 l normalises to 2000 ml and displays as litres again.
        XCTAssertEqual(milk.quantity, 2000)
    }

    @MainActor
    func testManualItemMergesWithAPlannedIngredientRatherThanDuplicating() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.completeOnboarding()

        guard let planned = store.groceryItems.first(where: { !$0.isManual && $0.unit == "g" }) else {
            throw XCTSkip("No gram-denominated ingredient in this generated week")
        }
        let before = planned.quantity

        store.addGroceryItem(name: planned.name, quantity: 100, unit: "g", aisle: planned.aisle)
        let matching = store.groceryItems.filter { $0.id == planned.id }
        XCTAssertEqual(matching.count, 1, "A manual entry should add to the line, not create a second one")
        XCTAssertEqual(matching.first?.quantity, before + 100)
    }

    @MainActor
    func testItemWithoutAnAmountShowsNoQuantity() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.addGroceryItem(name: "Kitchen roll", quantity: nil, unit: "", aisle: .pantry)
        let item = try XCTUnwrap(store.groceryItems.first { $0.name == "Kitchen roll" })
        XCTAssertEqual(item.quantityText, "", "A bare name should not render as \"1\"")
    }

    // MARK: - Already have it

    @MainActor
    func testStockedItemsLeaveTheListButStayRecoverable() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.completeOnboarding()

        let item = try XCTUnwrap(store.groceryItems.first)
        store.setStocked(item, stocked: true)

        XCTAssertFalse(store.groceryItems.contains { $0.id == item.id })
        XCTAssertTrue(store.stockedItems.contains { $0.id == item.id })

        store.setStocked(item, stocked: false)
        XCTAssertTrue(store.groceryItems.contains { $0.id == item.id })
        XCTAssertTrue(store.stockedItems.isEmpty)
    }

    @MainActor
    func testSettingAsideClearsAnyTick() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.completeOnboarding()

        let item = try XCTUnwrap(store.groceryItems.first)
        store.toggleGroceryItem(item)
        XCTAssertTrue(store.checkedGroceryIDs.contains(item.id))

        store.setStocked(item, stocked: true)
        XCTAssertFalse(store.checkedGroceryIDs.contains(item.id),
                       "Owning something and having just bought it are different facts")
    }

    @MainActor
    func testTicksSurviveAReshuffleEvenWhileSomeItemsAreSetAside() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.completeOnboarding()

        let items = store.groceryItems
        guard items.count >= 2 else { throw XCTSkip("Generated week has too few ingredients") }
        store.setStocked(items[0], stocked: true)
        store.toggleGroceryItem(items[1])

        store.shuffle(day: .monday, intent: .different)

        // The tick survives if its item is still called for anywhere in the week.
        let stillPresent = GroceryListBuilder
            .build(plan: store.plan, meals: store.meals, manualItems: store.manualGroceryItems)
            .contains { $0.id == items[1].id }
        if stillPresent {
            XCTAssertTrue(store.checkedGroceryIDs.contains(items[1].id))
        }
        XCTAssertTrue(store.stockedGroceryIDs.contains(items[0].id), "Set-aside items are not reset by a reshuffle")
    }

    // MARK: - Widget reader

    @MainActor
    func testWidgetReaderSeesWhatTheAppSaved() throws {
        let suite = "WidgetReaderTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = UserDefaultsStateRepository(defaults: defaults)

        let store = AppStore(repository: repository, random: SeededRandomSource(seed: 8))
        store.completeOnboarding()
        store.flushPendingWrites()

        // A separate reader, as the widget process would construct it.
        let dinners = PlannedDinnerReader(repository: repository).upcoming()
        XCTAssertFalse(dinners.isEmpty, "The widget must see the plan the app just wrote")

        let today = try XCTUnwrap(dinners.first)
        XCTAssertTrue(Calendar.current.isDateInToday(today.date))

        // It agrees with the app about what is planned.
        let weekday = today.day
        if let mealID = store.plan[weekday]?.mealID, let meal = store.meal(id: mealID) {
            XCTAssertEqual(today.title, meal.name)
        }
    }

    @MainActor
    func testWidgetReaderReturnsNothingWhenNoPlanExists() throws {
        let suite = "WidgetEmptyTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let dinners = PlannedDinnerReader(repository: UserDefaultsStateRepository(defaults: defaults)).upcoming()
        XCTAssertTrue(dinners.isEmpty, "An empty container is an invitation, not an error")
    }

    @MainActor
    func testWidgetReaderOnlyLooksForward() throws {
        let suite = "WidgetForwardTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = UserDefaultsStateRepository(defaults: defaults)

        let store = AppStore(repository: repository, random: SeededRandomSource(seed: 9))
        store.completeOnboarding()
        store.flushPendingWrites()

        let dinners = PlannedDinnerReader(repository: repository).upcoming()
        let today = Calendar.current.startOfDay(for: .now)
        XCTAssertTrue(dinners.allSatisfy { Calendar.current.startOfDay(for: $0.date) >= today })
    }
}
