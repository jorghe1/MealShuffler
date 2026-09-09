import XCTest
@testable import MealShuffler

/// What can and cannot go to Bring!, and what the link says when it can.
///
/// Bring only ever imports from a URL it fetches itself, so the interesting cases are the
/// meals that have no address at all -- which is most of the library.
final class BringExportTests: XCTestCase {

    private func meal(source: MealSource, servings: Int = 4) -> Meal {
        Meal(
            name: "Fiskegrateng", subtitle: "", emoji: "🐟", prepMinutes: 40, tags: [.fish],
            ingredients: [.init(name: "Torskefilet", quantity: 600, unit: "g", aisle: .meatAndFish)],
            defaultServings: servings,
            source: source
        )
    }

    private func query(_ url: URL) throws -> [String: String] {
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    func testAMealImportedFromALinkCarriesThatLinkAndTheServings() throws {
        let source = try XCTUnwrap(URL(string: "https://example.com/oppskrift/fiskegrateng"))
        let link = try XCTUnwrap(BringExport.deeplink(for: meal(source: .web(source)), servings: 6))
        let values = try query(link)

        XCTAssertEqual(link.host, "api.getbring.com")
        XCTAssertEqual(values["url"], source.absoluteString, "Bring re-reads the page itself")
        XCTAssertEqual(values["source"], "web")
        XCTAssertEqual(values["baseQuantity"], "4", "What the recipe itself serves")
        XCTAssertEqual(values["requestedQuantity"], "6", "What this household is cooking for")
    }

    /// The advertising identifier the app-to-app variant asks for is deliberately not sent.
    func testNoAdvertisingIdentifierIsSent() throws {
        let source = try XCTUnwrap(URL(string: "https://example.com/x"))
        let link = try XCTUnwrap(BringExport.deeplink(for: meal(source: .web(source))))
        let values = try query(link)
        XCTAssertNil(values["sha1AppleIdfa"])
        XCTAssertNil(values["sha1GoogleAdId"])
    }

    /// Everything else in the library has no address, and must not offer a link that opens
    /// Bring on nothing.
    func testMealsWithNoPageOfTheirOwnCannotGo() {
        for source in [MealSource.builtIn, .manual, .photo, .community(UUID())] {
            XCTAssertNil(BringExport.deeplink(for: meal(source: source)), "\(source) has no page")
        }
    }

    func testTheWeeksExportableDinnersAreTheOnesWithLinks() throws {
        let source = try XCTUnwrap(URL(string: "https://example.com/oppskrift"))
        let imported = meal(source: .web(source))
        let ownRecipe = meal(source: .manual)
        let plan = WeeklyPlan(meals: [
            PlannedMeal(day: .monday, mealID: ownRecipe.id, isLocked: false),
            PlannedMeal(day: .tuesday, mealID: imported.id, isLocked: false, servings: 5),
            PlannedMeal(day: .wednesday, mealID: nil, isLocked: false)
        ])

        let dinners = BringExport.exportableDinners(plan: plan, meals: [imported, ownRecipe])
        XCTAssertEqual(dinners.count, 1)
        XCTAssertEqual(dinners.first?.id, imported.id)
        XCTAssertEqual(try query(try XCTUnwrap(dinners.first?.link))["requestedQuantity"], "5",
                       "The day's own servings, not the recipe's")
    }
}
