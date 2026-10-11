import XCTest
@testable import MealShuffler

/// "Plan this day" changes how much is cooked far more often than what is cooked.
///
/// In 0.6.0 every save re-rolled the day, ignoring its lock, so adding two guests on taco
/// Friday replaced the taco; and seating a member set the diner count to the number of members,
/// wiping the guests. These tests hold both lines.
@MainActor
final class DayPlanEditTests: XCTestCase {

    private func makeStore(seed: UInt64 = 31) throws -> AppStore {
        let suite = "DayPlanEditTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let store = AppStore(
            repository: UserDefaultsStateRepository(defaults: defaults),
            random: SeededRandomSource(seed: seed),
            widgetRefresher: RecordingWidgetRefresher(),
            reminderService: RecordingReminderScheduler()
        )
        store.completeOnboarding()
        return store
    }

    // MARK: - This week

    func testMoreDinersKeepsALockedDinnerAndRescalesIt() throws {
        let store = try makeStore()
        let taco = try XCTUnwrap(store.meals.first { $0.tags.contains(.taco) })
        store.setMeal(taco, on: .friday)

        var context = store.context(for: .friday)
        context.diners += 2
        store.updateContext(context, for: .friday)

        XCTAssertEqual(store.plan[.friday]?.mealID, taco.id, "Two guests are more taco, not a different dinner")
        XCTAssertEqual(store.plan[.friday]?.isLocked, true)
        XCTAssertEqual(store.plan[.friday]?.servings, context.cookedServings)
        XCTAssertNil(store.actionNotice)
    }

    func testPortionSizeKeepsAnUnlockedDinner() throws {
        let store = try makeStore()
        let day = try XCTUnwrap(Weekday.ordered().first {
            store.plan[$0]?.kind == .meal && store.plan[$0]?.isLocked == false && store.plan[$0]?.mealID != nil
        })
        let before = store.plan[day]?.mealID

        var context = store.context(for: day)
        context.portionScale = 0.5
        context.extraServings = 2
        store.updateContext(context, for: day)

        XCTAssertEqual(store.plan[day]?.mealID, before)
        XCTAssertEqual(store.plan[day]?.isLocked, false)
        XCTAssertEqual(store.plan[day]?.portionScale, 0.5)
        XCTAssertEqual(store.plan[day]?.servings, context.cookedServings)
    }

    func testDinerEditIsUndoable() throws {
        let store = try makeStore()
        let day = try XCTUnwrap(Weekday.ordered().first { store.plan[$0]?.kind == .meal })
        let servings = store.plan[day]?.servings

        var context = store.context(for: day)
        context.diners += 3
        store.updateContext(context, for: day)
        store.undoLastChange()

        XCTAssertEqual(store.plan[day]?.servings, servings)
    }

    func testATimeLimitTheDinnerBreaksReplacesItAndSaysSo() throws {
        let store = try makeStore()
        let slow = try XCTUnwrap(store.meals.first { $0.prepMinutes >= 45 })
        try XCTSkipUnless(store.meals.contains { $0.prepMinutes > 0 && $0.prepMinutes <= 25 }, "Needs a quick dinner to swap in")
        store.setMeal(slow, on: .wednesday)

        var context = store.context(for: .wednesday)
        context.maximumPrepMinutes = 25
        store.updateContext(context, for: .wednesday)

        XCTAssertNotEqual(store.plan[.wednesday]?.mealID, slow.id)
        XCTAssertNotNil(store.actionNotice, "A dinner that changes under a day edit is announced")
    }

    func testATimeLimitTheDinnerMeetsKeepsIt() throws {
        let store = try makeStore()
        let quick = try XCTUnwrap(store.meals.first { $0.prepMinutes > 0 && $0.prepMinutes <= 20 })
        store.setMeal(quick, on: .tuesday)

        var context = store.context(for: .tuesday)
        context.maximumPrepMinutes = 30
        store.updateContext(context, for: .tuesday)

        XCTAssertEqual(store.plan[.tuesday]?.mealID, quick.id)
    }

    func testANightOffStillReplacesTheDinner() throws {
        let store = try makeStore()
        let taco = try XCTUnwrap(store.meals.first { $0.tags.contains(.taco) })
        store.setMeal(taco, on: .saturday)

        var context = store.context(for: .saturday)
        context.mode = .takeaway
        store.updateContext(context, for: .saturday)

        XCTAssertEqual(store.plan[.saturday]?.kind, .takeaway)
        XCTAssertNil(store.actionNotice, "A different kind of evening is the point of the edit, not news")
    }

    func testSeatingSomeoneWhoDislikesTheDinnerReplacesIt() throws {
        let store = try makeStore()
        store.addHouseholdMember(named: "Ola")
        let ola = try XCTUnwrap(store.household.members.first { $0.displayName == "Ola" })
        let members = store.household.members.map(\.id)
        let taco = try XCTUnwrap(store.meals.first { $0.tags.contains(.taco) })
        store.setMeal(taco, on: .thursday)

        var away = store.context(for: .thursday)
        away.setAttending(false, member: ola.id, among: members)
        store.updateContext(away, for: .thursday)
        XCTAssertEqual(store.plan[.thursday]?.mealID, taco.id, "Someone leaving the table never changes the dinner")

        store.setPreference(.disliked, for: taco, member: ola.id)
        var home = store.context(for: .thursday)
        home.setAttending(true, member: ola.id, among: members)
        store.updateContext(home, for: .thursday)

        XCTAssertNotEqual(store.plan[.thursday]?.mealID, taco.id)
    }

    // MARK: - Next week

    func testMoreDinersNextWeekKeepsTheDinner() throws {
        let store = try makeStore()
        store.planNextWeek()
        let next = try XCTUnwrap(store.nextWeekPlan)
        let day = try XCTUnwrap(Weekday.ordered().first { next[$0]?.kind == .meal && next[$0]?.mealID != nil })
        let before = next[day]?.mealID

        var context = store.context(for: day, nextWeek: true)
        context.diners += 3
        store.updateNextWeekContext(context, for: day)

        XCTAssertEqual(store.nextWeekPlan?[day]?.mealID, before)
        XCTAssertEqual(store.nextWeekPlan?[day]?.servings, context.cookedServings)
    }

    // MARK: - Who is eating

    func testSeatingAMemberMovesTheCountByOneAndKeepsGuests() {
        let first = UUID(), second = UUID()
        // Two members and three guests.
        var context = DayPlanContext(diners: 5)

        context.setAttending(false, member: first, among: [first, second])
        XCTAssertEqual(context.diners, 4)
        XCTAssertEqual(context.attendingMemberIDs, [second])

        context.setAttending(false, member: first, among: [first, second])
        XCTAssertEqual(context.diners, 4, "Unseating someone already away changes nothing")

        context.setAttending(true, member: first, among: [first, second])
        XCTAssertEqual(context.diners, 5)
        XCTAssertEqual(context.attendingMemberIDs, [first, second])
    }

    func testTheCountNeverDropsBelowOne() {
        let only = UUID()
        var context = DayPlanContext(diners: 1)
        context.setAttending(false, member: only, among: [only])
        XCTAssertEqual(context.diners, 1)
    }
}
