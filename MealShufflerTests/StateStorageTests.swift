import XCTest
@testable import MealShuffler

/// Where state lives, and how an install already in the wild moves onto it.
///
/// The blob outgrew user defaults: 26 archived weeks, up to 2,000 feedback events and a meal
/// library that now carries instructions, read into memory and rewritten whole on every
/// change -- by the app and by both extensions.
final class StateStorageTests: XCTestCase {

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("StateStorageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func snapshot(householdSize: Int = 4) -> AppStateSnapshot {
        AppStateSnapshot(
            hasCompletedOnboarding: true,
            memberPreferences: [:],
            rules: PlanningRule.starterRules(),
            plan: WeeklyPlan(meals: [PlannedMeal(day: .monday, mealID: SampleMeals.all[0].id, isLocked: false)]),
            checkedGroceryIDs: [],
            stockedGroceryIDs: [],
            manualGroceryItems: [],
            pantryStaples: ["olivenolje"],
            aisleOrder: GroceryAisle.allCases,
            customMeals: [],
            favoriteMealIDs: [],
            dayContexts: [:],
            feedbackEvents: [],
            householdSize: householdSize,
            household: Household(),
            archivedWeeks: [],
            nextWeekPlan: nil,
            dinnerReminderEnabled: true,
            dinnerReminderHour: 17,
            prepLeadReminderEnabled: true,
            groceryReminderEnabled: true,
            groceryReminderWeekday: .friday,
            groceryReminderHour: 9
        )
    }

    func testStateRoundTripsThroughAFile() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = FileStateRepository(directory: directory, migratingFrom: nil)
        XCTAssertNil(repository.load(), "Nothing has been written yet")

        repository.save(snapshot(householdSize: 6))
        let restored = try XCTUnwrap(repository.load())

        XCTAssertEqual(restored.householdSize, 6)
        XCTAssertTrue(restored.hasCompletedOnboarding)
        XCTAssertEqual(restored.dinnerReminderHour, 17)
        XCTAssertTrue(restored.prepLeadReminderEnabled)
        XCTAssertEqual(restored.groceryReminderWeekday, .friday)
        XCTAssertEqual(restored.groceryReminderHour, 9)
        XCTAssertEqual(restored.pantryStaples, ["olivenolje"])
    }

    /// The new reminder settings are additive, so an older blob must decode with defaults
    /// rather than throwing the household's whole plan away.
    func testAnOlderBlobWithoutTheReminderSettingsStillDecodes() throws {
        let suite = "StateStorageTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let legacy: [String: Any] = [
            "schemaVersion": 2,
            "hasCompletedOnboarding": true,
            "householdSize": 5,
        ]
        defaults.set(try JSONSerialization.data(withJSONObject: legacy),
                     forKey: UserDefaultsStateRepository.storageKey)

        let restored = try XCTUnwrap(UserDefaultsStateRepository(defaults: defaults).load())
        XCTAssertEqual(restored.householdSize, 5)
        XCTAssertFalse(restored.prepLeadReminderEnabled)
        XCTAssertFalse(restored.groceryReminderEnabled)
        XCTAssertEqual(restored.groceryReminderWeekday, .saturday)
        XCTAssertEqual(restored.groceryReminderHour, 10)
        XCTAssertTrue(restored.pantryStaples.isEmpty)
    }

    /// An install already in the wild keeps its plan, and the old copy goes away so there is
    /// exactly one source of truth afterwards.
    func testStateWrittenBeforeTheFileExistedIsAdoptedOnce() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "StateStorageTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        UserDefaultsStateRepository(defaults: defaults).save(snapshot(householdSize: 7))
        XCTAssertNotNil(defaults.data(forKey: UserDefaultsStateRepository.storageKey))

        let repository = FileStateRepository(directory: directory, migratingFrom: defaults)
        let adopted = try XCTUnwrap(repository.load())
        XCTAssertEqual(adopted.householdSize, 7, "The household's own state must come across")

        XCTAssertNil(
            defaults.data(forKey: UserDefaultsStateRepository.storageKey),
            "Leaving the old copy behind means two sources of truth that drift"
        )
        XCTAssertEqual(repository.load()?.householdSize, 7, "And it reads back from the file")
    }

    func testACorruptFileDoesNotCrashOrResurrectOldState() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = FileStateRepository(directory: directory, migratingFrom: nil)
        repository.save(snapshot())
        try Data("not json".utf8).write(to: directory.appendingPathComponent("state.json"))

        XCTAssertNil(repository.load(), "A ruined file reads as a fresh install, not as a crash")

        repository.save(snapshot(householdSize: 3))
        XCTAssertEqual(repository.load()?.householdSize, 3, "And it recovers on the next write")
    }

    /// A constraint can leave the vocabulary -- `maximumCostPerWeek` did, when the app stopped
    /// claiming to know what a week costs. Decoding that rule throws, and the throw is not
    /// local: it fails the whole snapshot, which reads back as a fresh install.
    func testARuleWrittenAgainstAnOlderVocabularyDoesNotCostTheHouseholdItsPlan() throws {
        let suite = "StateStorageTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let legacy: [String: Any] = [
            "schemaVersion": 3,
            "hasCompletedOnboarding": true,
            "householdSize": 5,
            "rules": [
                ["title": "Budget", "constraint": ["maximumCostPerWeek": ["amount": 800]]],
                ["title": "Fish on Tuesday",
                 "constraint": ["requiredOn": ["day": "tuesday", "matcher": ["tag": ["_0": "fish"]]]]]
            ],
        ]
        defaults.set(try JSONSerialization.data(withJSONObject: legacy),
                     forKey: UserDefaultsStateRepository.storageKey)

        let restored = try XCTUnwrap(
            UserDefaultsStateRepository(defaults: defaults).load(),
            "One unreadable rule must not read as a fresh install"
        )
        XCTAssertEqual(restored.householdSize, 5, "The rest of the household's state survives")
        XCTAssertFalse(restored.rules.contains { $0.title == "Budget" }, "The dead rule is dropped")
    }

    // MARK: - Calendar alignment

    /// `Weekday` is declared Monday-first; `Calendar` counts Sunday as 1. The weekly grocery
    /// reminder builds its trigger from the second numbering.
    func testWeekdayMapsOntoCalendarNumbering() {
        XCTAssertEqual(Weekday.sunday.calendarWeekday, 1)
        XCTAssertEqual(Weekday.monday.calendarWeekday, 2)
        XCTAssertEqual(Weekday.tuesday.calendarWeekday, 3)
        XCTAssertEqual(Weekday.wednesday.calendarWeekday, 4)
        XCTAssertEqual(Weekday.thursday.calendarWeekday, 5)
        XCTAssertEqual(Weekday.friday.calendarWeekday, 6)
        XCTAssertEqual(Weekday.saturday.calendarWeekday, 7)
        XCTAssertEqual(Set(Weekday.allCases.map(\.calendarWeekday)), Set(1...7))
    }
}
