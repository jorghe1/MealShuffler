import XCTest
@testable import MealShuffler

/// Who is at the table, said once per person instead of re-entered day by day.
///
/// Children who live here in even weeks and training every Tuesday are the common cases. The
/// pattern sets each untouched day's attendance -- and so its portions and whose dislikes count
/// -- while a day planned by hand keeps what was set.
@MainActor
final class HomePatternTests: XCTestCase {

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day; components.hour = 12
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    private func weekStart(of date: Date) -> Date { WeekAnchor.startOfWeek(containing: date) }

    private func makeStore() throws -> AppStore {
        let suite = "HomePatternTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let store = AppStore(
            repository: UserDefaultsStateRepository(defaults: defaults),
            random: SeededRandomSource(seed: 7),
            widgetRefresher: RecordingWidgetRefresher(),
            reminderService: RecordingReminderScheduler()
        )
        store.completeOnboarding()
        return store
    }

    // MARK: - The pattern

    func testAlwaysHomeByDefault() {
        let member = HouseholdMember(displayName: "Kari")
        XCTAssertTrue(member.isHome(on: .tuesday, inWeekStarting: weekStart(of: date(2026, 10, 12))))
        XCTAssertTrue(HomePattern().isAlwaysHome)
    }

    func testEvenAndOddWeeksFollowTheIsoWeekNumber() {
        // Monday 12 October 2026 is in ISO week 42.
        let monday = date(2026, 10, 12)
        XCTAssertEqual(HomePattern.isoWeekNumber(of: monday), 42)
        let start = weekStart(of: monday)

        XCTAssertTrue(HomePattern(weeks: .even).isHome(on: .monday, inWeekStarting: start))
        XCTAssertFalse(HomePattern(weeks: .odd).isHome(on: .monday, inWeekStarting: start))

        let nextStart = WeekAnchor.startOfNextWeek(after: start)
        XCTAssertFalse(HomePattern(weeks: .even).isHome(on: .monday, inWeekStarting: nextStart))
        XCTAssertTrue(HomePattern(weeks: .odd).isHome(on: .monday, inWeekStarting: nextStart))
    }

    /// 2026 has 53 ISO weeks, so week 53 and the next year's week 1 are both odd: "odd weeks"
    /// means the week numbers, as a custody agreement written that way does.
    func testParityAcrossTheTurnOfA53WeekYear() {
        let week53 = date(2026, 12, 28)
        let week1 = date(2027, 1, 4)
        XCTAssertEqual(HomePattern.isoWeekNumber(of: week53), 53)
        XCTAssertEqual(HomePattern.isoWeekNumber(of: week1), 1)
        let odd = HomePattern(weeks: .odd)
        XCTAssertTrue(odd.isHome(on: .monday, inWeekStarting: weekStart(of: week53)))
        XCTAssertTrue(odd.isHome(on: .monday, inWeekStarting: weekStart(of: week1)))
    }

    func testAwayDaysApplyInTheWeeksSomeoneLivesHere() {
        let pattern = HomePattern(weeks: .even, awayDays: [.tuesday])
        let evenWeek = weekStart(of: date(2026, 10, 12))
        XCTAssertFalse(pattern.isHome(on: .tuesday, inWeekStarting: evenWeek))
        XCTAssertTrue(pattern.isHome(on: .wednesday, inWeekStarting: evenWeek))
        XCTAssertFalse(pattern.isAlwaysHome)
    }

    func testAPatternSurvivesCodingAndOldMembersStillDecode() throws {
        let member = HouseholdMember(displayName: "Emma", role: .child, homePattern: HomePattern(weeks: .odd, awayDays: [.friday]))
        let decoded = try JSONDecoder().decode(HouseholdMember.self, from: JSONEncoder().encode(member))
        XCTAssertEqual(decoded, member)

        let legacy = #"{"id":"\#(UUID().uuidString)","displayName":"Ola","role":"adult"}"#
        let old = try JSONDecoder().decode(HouseholdMember.self, from: Data(legacy.utf8))
        XCTAssertNil(old.homePattern, "A member saved before patterns existed is at home every day")
    }

    // MARK: - The week it sets

    func testSomeoneAwayByPatternTakesAPortionOffTheDay() throws {
        let store = try makeStore()
        store.setHouseholdSize(4)
        store.addHouseholdMember(named: "Ola")
        var ola = try XCTUnwrap(store.household.members.first { $0.displayName == "Ola" })
        ola.homePattern = HomePattern(awayDays: [.tuesday])
        store.updateMember(ola)

        let tuesday = store.context(for: .tuesday)
        XCTAssertEqual(tuesday.diners, 3)
        XCTAssertEqual(tuesday.attendingMemberIDs?.contains(ola.id), false)
        XCTAssertEqual(store.context(for: .wednesday).diners, 4)
        XCTAssertNil(store.context(for: .wednesday).attendingMemberIDs)
    }

    func testThePlanRescalesWhenAPatternChanges() throws {
        let store = try makeStore()
        store.setHouseholdSize(4)
        store.addHouseholdMember(named: "Ola")
        let day = try XCTUnwrap(Weekday.ordered().first { store.plan[$0]?.kind == .meal })
        let mealBefore = store.plan[day]?.mealID
        let servingsBefore = try XCTUnwrap(store.plan[day]?.servings)

        var ola = try XCTUnwrap(store.household.members.first { $0.displayName == "Ola" })
        ola.homePattern = HomePattern(awayDays: [day])
        store.updateMember(ola)

        XCTAssertEqual(store.plan[day]?.servings, servingsBefore - 1)
        XCTAssertEqual(store.plan[day]?.mealID, mealBefore, "A pattern changes the portions, not the dinner")
    }

    func testADayPlannedByHandKeepsWhatWasSet() throws {
        let store = try makeStore()
        store.setHouseholdSize(4)
        store.addHouseholdMember(named: "Ola")
        var context = store.context(for: .thursday)
        context.diners = 6
        store.updateContext(context, for: .thursday)

        var ola = try XCTUnwrap(store.household.members.first { $0.displayName == "Ola" })
        ola.homePattern = HomePattern(awayDays: [.thursday])
        store.updateMember(ola)

        XCTAssertEqual(store.context(for: .thursday).diners, 6)
    }

    func testDislikesOfSomeoneAwayByPatternDoNotCount() throws {
        let store = try makeStore()
        store.addHouseholdMember(named: "Ola")
        var ola = try XCTUnwrap(store.household.members.first { $0.displayName == "Ola" })
        ola.homePattern = HomePattern(awayDays: [.monday])
        store.updateMember(ola)

        XCTAssertEqual(store.matchContext.attendance[.monday]?.contains(ola.id), false)
        XCTAssertNil(store.matchContext.attendance[.tuesday])
    }

    func testAnAlwaysHomePatternIsStoredAsNone() throws {
        let store = try makeStore()
        store.addHouseholdMember(named: "Ola")
        var ola = try XCTUnwrap(store.household.members.first { $0.displayName == "Ola" })
        ola.homePattern = HomePattern()
        store.updateMember(ola)
        XCTAssertNil(store.household.members.first { $0.id == ola.id }?.homePattern)
    }

    func testGuestsAreTheDifferenceFromWhoIsExpected() throws {
        let store = try makeStore()
        store.setHouseholdSize(3)
        var context = store.context(for: .friday)
        context.diners = 5
        store.updateContext(context, for: .friday)
        XCTAssertEqual(store.context(for: .friday).diners - store.expectedDiners(on: .friday), 2)
    }
}
