import XCTest
@testable import MealShuffler

/// Who cooks, the kids' wishes and votes, busy evenings, use-up rules, rules that cannot hold,
/// the dinner year, photos and the saved-state migrations.
@MainActor
final class FamilyFeatureTests: XCTestCase {
    private let meals = SampleMeals.all

    private func makeStore(seed: UInt64 = 5, reminders: RecordingReminderScheduler = RecordingReminderScheduler()) throws -> AppStore {
        let suite = "FamilyFeatureTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let store = AppStore(
            repository: UserDefaultsStateRepository(defaults: defaults),
            random: SeededRandomSource(seed: seed),
            widgetRefresher: RecordingWidgetRefresher(),
            reminderService: reminders
        )
        store.busyEvenings = FixedBusyEvenings()
        return store
    }

    // MARK: - Use up

    func testUseUpMakesASoftRuleForThisWeekOnly() throws {
        let now = Date()
        for sentence in ["Bruk opp rømme", "use up the cream"] {
            let outcome = RuleSentenceParser.parse(sentence, meals: meals, now: now)
            let rule = try XCTUnwrap(outcome.rule, sentence)
            XCTAssertEqual(rule.strength, .preferred, sentence)
            guard case .minimumPerWeek(_, let count) = rule.constraint else {
                return XCTFail("\(sentence) gave \(rule.constraint)")
            }
            XCTAssertEqual(count, 1)
            let expiry = try XCTUnwrap(rule.expiresAfter)
            XCTAssertTrue(rule.isActive(inWeek: now))
            XCTAssertTrue(rule.isActive(inWeek: expiry))
            let nextWeek = try XCTUnwrap(Calendar.current.date(byAdding: .weekOfYear, value: 1, to: now))
            XCTAssertFalse(rule.isActive(inWeek: nextWeek), "\(sentence) should lapse after this week")
        }
    }

    func testExpiryRoundTripsAndOldRulesDecodeWithout() throws {
        var rule = PlanningRule(title: "Use up cream", strength: .preferred,
                                constraint: .minimumPerWeek(matcher: .ingredient("rømme"), count: 1))
        rule.expiresAfter = Date(timeIntervalSince1970: 1_800_000_000)
        let decoded = try JSONDecoder().decode(PlanningRule.self, from: JSONEncoder().encode(rule))
        XCTAssertEqual(decoded.expiresAfter, rule.expiresAfter)

        let plain = PlanningRule(title: "Fish", constraint: .minimumPerWeek(matcher: .tag(.fish), count: 1))
        let again = try JSONDecoder().decode(PlanningRule.self, from: JSONEncoder().encode(plain))
        XCTAssertNil(again.expiresAfter)
    }

    // MARK: - Rules that cannot hold

    func testProteinMinimumsBeyondTheCookedEveningsAreRefused() throws {
        let store = try makeStore()
        store.rules = []
        XCTAssertEqual(store.addRule(PlanningRule(title: "Fish", constraint: .minimumPerWeek(matcher: .tag(.fish), count: 4))), .added)
        let outcome = store.addRule(PlanningRule(title: "Meat", constraint: .minimumPerWeek(matcher: .tag(.meat), count: 4)))
        guard case .impossible = outcome else { return XCTFail("Expected impossible, got \(outcome)") }
        XCTAssertEqual(store.rules.count, 1, "An impossible rule is not added")
    }

    func testAPreferredRuleIsNeverRefusedAsImpossible() throws {
        let store = try makeStore()
        store.rules = [PlanningRule(title: "Fish", constraint: .minimumPerWeek(matcher: .tag(.fish), count: 4))]
        let soft = PlanningRule(title: "Meat", strength: .preferred, constraint: .minimumPerWeek(matcher: .tag(.meat), count: 4))
        XCTAssertEqual(store.addRule(soft), .added)
    }

    func testTwoKindsNoDishIsBothOnOneDayAreRefused() throws {
        let store = try makeStore()
        store.rules = []
        let fish = PlanningRule(title: "Fish Friday", constraint: .requiredOn(day: .day(.friday), matcher: .tag(.fish)))
        XCTAssertEqual(store.addRule(fish), .added)
        // No sample dish is both fish and chicken.
        XCTAssertFalse(meals.contains { $0.tags.contains(.fish) && $0.tags.contains(.chicken) })
        let chicken = PlanningRule(title: "Chicken Friday", constraint: .requiredOn(day: .day(.friday), matcher: .tag(.chicken)))
        guard case .impossible = store.addRule(chicken) else { return XCTFail("Expected impossible") }
    }

    func testTightDaysNameADayTheRulesLeaveNoChoiceOn() throws {
        let store = try makeStore()
        store.rules = [PlanningRule(title: "Impossible Monday",
                                    constraint: .requiredOn(day: .day(.monday), matcher: .ingredient("zzz-no-such-thing")))]
        let tight = store.tightDays()
        XCTAssertEqual(tight.first { $0.day == .monday }?.count, 0)
        XCTAssertNil(tight.first { $0.day == .tuesday })
    }

    // MARK: - Who cooks

    func testTheCookSurvivesAReshuffleOfTheDay() throws {
        let store = try makeStore()
        store.addHouseholdMember(named: "Kari")
        let kari = try XCTUnwrap(store.household.members.first { $0.displayName == "Kari" })
        store.setCook(kari.id, for: .wednesday)
        store.shuffle(day: .wednesday)
        XCTAssertEqual(store.cook(for: .wednesday)?.id, kari.id)
        XCTAssertNil(store.cook(for: .wednesday, nextWeek: true))

        store.setCook(nil, for: .wednesday)
        XCTAssertNil(store.cook(for: .wednesday))
    }

    func testAMemberWhoLeftIsNoLongerTheCook() throws {
        let store = try makeStore()
        store.addHouseholdMember(named: "Ola")
        let index = try XCTUnwrap(store.household.members.firstIndex { $0.displayName == "Ola" })
        store.setCook(store.household.members[index].id, for: .thursday)
        store.removeHouseholdMembers(at: IndexSet(integer: index))
        XCTAssertNil(store.cook(for: .thursday))
    }

    func testRemindersAreToldWhoCooks() async throws {
        let reminders = RecordingReminderScheduler()
        let store = try makeStore(reminders: reminders)
        store.addHouseholdMember(named: "Kari")
        let kari = try XCTUnwrap(store.household.members.first { $0.displayName == "Kari" })
        store.setCook(kari.id, for: .friday)
        await store.refreshRemindersAndWidget()?.value
        let stamp = WidgetSummary.stamp(for: store.plan.date(for: .friday))
        XCTAssertEqual(reminders.lastSchedule?.cooks[stamp], "Kari")
    }

    // MARK: - Wishes and votes

    func testOneWishPerChildAndAnsweringPutsItOnNextWeek() throws {
        let store = try makeStore()
        store.addHouseholdMember(named: "Emma", role: .child)
        let emma = try XCTUnwrap(store.household.members.first { $0.displayName == "Emma" })
        store.addWish(meals[0], from: emma)
        store.addWish(meals[1], from: emma)
        XCTAssertEqual(store.pendingWishes.count, 1)
        XCTAssertEqual(store.wish(from: emma)?.mealID, meals[1].id)

        let wish = try XCTUnwrap(store.wish(from: emma))
        store.resolveWish(wish, plannedOn: .saturday)
        XCTAssertTrue(store.pendingWishes.isEmpty)
        XCTAssertEqual(store.nextWeekPlan?[.saturday]?.mealID, meals[1].id)
    }

    func testDecliningAWishLeavesNextWeekAlone() throws {
        let store = try makeStore()
        store.addHouseholdMember(named: "Emma", role: .child)
        let emma = try XCTUnwrap(store.household.members.first { $0.displayName == "Emma" })
        store.addWish(meals[2], from: emma)
        let before = store.nextWeekPlan
        store.resolveWish(try XCTUnwrap(store.wish(from: emma)), plannedOn: nil)
        XCTAssertTrue(store.pendingWishes.isEmpty)
        XCTAssertEqual(store.nextWeekPlan, before)
    }

    func testVoteCandidatesAreStableAndSkipDishesAlreadyRated() throws {
        let store = try makeStore()
        store.addHouseholdMember(named: "Emma", role: .child)
        let emma = try XCTUnwrap(store.household.members.first { $0.displayName == "Emma" })
        let first = store.voteCandidates(for: emma)
        XCTAssertEqual(first.count, 6)
        XCTAssertEqual(store.voteCandidates(for: emma).map(\.id), first.map(\.id))
        let planned = Set(store.plan.meals.compactMap(\.mealID))
        XCTAssertTrue(first.allSatisfy { !planned.contains($0.id) })

        store.setPreference(.liked, for: first[0], member: emma.id)
        XCTAssertFalse(store.voteCandidates(for: emma).contains { $0.id == first[0].id })
        XCTAssertEqual(store.memberPreferences[emma.id]?[first[0].id], .liked)
    }

    func testWishesSurviveASaveAndOldToolsDecodeWithoutThem() throws {
        var tools = HouseholdTools()
        tools.wishes = [MealWish(memberID: UUID(), mealID: meals[0].id)]
        tools.sharesIngredients = true
        let decoded = try JSONDecoder().decode(HouseholdTools.self, from: JSONEncoder().encode(tools))
        XCTAssertEqual(decoded.wishes?.count, 1)
        XCTAssertEqual(decoded.sharesIngredients, true)

        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(HouseholdTools())) as? [String: Any])
        legacy["wishes"] = nil
        legacy["sharesIngredients"] = nil
        let old = try JSONDecoder().decode(HouseholdTools.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(old.wishes)
    }

    // MARK: - Busy evenings

    func testABusyEveningGetsAQuickDinner() throws {
        guard meals.contains(where: { $0.prepMinutes > 0 && $0.prepMinutes <= CalendarBusyEvenings.minutes }) else {
            throw XCTSkip("No quick dinners in the sample library")
        }
        for seed in UInt64(1)...8 {
            let store = try makeStore(seed: seed)
            store.rules = []
            store.busyEvenings = FixedBusyEvenings([.tuesday])
            store.shuffleAll()
            guard let item = store.plan[.tuesday], item.kind == .meal, let id = item.mealID,
                  let meal = store.meal(id: id) else { continue }
            XCTAssertTrue(meal.prepMinutes > 0 && meal.prepMinutes <= CalendarBusyEvenings.minutes,
                          "Seed \(seed) put \(meal.name) (\(meal.prepMinutes) min) on a busy Tuesday")
        }
    }

    func testTheCalendarLimitIsNeverSavedIntoTheDay() throws {
        let store = try makeStore()
        store.busyEvenings = FixedBusyEvenings([.tuesday])
        store.shuffleAll()
        XCTAssertNil(store.dayContexts[.tuesday]?.maximumPrepMinutes)
        XCTAssertEqual(store.busyDays(inWeekStarting: store.plan.startDate), [.tuesday])
    }

    // MARK: - Dinner year

    func testYearSummaryCountsCookedDinners() throws {
        let store = try makeStore()
        store.shuffleAll()
        let cooked = Weekday.ordered().compactMap { day -> (Weekday, Meal)? in
            guard let item = store.plan[day], item.kind == .meal, let id = item.mealID, let meal = store.meal(id: id) else { return nil }
            return (day, meal)
        }.prefix(3)
        for (day, meal) in cooked {
            store.handleReminderAction(.cooked(mealID: meal.id, day: day, date: store.plan.date(for: day)))
        }
        let year = Calendar.current.component(.year, from: store.plan.date(for: .monday))
        let summary = store.yearSummary(for: year)
        XCTAssertGreaterThanOrEqual(summary.dinners, 1)
        XCTAssertLessThanOrEqual(summary.distinctDishes, summary.dinners)
        XCTAssertEqual(summary.newDishes, summary.distinctDishes)
        XCTAssertLessThanOrEqual(summary.top.count, 3)
        XCTAssertEqual(store.yearSummary(for: year - 5).dinners, 0)
    }

    // MARK: - Photos

    func testPhotoNameRoundTripsAndOldMealsDecodeWithout() throws {
        var meal = meals[0]
        meal.photoName = "photo-1.jpg"
        let decoded = try JSONDecoder().decode(Meal.self, from: JSONEncoder().encode(meal))
        XCTAssertEqual(decoded.photoName, "photo-1.jpg")
        let plain = try JSONDecoder().decode(Meal.self, from: JSONEncoder().encode(meals[1]))
        XCTAssertNil(plain.photoName)
    }

    // MARK: - Shopping overlap

    func testSharedIngredientsAreCountedByCanonicalName() {
        let withIngredients = meals.filter { !MealPlanGenerator.ingredientKeys($0).isEmpty }
        guard let first = withIngredients.first else { return }
        XCTAssertEqual(MealPlanGenerator.sharedIngredientCount(first, with: [first]), 0, "A dish does not share with itself")
        let keys = MealPlanGenerator.ingredientKeys(first)
        XCTAssertFalse(keys.contains("salt"))
        if let partner = withIngredients.dropFirst().first(where: { !MealPlanGenerator.ingredientKeys($0).isDisjoint(with: keys) }) {
            XCTAssertGreaterThan(MealPlanGenerator.sharedIngredientCount(first, with: [partner]), 0)
        }
    }

    // MARK: - Migrations

    func testAVersionOneBlobMovesTasteToTheOwner() throws {
        let owner = UUID()
        let mealID = meals[0].id
        let blob: [String: Any] = [
            "hasCompletedOnboarding": true,
            "household": [
                "id": UUID().uuidString, "name": "Test", "inviteCode": "ABCDEFGH",
                "members": [["id": owner.uuidString, "displayName": "Me", "role": "owner"]]
            ],
            "preferences": [mealID.uuidString, "liked"]
        ]
        let data = try JSONSerialization.data(withJSONObject: blob)
        let migrated = try XCTUnwrap(JSONSerialization.jsonObject(with: StateMigrations.migrate(data)) as? [String: Any])
        XCTAssertEqual(migrated["schemaVersion"] as? Int, AppStateSnapshot.currentVersion)
        XCTAssertNil(migrated["preferences"])

        let snapshot = try AppStateSnapshot.decoding(data)
        XCTAssertEqual(snapshot.memberPreferences[owner]?[mealID], .liked)
    }

    func testCurrentAndNewerBlobsPassThroughUntouched() throws {
        let current = try JSONEncoder().encode(try makeStore().makeSnapshot())
        XCTAssertEqual(StateMigrations.migrate(current), current)

        let newer = try JSONSerialization.data(withJSONObject: ["schemaVersion": AppStateSnapshot.currentVersion + 1])
        XCTAssertEqual(StateMigrations.migrate(newer), newer)
        XCTAssertThrowsError(try AppStateSnapshot.decoding(newer))

        let garbage = Data("not json".utf8)
        XCTAssertEqual(StateMigrations.migrate(garbage), garbage)
    }

    func testTheStepsReachTheCurrentVersion() {
        XCTAssertEqual(StateMigrations.steps.map(\.from), Array(1..<AppStateSnapshot.currentVersion))
    }

    // MARK: - Recovery packages

    func testRecoveryKeepsTheNewestThree() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("recovery-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<5 {
            let url = root.appendingPathComponent("before-restore-\(index).mealbackup")
            try Data([UInt8(index)]).write(to: url)
            let date = Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 60)
            try FileManager.default.setAttributes([.creationDate: date, .modificationDate: date], ofItemAtPath: url.path)
        }
        DeviceBackupDocument.pruneRecovery(in: root, keeping: 3)
        let left = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
        XCTAssertEqual(left, ["before-restore-2.mealbackup", "before-restore-3.mealbackup", "before-restore-4.mealbackup"])
    }
}
