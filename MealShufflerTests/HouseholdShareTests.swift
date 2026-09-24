import Compression
import XCTest
@testable import MealShuffler

/// Rules and recipes travelling between households inside a link.
///
/// The link is untrusted input from a chat message, so most of this is about what a receiving
/// household is protected from: oversized and corrupt payloads, references to people and
/// recipes it does not have, and a friend's list quietly overriding its own.
final class HouseholdShareTests: XCTestCase {
    private let meals = SampleMeals.all

    @MainActor
    private func makeStore() throws -> (AppStore, UserDefaults, String) {
        let suite = "HouseholdShareTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let repository = UserDefaultsStateRepository(defaults: defaults)
        return (AppStore(repository: repository, random: SeededRandomSource(seed: 11)), defaults, suite)
    }

    // MARK: - Codec

    func testRulesSurviveTheTrip() throws {
        let rules = PlanningRule.starterRules()
        let payload = SharedRules(from: "The Hansens", rules: rules, lines: ["a", "b"])
        let encoded = try ShareCodec.encode(payload)
        XCTAssertTrue(encoded.hasPrefix("1."), "The format version leads the payload")
        XCTAssertFalse(encoded.contains("+") || encoded.contains("/") || encoded.contains("="), "Must be base64url")
        let decoded = try ShareCodec.decode(SharedRules.self, from: encoded)
        XCTAssertEqual(decoded.from, "The Hansens")
        XCTAssertEqual(decoded.rules.map(\.constraint), rules.map(\.constraint))
    }

    /// A week of real recipes has to fit in something a chat app will carry.
    func testAWeekOfRecipesFitsInALink() throws {
        let week = Array(meals.prefix(7))
        let link = try XCTUnwrap(RecipeShare.link(meals: week, household: "Us"))
        XCTAssertLessThan(link.absoluteString.count, 12_000)
        let share = try XCTUnwrap(IncomingShare.parse(link))
        guard case .recipes(let received) = share else { return XCTFail("Expected recipes") }
        XCTAssertEqual(received.recipes.map(\.name), week.map(\.name))
    }

    func testGarbageIsRefusedNotCrashedOn() {
        for payload in ["", "1.", "1.!!!!", "2.AAAA", "1.AAAAAAAA", String(repeating: "A", count: 70_000)] {
            XCTAssertThrowsError(try ShareCodec.decode(SharedRules.self, from: payload), payload.prefix(12).description)
        }
    }

    /// Two megabytes of zeros compress to almost nothing; they must not inflate into memory.
    func testADecompressionBombStopsAtTheLimit() throws {
        let bomb = Data(repeating: 0x20, count: 2_000_000)
        let compressed = try XCTUnwrap(ShareCodec.deflate(bomb))
        XCTAssertLessThan(compressed.count, 20_000)
        XCTAssertNil(ShareCodec.inflate(compressed, limit: ShareCodec.maximumDecodedBytes))
        XCTAssertThrowsError(try ShareCodec.decode(SharedRules.self, from: "1." + ShareCodec.base64url(compressed)))
    }

    /// One rule from a newer version is dropped, not the whole message.
    func testAnUnreadableRuleDropsAlone() throws {
        let good = try JSONSerialization.jsonObject(with: JSONEncoder().encode(PlanningRule.starterRules()[0]))
        let future: [String: Any] = ["title": "From the future", "constraint": ["teleport": [String: Any]()] as [String: Any]]
        let json: [String: Any] = ["f": "Friends", "r": [good, future] as [Any], "l": [String]()]
        let data = try JSONSerialization.data(withJSONObject: json)
        let encoded = "1." + ShareCodec.base64url(try XCTUnwrap(ShareCodec.deflate(data)))
        XCTAssertEqual(try ShareCodec.decode(SharedRules.self, from: encoded).rules.count, 1)
    }

    // MARK: - Links

    func testAppLinksRoundTrip() throws {
        let url = ShareLinks.url(kind: .rules, payload: "1.abc_-", serviceBase: nil)
        XCTAssertEqual(url.scheme, "mealshuffler")
        let parsed = try XCTUnwrap(ShareLinks.parse(url, serviceBase: nil))
        XCTAssertEqual(parsed.kind, .rules)
        XCTAssertEqual(parsed.payload, "1.abc_-")
    }

    /// With the service deployed, the link opens a page that works without the app.
    func testServiceLinksUseTheLandingPage() throws {
        let base = try XCTUnwrap(URL(string: "https://recipes.example.workers.dev"))
        let url = ShareLinks.url(kind: .recipes, payload: "1.xyz", serviceBase: base)
        XCTAssertEqual(url.absoluteString, "https://recipes.example.workers.dev/s/recipes#1.xyz")
        XCTAssertEqual(ShareLinks.parse(url, serviceBase: base)?.kind, .recipes)
        let elsewhere = try XCTUnwrap(URL(string: "https://evil.example/s/recipes#1.xyz"))
        XCTAssertNil(ShareLinks.parse(elsewhere, serviceBase: base), "Only the configured service's pages are share links")
    }

    func testOtherURLsAreNotShares() throws {
        XCTAssertNil(try IncomingShare.parse(XCTUnwrap(URL(string: "mealshuffler://join/ABCD1234"))))
        XCTAssertNil(try IncomingShare.parse(XCTUnwrap(URL(string: "mealshuffler://share/rules"))))
        XCTAssertThrowsError(try IncomingShare.parse(XCTUnwrap(URL(string: "mealshuffler://share/rules#1.nope"))))
    }

    // MARK: - What travels

    func testRulesAboutPeopleAndPrivateRecipesStayHome() {
        let mine = Meal(name: "Grandma's stew", subtitle: "", emoji: "🍲", prepMinutes: 60, tags: [.meat], ingredients: [], source: .manual)
        let lasagne = meals.first { $0.name == "Lasagne" }!
        let rules = [
            PlanningRule(title: "Taco", constraint: .requiredOn(day: .day(.friday), matcher: .tag(.taco))),
            PlanningRule(title: "Emma", constraint: .maximumPerWeek(matcher: .dislikedBy(memberID: UUID()), count: 0)),
            PlanningRule(title: "Stew", constraint: .requiredOn(day: .day(.sunday), matcher: .exactMeal(mine.id))),
            PlanningRule(title: "Lasagne", constraint: .requiredOn(day: .day(.sunday), matcher: .exactMeal(lasagne.id))),
            PlanningRule(title: "Off", isEnabled: false, constraint: .noRepeatWithin(weeks: 2))
        ]
        XCTAssertEqual(HouseRulesShare.shareableRules(rules, meals: meals + [mine]).map(\.title), ["Taco", "Lasagne"])
    }

    func testReceivedRulesAreSanitized() {
        let incoming = [
            PlanningRule(title: "Sane", constraint: .maximumPerWeek(matcher: .tag(.chicken), count: 2)),
            PlanningRule(title: "Absurd", constraint: .maximumPerWeek(matcher: .tag(.chicken), count: 400)),
            PlanningRule(title: "Unknown dish", constraint: .requiredOn(day: .day(.monday), matcher: .exactMeal(UUID()))),
            PlanningRule(title: "Empty", constraint: .maximumPerWeek(matcher: .ingredient("   "), count: 0))
        ]
        let sanitized = HouseRulesShare.sanitized(incoming, meals: meals)
        XCTAssertEqual(sanitized.map(\.title), ["Sane"])
        XCTAssertNotEqual(sanitized[0].id, incoming[0].id, "A received rule gets an identity of its own")
    }

    func testARecipeKeepsWhatMattersAndDropsWhatIsUnsafe() throws {
        var shared = SharedRecipe(meal: meals[0])
        shared.source = URL(string: "javascript:alert(1)")
        shared.image = URL(string: "http://insecure.example/a.jpg")
        let meal = try XCTUnwrap(shared.meal())
        XCTAssertEqual(meal.name, meals[0].name)
        XCTAssertEqual(meal.ingredients.map(\.name), meals[0].ingredients.map(\.name))
        XCTAssertEqual(meal.tags, meals[0].tags)
        XCTAssertNotEqual(meal.id, meals[0].id)
        XCTAssertEqual(meal.source, .manual, "Only web pages survive as a source")
        XCTAssertNil(meal.heroImageURL, "Only secure images are loaded")
        XCTAssertFalse(meal.isBuiltIn)
    }

    // MARK: - Receiving, in a store

    /// A friend's list never overrides this household's own rules.
    @MainActor
    func testImportedRulesSkipDuplicatesAndContradictions() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let incoming = [
            PlanningRule(title: "Same as ours", constraint: .requiredOn(day: .day(.tuesday), matcher: .tag(.fish))),
            PlanningRule(title: "Against ours", constraint: .excludedOn(day: .day(.tuesday), matcher: .tag(.fish))),
            PlanningRule(title: "New", constraint: .requiredOn(day: .day(.friday), matcher: .tag(.taco)))
        ]
        let before = store.rules.count
        let outcome = store.importSharedRules(incoming)
        XCTAssertEqual(outcome, AppStore.SharedRulesOutcome(added: 1, duplicates: 1, conflicts: 1))
        XCTAssertEqual(store.rules.count, before + 1)
    }

    @MainActor
    func testImportedRecipesAreNewCopiesAndNotDoubled() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let newDish = Meal(name: "Friend's dal", subtitle: "", emoji: "🍛", prepMinutes: 30, tags: [.vegetarian],
                           ingredients: [Ingredient(name: "Red lentils", quantity: 300, unit: "g", aisle: .pantry)])
        let incoming = [SharedRecipe(meal: meals[0]), SharedRecipe(meal: newDish), SharedRecipe(meal: newDish)]
        XCTAssertEqual(store.importSharedRecipes(incoming), 1, "An existing dish and a repeat are skipped")
        let added = try XCTUnwrap(store.mealNamed("Friend's dal"))
        XCTAssertNotEqual(added.id, newDish.id)
        XCTAssertTrue(store.meals.contains { $0.id == added.id })
    }

    // MARK: - The whole list to Bring!

    /// Bring only imports from a URL it fetches, so the list needs the service to exist.
    func testTheWholeListGoesToBringOnlyThroughTheService() throws {
        let items = [GroceryItem(name: "Laks", quantity: 600, unit: "g", aisle: .meatAndFish, mealNames: [])]
        XCTAssertNil(BringExport.listLink(items: items, title: "Uke 39", serviceBase: nil))

        let base = try XCTUnwrap(URL(string: "https://svc.example"))
        let link = try XCTUnwrap(BringExport.listLink(items: items, title: "Uke 39", serviceBase: base))
        let deeplink = try XCTUnwrap(URLComponents(url: link, resolvingAgainstBaseURL: false))
        XCTAssertEqual(deeplink.host, "api.getbring.com")
        XCTAssertEqual(deeplink.queryItems?.first { $0.name == "requestedQuantity" }?.value, "1", "Already scaled; Bring must not scale again")

        let listURL = try XCTUnwrap(deeplink.queryItems?.first { $0.name == "url" }?.value.flatMap(URL.init(string:)))
        XCTAssertEqual(listURL.host, "svc.example")
        XCTAssertEqual(listURL.path, "/v1/bring/list")
        let payload = try XCTUnwrap(URLComponents(url: listURL, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "d" }?.value)
        struct List: Decodable { let n: String; let i: [String] }
        let list = try ShareCodec.decode(List.self, from: payload)
        XCTAssertEqual(list.n, "Uke 39")
        XCTAssertEqual(list.i.count, 1)
        XCTAssertTrue(list.i[0].hasSuffix("Laks"))
    }

    // MARK: - The poster and the odds

    func testThePosterNamesTheRuleThatDecidedADay() throws {
        let taco = try XCTUnwrap(meals.first { $0.tags.contains(.taco) && !$0.tags.contains(.fish) })
        let start = WeekAnchor.startOfCurrentWeek()
        let plan = WeeklyPlan(startDate: start, meals: [
            PlannedMeal(day: .friday, mealID: taco.id, isLocked: false),
            PlannedMeal(day: .saturday, mealID: nil, isLocked: false, kind: .takeaway)
        ])
        let rules = [
            PlanningRule(title: "Taco Friday", constraint: .requiredOn(day: .day(.friday), matcher: .tag(.taco))),
            PlanningRule(title: "Tacos any day", constraint: .requiredOn(day: .everyDay, matcher: .tag(.taco))),
            PlanningRule(title: "Saturday takeaway", constraint: .dinnerMode(day: .day(.saturday), mode: .takeaway))
        ]
        let poster = WeekPosterContent.make(plan: plan, meals: meals, rules: rules, household: "The Hansens", possibleWeeks: 1)
        XCTAssertEqual(poster.days.first { $0.day == .friday }?.badge, "Taco Friday", "The most specific rule wins")
        XCTAssertEqual(poster.days.first { $0.day == .saturday }?.badge, "Saturday takeaway")
        XCTAssertEqual(poster.heading, "The Hansens")
        XCTAssertEqual(poster.rulesKept, 3)
    }

    func testTheOddsMoveTheRightWay() {
        let plan = WeeklyPlan(startDate: WeekAnchor.startOfCurrentWeek(), meals: [])
        let open = ShuffleOdds.possibleWeeks(plan: plan, meals: meals, rules: [])
        let tight = ShuffleOdds.possibleWeeks(plan: plan, meals: meals, rules: [
            PlanningRule(title: "Fish", constraint: .requiredOn(day: .weekdays, matcher: .tag(.fish)))
        ])
        XCTAssertGreaterThan(open, 1_000_000, "Forty dinners over seven days is a lot of weeks")
        XCTAssertLessThan(tight, open, "A tighter rule allows fewer weeks")
        XCTAssertEqual(WeekPosterContent.compactCount(12), "12")
        XCTAssertEqual(WeekPosterContent.compactCount(0), "1")
    }
}
