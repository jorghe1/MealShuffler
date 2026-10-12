import XCTest
@testable import MealShuffler

/// A one-person household is addressed as one person: "du" and "mine" rather than "dere" and
/// "våre". The wording lives in Solo.strings; the store decides who is being spoken to.
@MainActor
final class HouseholdAddressTests: XCTestCase {

    private func makeStore() throws -> AppStore {
        let suite = "HouseholdAddressTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        return AppStore(
            repository: UserDefaultsStateRepository(defaults: defaults),
            random: SeededRandomSource(seed: 3),
            widgetRefresher: RecordingWidgetRefresher(),
            reminderService: RecordingReminderScheduler()
        )
    }

    /// The flag is process-wide, so every test puts it back.
    private func resetAfterwards() {
        addTeardownBlock { @MainActor in L10n.speaksToOne = false }
    }

    func testOnePersonReadsTheSoloWording() {
        resetAfterwards()
        L10n.speaksToOne = true
        XCTAssertEqual(L10n.household("Our favorites"), L10n.string("My favorites"))
        L10n.speaksToOne = false
        XCTAssertEqual(L10n.household("Our favorites"), L10n.string("Our favorites"))
    }

    func testAKeyWithoutASoloWordingReadsAsUsual() {
        resetAfterwards()
        L10n.speaksToOne = true
        XCTAssertEqual(L10n.household("Shopping list"), L10n.string("Shopping list"))
    }

    func testTheStoreSpeaksToOneOnlyWhenOneSitsDownAlone() throws {
        resetAfterwards()
        let store = try makeStore()
        store.setHouseholdSize(4)
        XCTAssertFalse(L10n.speaksToOne)

        store.setHouseholdSize(1)
        XCTAssertEqual(L10n.speaksToOne, store.household.members.count <= 1)

        store.addHouseholdMember(named: "Ola")
        XCTAssertFalse(L10n.speaksToOne, "Two members are a family even if one usually eats alone")
    }
}
