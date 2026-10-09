import XCTest
@testable import MealShuffler

/// Rules typed the way a household says them.
///
/// Every suggestion chip the app offers must parse, in both languages; the rest covers the
/// grammar's harder corners -- negations that belong to a day plan, numbers that are also
/// words, and Norwegian compounds that glue the day to the dish.
final class RuleSentenceParserTests: XCTestCase {
    private let meals = SampleMeals.all

    private func constraint(_ text: String, customTags: [String] = [], file: StaticString = #filePath, line: UInt = #line) -> RuleConstraint? {
        let outcome = RuleSentenceParser.parse(text, meals: meals, customTags: customTags)
        guard let rule = outcome.rule else {
            XCTFail("\"\(text)\" did not make a rule: \(outcome)", file: file, line: line)
            return nil
        }
        return rule.constraint
    }

    // MARK: - The chips

    func testEverySuggestionParses() {
        for suggestion in RuleSentenceParser.suggestions {
            XCTAssertNotNil(RuleSentenceParser.parse(suggestion, meals: meals).rule, suggestion)
        }
    }

    func testTheNorwegianSuggestionsParseToo() {
        let norwegian = [
            "Fredagstaco", "Fisk på tirsdag", "Kjøttfri mandag", "Sunn mat på hverdager",
            "Maks 30 minutter på hverdager", "Maks 2 kylling i uka", "Rester på onsdag",
            "Ikke pasta to dager på rad", "Pizza annenhver lørdag", "Ingen gjentakelser på 3 uker"
        ]
        for text in norwegian {
            XCTAssertNotNil(RuleSentenceParser.parse(text, meals: meals).rule, text)
        }
    }

    // MARK: - Days

    func testTheClassics() {
        XCTAssertEqual(constraint("Taco Friday"), .requiredOn(day: .day(.friday), matcher: .tag(.taco)))
        XCTAssertEqual(constraint("taco tuesday"), .requiredOn(day: .day(.tuesday), matcher: .tag(.taco)))
        XCTAssertEqual(constraint("Fish on Tuesday"), .requiredOn(day: .day(.tuesday), matcher: .tag(.fish)))
        XCTAssertEqual(constraint("Meatless Monday"), .requiredOn(day: .day(.monday), matcher: .tag(.vegetarian)))
        XCTAssertEqual(constraint("meat-free monday"), .requiredOn(day: .day(.monday), matcher: .tag(.vegetarian)))
    }

    /// Norwegian glues the day to the dish, in either order.
    func testNorwegianCompounds() {
        XCTAssertEqual(constraint("Fredagstaco"), .requiredOn(day: .day(.friday), matcher: .tag(.taco)))
        XCTAssertEqual(constraint("tacofredag"), .requiredOn(day: .day(.friday), matcher: .tag(.taco)))
        XCTAssertEqual(constraint("lørdagspizza"), .requiredOn(day: .day(.saturday), matcher: .tag(.pizza)))
        XCTAssertEqual(constraint("søndagsmiddag med kylling"), .requiredOn(day: .day(.sunday), matcher: .tag(.chicken)))
    }

    func testGroupsListsAndRanges() {
        XCTAssertEqual(constraint("Healthy on weekdays"), .requiredOn(day: .weekdays, matcher: .tag(.healthy)))
        XCTAssertEqual(constraint("pizza on the weekend"), .requiredOn(day: .weekend, matcher: .tag(.pizza)))
        XCTAssertEqual(constraint("monday to friday quick"), .requiredOn(day: .weekdays, matcher: .tag(.quick)))
        XCTAssertEqual(
            constraint("fish on tuesday and thursday"),
            .requiredOn(day: .selected([.tuesday, .thursday]), matcher: .tag(.fish))
        )
        XCTAssertEqual(constraint("only healthy meals"), .requiredOn(day: .everyDay, matcher: .tag(.healthy)))
    }

    // MARK: - Limits and counts

    func testWeeklyCounts() {
        XCTAssertEqual(constraint("Max 2 chicken a week"), .maximumPerWeek(matcher: .tag(.chicken), count: 2))
        XCTAssertEqual(constraint("maks 2 kylling i uka"), .maximumPerWeek(matcher: .tag(.chicken), count: 2))
        XCTAssertEqual(constraint("no more than 2 red meat per week"), .maximumPerWeek(matcher: .tag(.meat), count: 2))
        XCTAssertEqual(constraint("fewer than 3 pasta a week"), .maximumPerWeek(matcher: .tag(.pasta), count: 2))
        XCTAssertEqual(constraint("fish twice a week"), .minimumPerWeek(matcher: .tag(.fish), count: 2))
        XCTAssertEqual(constraint("at least 2 vegetarian dinners a week"), .minimumPerWeek(matcher: .tag(.vegetarian), count: 2))
    }

    /// "To" is two in Norwegian and a preposition in English; "en" is one and an article.
    func testAmbiguousNumberWordsOnlyCountInContext() {
        XCTAssertEqual(constraint("fisk to ganger i uka"), .minimumPerWeek(matcher: .tag(.fish), count: 2))
        XCTAssertEqual(constraint("en gang i uka fisk"), .minimumPerWeek(matcher: .tag(.fish), count: 1))
        XCTAssertEqual(constraint("monday to friday quick"), .requiredOn(day: .weekdays, matcher: .tag(.quick)))
    }

    func testTimeLimits() {
        XCTAssertEqual(constraint("Under 30 minutes on weekdays"), .maximumPrepTime(day: .weekdays, minutes: 30))
        XCTAssertEqual(constraint("mon-fri under 30min"), .maximumPrepTime(day: .weekdays, minutes: 30))
        XCTAssertEqual(constraint("half an hour on weekdays"), .maximumPrepTime(day: .weekdays, minutes: 30))
        XCTAssertEqual(constraint("dinner under an hour on sundays"), .maximumPrepTime(day: .day(.sunday), minutes: 60))
    }

    // MARK: - Bans and allergies

    func testNegationsBecomeBansOrExclusions() {
        XCTAssertEqual(constraint("no pasta on weekdays"), .excludedOn(day: .weekdays, matcher: .tag(.pasta)))
        XCTAssertEqual(constraint("ikke pasta på hverdager"), .excludedOn(day: .weekdays, matcher: .tag(.pasta)))
        XCTAssertEqual(constraint("no meat every day"), .maximumPerWeek(matcher: .tag(.meat), count: 0))
    }

    /// Foods outside the categories are kept as typed; the vocabulary decides what they find,
    /// so "nuts" still finds a hazelnut and "laks" is never trimmed to "lak".
    func testUnknownFoodsBecomeIngredients() {
        XCTAssertEqual(constraint("no nuts"), .excludedOn(day: .everyDay, matcher: .ingredient("nuts")))
        XCTAssertEqual(constraint("allergic to peanuts"), .excludedOn(day: .everyDay, matcher: .ingredient("peanuts")))
        XCTAssertEqual(constraint("salmon on monday"), .requiredOn(day: .day(.monday), matcher: .ingredient("salmon")))
    }

    // MARK: - Norwegian foods, clauses and negation scope

    /// The reported bug: "laks" became "lak" through an English plural rule.
    func testSalmonStaysSalmonAndOffersFishAsTheBroaderReading() throws {
        let reading = RuleSentenceParser.read("laks på torsdag", meals: meals)
        XCTAssertEqual(reading.rule?.constraint, .requiredOn(day: .day(.thursday), matcher: .ingredient("laks")))
        XCTAssertEqual(reading.food?.word, "laks")
        XCTAssertTrue(try XCTUnwrap(reading.food).alternatives.contains(.tag(.fish)))
        XCTAssertEqual(constraint("laksen på torsdag"), .requiredOn(day: .day(.thursday), matcher: .ingredient("laks")))
        XCTAssertTrue(reading.ignored.isEmpty)
    }

    func testInflectedAndMisspeltWordsAreRead() {
        XCTAssertEqual(constraint("tacoen på fredag"), .requiredOn(day: .day(.friday), matcher: .tag(.taco)))
        XCTAssertEqual(constraint("tako på fredag"), .requiredOn(day: .day(.friday), matcher: .tag(.taco)))
        XCTAssertEqual(constraint("fisk på torsdg"), .requiredOn(day: .day(.thursday), matcher: .tag(.fish)))
    }

    /// "Men ikke på mandag" belongs to its own clause, and borrows the food from the first.
    func testButNotScopesTheNegationToItsOwnClause() {
        let readings = RuleSentenceParser.readAll("pizza på fredag men ikke på mandag", meals: meals)
        XCTAssertEqual(readings.map { $0.reading.rule?.constraint }, [
            .requiredOn(day: .day(.friday), matcher: .tag(.pizza)),
            .excludedOn(day: .day(.monday), matcher: .tag(.pizza))
        ])
        XCTAssertEqual(
            RuleSentenceParser.readAll("pizza på fredag, men ikke på mandag", meals: meals).compactMap { $0.reading.rule?.constraint }.count,
            2, "The comma version means the same"
        )
    }

    func testANegatedLimitIsALimitNotABan() {
        XCTAssertEqual(constraint("ikke pasta mer enn to ganger i uka"), .maximumPerWeek(matcher: .tag(.pasta), count: 2))
        XCTAssertEqual(constraint("more than 2 vegetarian a week"), .minimumPerWeek(matcher: .tag(.vegetarian), count: 3))
    }

    /// Two whole rules joined by "og" are two rules; "fish on Tuesday and Thursday" is one.
    func testTwoRulesInOneSentenceAreBothKept() {
        let readings = RuleSentenceParser.readAll("fisk på fredag og kylling på mandag", meals: meals)
        XCTAssertEqual(readings.compactMap { $0.reading.rule?.constraint }, [
            .requiredOn(day: .day(.friday), matcher: .tag(.fish)),
            .requiredOn(day: .day(.monday), matcher: .tag(.chicken))
        ])
        XCTAssertEqual(RuleSentenceParser.readAll("fish on tuesday and thursday", meals: meals).count, 1)
    }

    /// A ban on several foods is each of them banned.
    func testABanOnSeveralFoodsBecomesOneBanEach() {
        let readings = RuleSentenceParser.readAll("no nuts or mushrooms", meals: meals)
        XCTAssertEqual(readings.compactMap { $0.reading.rule?.constraint }, [
            .excludedOn(day: .everyDay, matcher: .ingredient("nuts")),
            .excludedOn(day: .everyDay, matcher: .ingredient("mushrooms"))
        ])
        XCTAssertTrue(readings.allSatisfy { $0.reading.additionalFoods.isEmpty })
    }

    /// Anything but a ban is about one food, and the composer is told what was left out.
    func testAnExtraFoodInARequirementIsReportedNotDropped() {
        let reading = RuleSentenceParser.read("fisk eller kylling på mandag", meals: meals)
        XCTAssertEqual(reading.rule?.constraint, .requiredOn(day: .day(.monday), matcher: .tag(.fish)))
        XCTAssertEqual(reading.additionalFoods.map(\.matcher), [.tag(.chicken)])
    }

    func testEveryNthWeekday() throws {
        let rule = try XCTUnwrap(RuleSentenceParser.parse("taco hver 2. fredag", meals: meals).rule)
        XCTAssertEqual(rule.constraint, .requiredOn(day: .day(.friday), matcher: .tag(.taco)))
        XCTAssertEqual(rule.repeatEveryWeeks, 2)
    }

    /// "Glutenfri", "nøttefritt": a food with "-fri" glued on is a ban on that food.
    func testFreeCompoundsAreBans() {
        XCTAssertEqual(constraint("nøttefritt"), .excludedOn(day: .everyDay, matcher: .ingredient("nøtter")))
        XCTAssertEqual(constraint("glutenfri på mandag"), .excludedOn(day: .day(.monday), matcher: .ingredient("gluten")))
    }

    /// A compound is named by its last part: "kyllingsuppe" is a soup, chicken the other reading.
    func testCompoundFoodsReadAsOneFood() throws {
        let reading = RuleSentenceParser.read("kyllingsuppe på mandag", meals: [])
        XCTAssertEqual(reading.rule?.constraint, .requiredOn(day: .day(.monday), matcher: .tag(.soup)))
        XCTAssertEqual(try XCTUnwrap(reading.food).alternatives, [.tag(.chicken)])
        XCTAssertTrue(reading.additionalFoods.isEmpty)
    }

    func testAMemberWhoDislikesAFoodMakesASoftBan() throws {
        let ola = HouseholdMember(displayName: "Ola")
        let rule = try XCTUnwrap(RuleSentenceParser.parse("Ola liker ikke sopp", meals: meals, members: [ola]).rule)
        XCTAssertEqual(rule.constraint, .excludedOn(day: .everyDay, matcher: .ingredient("sopp")))
        XCTAssertEqual(rule.strength, .preferred)
        let general = try XCTUnwrap(RuleSentenceParser.parse("Ola liker ikke", meals: meals, members: [ola]).rule)
        XCTAssertEqual(general.constraint, .excludedOn(day: .everyDay, matcher: .dislikedBy(memberID: ola.id)))
    }

    /// The composer highlights what was read; every word gets a role.
    func testTokensCarryTheRoleTheyWereReadIn() {
        let tokens = RuleSentenceParser.read("maks 2 kylling i uka", meals: meals).tokens
        XCTAssertEqual(tokens.map(\.text), ["maks", "2", "kylling", "i", "uka"])
        XCTAssertEqual(tokens.first { $0.text == "kylling" }?.role, .food)
        XCTAssertEqual(tokens.first { $0.text == "2" }?.role, .number)
        let ignored = RuleSentenceParser.read("taco på fredag hurra", meals: meals).ignored
        XCTAssertEqual(ignored, ["hurra"])
    }

    // MARK: - Dishes and labels

    func testNamedDishesWinOverTheirCategories() throws {
        let fishTacos = try XCTUnwrap(meals.first { $0.name == "Fish tacos" })
        let lasagne = try XCTUnwrap(meals.first { $0.name == "Lasagne" })
        XCTAssertEqual(constraint("fish tacos on friday"), .requiredOn(day: .day(.friday), matcher: .exactMeal(fishTacos.id)))
        XCTAssertEqual(constraint("lasagne on sunday"), .requiredOn(day: .day(.sunday), matcher: .exactMeal(lasagne.id)))
    }

    func testCustomLabels() {
        XCTAssertEqual(
            constraint("kid-friendly on weekdays", customTags: ["kid-friendly"]),
            .requiredOn(day: .weekdays, matcher: .customTag("kid-friendly"))
        )
    }

    /// "Quick fish" is about fish; quick describes it.
    func testTheDishWinsOverAModifier() {
        XCTAssertEqual(constraint("quick fish on weekdays"), .requiredOn(day: .weekdays, matcher: .tag(.fish)))
    }

    // MARK: - The rest of the vocabulary

    func testDayPlans() {
        XCTAssertEqual(constraint("Leftovers on Wednesday"), .dinnerMode(day: .day(.wednesday), mode: .leftovers))
        XCTAssertEqual(constraint("takeaway friday"), .dinnerMode(day: .day(.friday), mode: .takeaway))
        XCTAssertEqual(constraint("vi spiser ute på fredag"), .dinnerMode(day: .day(.friday), mode: .away))
        XCTAssertEqual(constraint("nobody home on thursday"), .dinnerMode(day: .day(.thursday), mode: .away))
    }

    /// There is no rule for "no takeaway": day plans say what does happen.
    func testANegatedDayPlanAsksForARephrase() {
        guard case .incomplete = RuleSentenceParser.parse("no takeaway on weekdays", meals: meals) else {
            return XCTFail("A negated day plan must not silently become a takeaway rule")
        }
    }

    func testRepeatsAndRotation() {
        XCTAssertEqual(constraint("No repeats within 3 weeks"), .noRepeatWithin(weeks: 3))
        XCTAssertEqual(constraint("Ingen gjentakelser på 3 uker"), .noRepeatWithin(weeks: 3))
        XCTAssertEqual(constraint("not the same dinner twice in a week"), .noRepeatWithin(weeks: 1))
        XCTAssertEqual(constraint("no repeats for a month"), .noRepeatWithin(weeks: 4))
        XCTAssertEqual(constraint("fish every 2 weeks"), .requiredEvery(weeks: 2, matcher: .tag(.fish)))
        XCTAssertEqual(constraint("Not pasta two days in a row"), .notOnConsecutiveDays(matcher: .tag(.pasta)))
        XCTAssertEqual(constraint("Ikke pasta to dager på rad"), .notOnConsecutiveDays(matcher: .tag(.pasta)))
    }

    /// A day with an interval is the same day rule on a fortnightly schedule.
    func testEveryOtherWeekdayIsAScheduledDayRule() throws {
        let rule = try XCTUnwrap(RuleSentenceParser.parse("Pizza every other Saturday", meals: meals).rule)
        XCTAssertEqual(rule.constraint, .requiredOn(day: .day(.saturday), matcher: .tag(.pizza)))
        XCTAssertEqual(rule.repeatEveryWeeks, 2)
        XCTAssertNotNil(rule.firstWeek)
        XCTAssertEqual(try XCTUnwrap(RuleSentenceParser.parse("Pizza annenhver lørdag", meals: meals).rule).repeatEveryWeeks, 2)
    }

    func testSofteningWordsMakeAPreference() throws {
        XCTAssertEqual(try XCTUnwrap(RuleSentenceParser.parse("preferably fish on friday", meals: meals).rule).strength, .preferred)
        XCTAssertEqual(try XCTUnwrap(RuleSentenceParser.parse("gjerne fisk på fredag", meals: meals).rule).strength, .preferred)
        XCTAssertEqual(try XCTUnwrap(RuleSentenceParser.parse("fish on friday", meals: meals).rule).strength, .required)
    }

    func testHalfARuleSaysWhatIsMissing() {
        for text in ["fish", "friday", "max chicken"] {
            guard case .incomplete = RuleSentenceParser.parse(text, meals: meals) else {
                return XCTFail("\"\(text)\" should ask for the missing part")
            }
        }
        XCTAssertEqual(RuleSentenceParser.parse("   ", meals: meals), .notUnderstood)
    }

    func testTheTypedSentenceBecomesTheTitle() throws {
        XCTAssertEqual(try XCTUnwrap(RuleSentenceParser.parse("taco friday", meals: meals).rule).title, "Taco friday")
    }

    /// The healthy shelf must be deep enough for the rule the chips suggest.
    func testHealthyWeekdaysAreSatisfiable() {
        let healthy = meals.filter { $0.tags.contains(.healthy) }
        XCTAssertGreaterThanOrEqual(healthy.count, 7, "A healthy week without repeats needs real choice")
        XCTAssertGreaterThanOrEqual(healthy.filter { $0.tags.contains(.fish) }.count, 2, "Fish Tuesday and Thursday stay healthy")
    }

    /// A tag added by a newer version drops out rather than failing the whole meal.
    func testAnUnknownTagDoesNotLoseTheMeal() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(meals[0])) as? [String: Any])
        json["tags"] = ["fish", "somethingFromTheFuture"]
        let decoded = try JSONDecoder().decode(Meal.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.tags, [.fish])
    }
    func testBatchRetainsOverflowAndUnrecognizedText() {
        let input = Array(repeating: "Taco Friday", count: 12) + ["fish on Tuesday", "unfinished"]
        let readings = RuleSentenceParser.parseAll(input.joined(separator: "; "), meals: [])
        XCTAssertEqual(readings.map(\.text), input)
        XCTAssertEqual(readings.compactMap { $0.outcome.rule }.count, 12)
        XCTAssertNil(readings[12].outcome.rule)
    }

}
