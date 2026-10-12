import XCTest
@testable import MealShuffler

/// The ways a household could lose its data without anything crashing: a restore quietly
/// undone by a write that was already on its way, one bad number costing the whole file,
/// a backup that only ever held the last edit, and lists that grew for ever.
@MainActor
final class DataSafetyTests: XCTestCase {

    // MARK: - Helpers

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DataSafetyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
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
            dinnerReminderEnabled: false,
            dinnerReminderHour: 16,
            prepLeadReminderEnabled: false,
            groceryReminderEnabled: false,
            groceryReminderWeekday: .saturday,
            groceryReminderHour: 10
        )
    }

    private func makeStore(repository: any AppStateRepository, seed: UInt64 = 41) -> AppStore {
        AppStore(
            repository: repository,
            random: SeededRandomSource(seed: seed),
            widgetRefresher: RecordingWidgetRefresher(),
            reminderService: RecordingReminderScheduler()
        )
    }

    // MARK: - Restore against a queued background write

    /// The debounced save had already fired and was waiting on the write queue when the
    /// restore wrote straight to disk from the main thread. The queued write then landed
    /// second and put the household back the way it was before the restore.
    func testARestoreIsNotOverwrittenByABackgroundWriteAlreadyQueued() async throws {
        let repository = GatedRepository()
        let store = makeStore(repository: repository)
        store.flushPendingWrites()
        var restored = store.makeSnapshot()
        restored.householdSize = 6

        repository.holdNextSave()
        store.setHouseholdSize(3)
        // The debounce has fired and its write is stuck inside the repository, on the queue.
        await fulfillment(of: [repository.entered], timeout: 5)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { repository.release() }

        try store.restoreSnapshot(restored)
        await fulfillment(of: [repository.finished], timeout: 5)

        XCTAssertEqual(repository.load()?.householdSize, 6,
                       "The older write must land before the restore's, never after it")
        store.flushPendingWrites()
        XCTAssertEqual(repository.load()?.householdSize, 6)
        XCTAssertEqual(store.householdSize, 6)
    }

    /// A debounced save that has not fired yet is cancelled by the restore, not left to fire.
    func testARestoreCancelsAPendingDebouncedSave() async throws {
        let repository = GatedRepository()
        let store = makeStore(repository: repository)
        store.flushPendingWrites()
        var restored = store.makeSnapshot()
        restored.householdSize = 7

        store.setHouseholdSize(2)
        try store.restoreSnapshot(restored)
        // Longer than the 400 ms debounce, so a surviving save would have written by now.
        try await Task.sleep(for: .milliseconds(900))

        XCTAssertEqual(repository.load()?.householdSize, 7)
    }

    // MARK: - Repair instead of refusal

    /// One diner count of 30 used to fail the state file and its backup alike, and the
    /// household started from nothing.
    func testAnOutOfRangeValueIsRepairedRatherThanCostingTheHousehold() throws {
        let directory = try makeDirectory()
        var state = snapshot(householdSize: 25)
        state.dayContexts = [.monday: DayPlanContext(diners: 30, extraServings: 40, portionScale: 9)]
        state.nextWeekContexts = [.friday: DayPlanContext(diners: 0)]
        state.plan = WeeklyPlan(meals: [
            PlannedMeal(day: .monday, mealID: SampleMeals.all[0].id, isLocked: false, servings: 5000, portionScale: 0.01)
        ])
        state.tools.freezer = [
            FreezerBatch(recipe: SampleMeals.all[0], portions: 5000, label: "Big batch"),
            FreezerBatch(recipe: SampleMeals.all[1], portions: -1, label: "Already eaten")
        ]
        try JSONEncoder().encode(state).write(to: directory.appendingPathComponent("state.json"))

        let repository = FileStateRepository(directory: directory, migratingFrom: nil)
        let loaded = try XCTUnwrap(repository.load(), "A bad number must not read as a fresh install")
        XCTAssertNil(repository.recoveryNotice, "The file was read, so there is nothing to recover")

        XCTAssertEqual(loaded.householdSize, 20)
        XCTAssertEqual(loaded.dayContexts[.monday]?.diners, 20)
        XCTAssertEqual(loaded.dayContexts[.monday]?.extraServings, 12)
        XCTAssertEqual(loaded.dayContexts[.monday]?.portionScale, 2)
        XCTAssertEqual(loaded.nextWeekContexts[.friday]?.diners, 1)
        XCTAssertEqual(loaded.plan[.monday]?.servings, 1000)
        XCTAssertEqual(loaded.plan[.monday]?.portionScale, 0.25)
        XCTAssertEqual(loaded.tools.freezer.map(\.label), ["Big batch"])
        XCTAssertEqual(loaded.tools.freezer.first?.portions, 1000)
        XCTAssertEqual(loaded.pantryStaples, ["olivenolje"], "Everything else survives untouched")

        // The original reads, so the next save keeps it as the backup instead of parking it.
        try repository.saveOrThrow(loaded)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertFalse(names.contains { $0.contains("unreadable-") })
        XCTAssertTrue(names.contains("state.json.backup"))
    }

    /// A week with two Mondays has no nearest legal value, so that is still refused.
    func testStructurallyCorruptStateIsStillRefused() throws {
        var state = snapshot()
        state.plan = WeeklyPlan(meals: [
            PlannedMeal(day: .monday, mealID: SampleMeals.all[0].id, isLocked: false),
            PlannedMeal(day: .monday, mealID: SampleMeals.all[1].id, isLocked: false)
        ])
        XCTAssertThrowsError(try AppStateSnapshot.decoding(JSONEncoder().encode(state)))
    }

    /// A snapshot built in memory goes through the same repair on its way into the store.
    func testRestoringAnOutOfRangeSnapshotRepairsIt() throws {
        let suite = "DataSafetyTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = makeStore(repository: UserDefaultsStateRepository(defaults: defaults))
        var state = store.makeSnapshot()
        state.householdSize = 99

        try store.restoreSnapshot(state)

        XCTAssertEqual(store.householdSize, 20)
    }

    // MARK: - Shopping sessions

    func testShoppingPeriodKeysAreReadAsTheyAreWritten() {
        XCTAssertEqual(AppStore.shoppingPeriodEnd("100-200"), Date(timeIntervalSince1970: 200))
        XCTAssertEqual(AppStore.shoppingPeriodEnd("-300-200"), Date(timeIntervalSince1970: 200))
        XCTAssertEqual(AppStore.shoppingPeriodEnd("-300--200"), Date(timeIntervalSince1970: -200))
        XCTAssertNil(AppStore.shoppingPeriodEnd("garbage"))
        XCTAssertNil(AppStore.shoppingPeriodEnd("weekly-list"))
    }

    func testOnlyShoppingSessionsFromLongAgoArePruned() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let week: TimeInterval = 7 * 86_400
        func key(endingWeeksAgo weeks: Double) -> String {
            let end = now.addingTimeInterval(-weeks * week)
            return "\(Int(end.addingTimeInterval(-6 * 86_400).timeIntervalSince1970))-\(Int(end.timeIntervalSince1970))"
        }
        let old = key(endingWeeksAgo: 20), recent = key(endingWeeksAgo: 3), current = key(endingWeeksAgo: 30)
        let sessions = [old: ShoppingSession(), recent: ShoppingSession(), current: ShoppingSession(),
                        "weekly-list": ShoppingSession()]

        let kept = AppStore.prunedShoppingSessions(sessions, keeping: current, now: now)

        XCTAssertEqual(Set(kept.keys), [recent, current, "weekly-list"],
                       "Recent periods, the current one and unreadable keys all stay")
    }

    func testRolloverPrunesShoppingSessionsFromLongAgo() throws {
        let suite = "DataSafetyTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = makeStore(repository: UserDefaultsStateRepository(defaults: defaults))
        let calendar = Calendar.current
        func key(endingWeeksAgo weeks: Int) -> String {
            let end = calendar.date(byAdding: .weekOfYear, value: -weeks, to: .now)!
            let start = calendar.date(byAdding: .day, value: -6, to: end)!
            return "\(Int(start.timeIntervalSince1970))-\(Int(end.timeIntervalSince1970))"
        }
        let old = key(endingWeeksAgo: 20), recent = key(endingWeeksAgo: 4)
        store.householdTools.shoppingSessions[old] = ShoppingSession(checked: ["melk"])
        store.householdTools.shoppingSessions[recent] = ShoppingSession(checked: ["brød"])
        store.plan = store.plan.anchored(to: calendar.date(byAdding: .weekOfYear, value: -2,
                                                           to: WeekAnchor.startOfCurrentWeek())!)

        store.rollOverIfNeeded()

        XCTAssertNil(store.householdTools.shoppingSessions[old])
        XCTAssertEqual(store.householdTools.shoppingSessions[recent]?.checked, ["brød"])
    }

    // MARK: - Daily backups

    private func day(_ offset: Int) -> Date {
        let calendar = Calendar.current
        let base = calendar.date(from: DateComponents(year: 2026, month: 3, day: 2, hour: 12))!
        return calendar.date(byAdding: .day, value: offset, to: base)!
    }

    /// Ten days, two saves a day. The daily copy is the state the day started with, taken
    /// once, and only the newest seven days are kept.
    func testADailyCopyIsTakenOnceADayAndAWeekIsKept() throws {
        let directory = try makeDirectory()
        let clock = TestClock(day(0))
        let repository = FileStateRepository(directory: directory, migratingFrom: nil, now: { clock.now })
        for offset in 0..<10 {
            clock.now = day(offset)
            try repository.saveOrThrow(snapshot(householdSize: 2 * offset + 1))
            try repository.saveOrThrow(snapshot(householdSize: 2 * offset + 2))
        }

        let names = repository.dailyBackupURLs.map(\.lastPathComponent)
        XCTAssertEqual(names, (3...9).reversed().map { FileStateRepository.dailyBackupName(for: day($0)) })
        // Day 9 began with day 8's last save, and its own second save did not replace it.
        let newest = try AppStateSnapshot.decoding(Data(contentsOf: try XCTUnwrap(repository.dailyBackupURLs.first)))
        XCTAssertEqual(newest.householdSize, 18)
    }

    /// When the file and the rolling backup are both unreadable, the newest day that still
    /// reads is used.
    func testLoadFallsBackToTheNewestReadableDailyCopy() throws {
        let directory = try makeDirectory()
        let clock = TestClock(day(0))
        let repository = FileStateRepository(directory: directory, migratingFrom: nil, now: { clock.now })
        for offset in 0..<3 {
            clock.now = day(offset)
            try repository.saveOrThrow(snapshot(householdSize: offset + 5))
        }
        // Day 1 began at 5, day 2 at 6.
        let broken = Data("broken".utf8)
        try broken.write(to: directory.appendingPathComponent("state.json"))
        try broken.write(to: directory.appendingPathComponent("state.json.backup"))

        XCTAssertEqual(repository.load()?.householdSize, 6)
        XCTAssertNotNil(repository.recoveryNotice)

        try broken.write(to: directory.appendingPathComponent(FileStateRepository.dailyBackupName(for: day(2))))
        XCTAssertEqual(repository.load()?.householdSize, 5, "An unreadable day is skipped, not trusted")
    }

    func testDailyCopyNamesAreRecognisedStrictly() {
        XCTAssertTrue(FileStateRepository.isDailyBackupName("state-2026-10-12.json"))
        XCTAssertFalse(FileStateRepository.isDailyBackupName("state.json"))
        XCTAssertFalse(FileStateRepository.isDailyBackupName("state.json.backup"))
        XCTAssertFalse(FileStateRepository.isDailyBackupName("state-2026-1-12.json"))
        XCTAssertFalse(FileStateRepository.isDailyBackupName("state-notadate!.json"))
    }

    // MARK: - Device backup files

    private func makeBackup(in root: URL) throws -> (document: DeviceBackupDocument, images: URL) {
        let images = root.appendingPathComponent("SharedRecipeImages", isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        try Data("original".utf8).write(to: images.appendingPathComponent("kept.jpg"))
        let document = try DeviceBackupDocument(state: snapshot(householdSize: 3), files: [
            "images__kept.jpg": Data("from backup".utf8),
            "images__added.jpg": Data("new".utf8)
        ])
        return (document, images)
    }

    /// The photos used to be written first and left there when the state then failed to save.
    func testARestoreWhoseStateFailsPutsTheFilesBack() throws {
        let root = try makeDirectory()
        let (document, images) = try makeBackup(in: root)
        let store = makeStore(repository: FailingRepository())

        XCTAssertThrowsError(try document.restore(into: store, roots: ["images__": images]))

        XCTAssertEqual(try Data(contentsOf: images.appendingPathComponent("kept.jpg")), Data("original".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: images.appendingPathComponent("added.jpg").path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["SharedRecipeImages"],
                       "No staging folder is left behind")
    }

    func testASuccessfulRestoreKeepsTheBackupsFiles() throws {
        let root = try makeDirectory()
        let (document, images) = try makeBackup(in: root)
        let suite = "DataSafetyTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = makeStore(repository: UserDefaultsStateRepository(defaults: defaults))

        try document.restore(into: store, roots: ["images__": images])

        XCTAssertEqual(store.householdSize, 3)
        XCTAssertEqual(try Data(contentsOf: images.appendingPathComponent("kept.jpg")), Data("from backup".utf8))
        XCTAssertEqual(try Data(contentsOf: images.appendingPathComponent("added.jpg")), Data("new".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["SharedRecipeImages"])
    }

    // MARK: - Saved blobs from earlier versions

    // Hand-written from the Codable shapes. Dictionaries keyed by anything but String encode
    // as flat key, value arrays, which is why `memberPreferences` and `dayContexts` are lists.
    private let memberID = UUID(uuidString: "6F1C2D3E-0000-4000-8000-000000000001")!
    private let mealID = UUID(uuidString: "6F1C2D3E-0000-4000-8000-000000000002")!

    private var version2: String { """
        {
          "schemaVersion": 2,
          "hasCompletedOnboarding": true,
          "householdSize": 3,
          "household": {
            "id": "6F1C2D3E-0000-4000-8000-0000000000AA",
            "name": "Fixture family",
            "inviteCode": "ABCD1234",
            "members": [{"id": "\(memberID.uuidString)", "displayName": "Kari", "role": "owner"}]
          },
          "memberPreferences": ["\(memberID.uuidString)", ["\(mealID.uuidString)", "liked"]],
          "plan": {
            "startDate": 812246400,
            "meals": [{"day": "monday", "mealID": "\(mealID.uuidString)", "isLocked": true, "servings": 3}]
          },
          "customMeals": [{
            "id": "\(mealID.uuidString)", "name": "Fiskegrateng", "subtitle": "", "emoji": "🐟",
            "prepMinutes": 45, "tags": [], "ingredients": []
          }],
          "checkedGroceryIDs": ["melk"],
          "favoriteMealIDs": ["\(mealID.uuidString)"],
          "dayContexts": ["friday", {"diners": 5, "extraServings": 1, "mode": "takeaway"}]
        }
        """ }

    private var version3: String { """
        {
          "schemaVersion": 3,
          "hasCompletedOnboarding": true,
          "householdSize": 4,
          "plan": {"startDate": 812246400, "meals": []},
          "pantryStaples": ["salt"],
          "stockedGroceryIDs": ["ris"],
          "manualGroceryItems": [{
            "id": "6F1C2D3E-0000-4000-8000-0000000000BB", "name": "Melk", "unit": "l",
            "quantity": 2, "aisle": "dairy", "addedAt": 812246400
          }],
          "archivedWeeks": [{
            "id": "6F1C2D3E-0000-4000-8000-0000000000CC",
            "archivedAt": 812851200,
            "plan": {"startDate": 811641600, "meals": [{"day": "tuesday", "mealID": "\(mealID.uuidString)"}]}
          }],
          "dinnerReminderEnabled": true,
          "dinnerReminderHour": 17,
          "prepLeadReminderEnabled": true,
          "groceryReminderEnabled": true,
          "groceryReminderWeekday": "friday",
          "groceryReminderHour": 9
        }
        """ }

    private var version4: String { """
        {
          "schemaVersion": 4,
          "hasCompletedOnboarding": true,
          "householdSize": 2,
          "rules": [],
          "plan": {"startDate": 812246400, "meals": []},
          "nextWeekPlan": {"startDate": 812851200, "meals": [{"day": "sunday", "mealID": "\(mealID.uuidString)", "servings": 2}]},
          "nextWeekContexts": ["sunday", {"diners": 2, "extraServings": 0, "mode": "cook"}],
          "tools": {
            "shoppingSessions": {"100-200": {"checked": ["melk"], "stocked": [], "manual": []}},
            "cooking": {},
            "freezer": [{
              "id": "6F1C2D3E-0000-4000-8000-0000000000DD",
              "recipe": {"id": "\(mealID.uuidString)", "name": "Lasagne", "subtitle": "", "emoji": "🍝",
                         "prepMinutes": 60, "tags": [], "ingredients": []},
              "portions": 2.5, "frozenOn": 812246400, "label": "Lasagne"
            }],
            "collections": {"Hverdag": ["\(mealID.uuidString)"]},
            "dinnerHour": 19,
            "sharesIngredients": true
          }
        }
        """ }

    func testAVersion2BlobDecodes() throws {
        let state = try AppStateSnapshot.decoding(Data(version2.utf8))
        XCTAssertEqual(state.schemaVersion, AppStateSnapshot.currentVersion)
        XCTAssertTrue(state.hasCompletedOnboarding)
        XCTAssertEqual(state.householdSize, 3)
        XCTAssertEqual(state.household.name, "Fixture family")
        XCTAssertEqual(state.memberPreferences[memberID]?[mealID], .liked)
        XCTAssertEqual(state.plan.startDate, Date(timeIntervalSinceReferenceDate: 812_246_400))
        XCTAssertEqual(state.plan[.monday]?.servings, 3)
        XCTAssertEqual(state.customMeals.first?.name, "Fiskegrateng")
        XCTAssertEqual(state.checkedGroceryIDs, ["melk"])
        XCTAssertEqual(state.dayContexts[.friday]?.mode, .takeaway)
        XCTAssertEqual(state.dayContexts[.friday]?.diners, 5)
        // Fields that came later read as their defaults.
        XCTAssertEqual(state.groceryReminderWeekday, .saturday)
        XCTAssertEqual(state.tools, HouseholdTools())
        XCTAssertFalse(state.rules.isEmpty, "A blob without rules starts with the starter rules")
    }

    func testAVersion3BlobDecodes() throws {
        let state = try AppStateSnapshot.decoding(Data(version3.utf8))
        XCTAssertEqual(state.schemaVersion, AppStateSnapshot.currentVersion)
        XCTAssertEqual(state.pantryStaples, ["salt"])
        XCTAssertEqual(state.stockedGroceryIDs, ["ris"])
        XCTAssertEqual(state.manualGroceryItems.first?.name, "Melk")
        XCTAssertEqual(state.manualGroceryItems.first?.aisle, .dairy)
        XCTAssertEqual(state.archivedWeeks.count, 1)
        XCTAssertEqual(state.archivedWeeks.first?.plan[.tuesday]?.mealID, mealID)
        XCTAssertTrue(state.dinnerReminderEnabled)
        XCTAssertEqual(state.dinnerReminderHour, 17)
        XCTAssertTrue(state.prepLeadReminderEnabled)
        XCTAssertEqual(state.groceryReminderWeekday, .friday)
        XCTAssertEqual(state.groceryReminderHour, 9)
        XCTAssertNil(state.nextWeekPlan)
    }

    func testAVersion4BlobDecodes() throws {
        let state = try AppStateSnapshot.decoding(Data(version4.utf8))
        XCTAssertEqual(state.schemaVersion, AppStateSnapshot.currentVersion)
        XCTAssertTrue(state.rules.isEmpty, "An empty rule list stays empty")
        XCTAssertEqual(state.nextWeekPlan?[.sunday]?.servings, 2)
        XCTAssertEqual(state.nextWeekContexts[.sunday]?.diners, 2)
        XCTAssertEqual(state.tools.dinnerHour, 19)
        XCTAssertEqual(state.tools.sharesIngredients, true)
        XCTAssertEqual(state.tools.shoppingSessions["100-200"]?.checked, ["melk"])
        XCTAssertEqual(state.tools.collections["Hverdag"], [mealID])
        XCTAssertEqual(state.tools.freezer.first?.portions, 2.5)
        XCTAssertEqual(state.tools.freezer.first?.recipe.name, "Lasagne")
    }
}

// MARK: - Test doubles

/// Holds one save until released, so a test can line a restore up behind a background write
/// that has already started.
private final class GatedRepository: AppStateRepository, @unchecked Sendable {
    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private var stored: AppStateSnapshot?
    private var holding = false
    let entered = XCTestExpectation(description: "The held save started")
    let finished = XCTestExpectation(description: "The held save finished")

    func holdNextSave() { lock.withLock { holding = true } }
    func release() { gate.signal() }

    func load() -> AppStateSnapshot? { lock.withLock { stored } }
    func save(_ snapshot: AppStateSnapshot) { try? saveOrThrow(snapshot) }

    func saveOrThrow(_ snapshot: AppStateSnapshot) throws {
        let held = lock.withLock { () -> Bool in
            defer { holding = false }
            return holding
        }
        if held {
            entered.fulfill()
            gate.wait()
        }
        lock.withLock { stored = snapshot }
        if held { finished.fulfill() }
    }
}

/// A disk that refuses every write.
private final class FailingRepository: AppStateRepository, @unchecked Sendable {
    func load() -> AppStateSnapshot? { nil }
    func save(_ snapshot: AppStateSnapshot) {}
    func saveOrThrow(_ snapshot: AppStateSnapshot) throws { throw CocoaError(.fileWriteOutOfSpace) }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ date: Date) { value = date }

    var now: Date {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}
