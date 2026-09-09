import XCTest
@testable import MealShuffler

/// What a household can now say, and what the app refuses to let it say twice.
///
/// The rule vocabulary was five constraints over ten fixed tags, which could not express an
/// allergy, a person's dislikes, eating out on Fridays, or "not pasta two days running" --
/// all things families state as a matter of course.
final class RuleVocabularyTests: XCTestCase {
    private let meals = SampleMeals.all

    // MARK: - Day scopes

    /// Rules stored before scopes existed named a bare weekday. They must still decode.
    func testAStoredWeekdayDecodesAsThatDay() throws {
        let stored = Data(#""tuesday""#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(DayScope.self, from: stored), .day(.tuesday))
    }

    func testScopesRoundTrip() throws {
        for scope in DayScope.selectableCases {
            let data = try JSONEncoder().encode(scope)
            XCTAssertEqual(try JSONDecoder().decode(DayScope.self, from: data), scope)
        }
    }

    func testGroupsCoverTheDaysTheyName() {
        XCTAssertEqual(DayScope.weekend.days(), [.saturday, .sunday])
        XCTAssertEqual(DayScope.weekdays.days().count, 5)
        XCTAssertFalse(DayScope.weekdays.covers(.sunday))
        XCTAssertEqual(DayScope.everyDay.days(), Set(Weekday.allCases))
        XCTAssertTrue(DayScope.day(.monday).covers(.monday))
    }

    /// A rule about a group only re-rolls the days it names.
    func testAffectedDaysFollowTheScope() {
        XCTAssertEqual(
            RuleConstraint.requiredOn(day: .weekend, matcher: .tag(.pizza)).affectedDays,
            [.saturday, .sunday]
        )
        XCTAssertEqual(
            RuleConstraint.notOnConsecutiveDays(matcher: .tag(.pasta)).affectedDays,
            Set(Weekday.allCases)
        )
    }

    // MARK: - Matchers

    /// The gap that mattered most: an allergy is a fact about ingredients, and no amount of
    /// tagging makes "contains almonds" visible to a tag matcher.
    func testIngredientMatcherFindsWhatTagsCannot() throws {
        let salmon = try XCTUnwrap(meals.first { $0.name.localizedCaseInsensitiveContains("salmon") })
        XCTAssertTrue(MealMatcher.ingredient("salmon fillet").matches(salmon))
        XCTAssertTrue(MealMatcher.ingredient("SALMON").matches(salmon), "Case must not matter")
        XCTAssertFalse(MealMatcher.ingredient("almonds").matches(salmon))
        XCTAssertFalse(MealMatcher.ingredient("").matches(salmon), "An empty needle matches nothing")
    }

    func testIngredientMatcherIgnoresDiacritics() {
        let meal = Meal(
            name: "Test", subtitle: "", emoji: "🍽️", prepMinutes: 20, tags: [.quick],
            ingredients: [.init(name: "Gulrøtter", quantity: 2, unit: "pcs", aisle: .produce)]
        )
        XCTAssertTrue(MealMatcher.ingredient("gulrotter").matches(meal))
    }

    func testCustomTagMatcherIsExactButForgiving() {
        let meal = Meal(
            name: "Test", subtitle: "", emoji: "🍽️", prepMinutes: 20, tags: [.quick],
            customTags: ["Kid-friendly"],
            ingredients: [.init(name: "Rice", quantity: 200, unit: "g", aisle: .pantry)]
        )
        XCTAssertTrue(MealMatcher.customTag("kid-friendly").matches(meal))
        XCTAssertFalse(MealMatcher.customTag("kid").matches(meal), "A label is not a substring match")
    }

    /// Per-member preferences have been stored since taste became per-person, and nothing
    /// read them until a rule could ask.
    func testMemberMatcherReadsThatPersonsDislikes() throws {
        let emma = UUID()
        let disliked = try XCTUnwrap(meals.first)
        let other = try XCTUnwrap(meals.last)
        let context = MealMatcher.MatchContext(
            dislikes: [emma: [disliked.id]],
            memberNames: [emma: "Emma"]
        )
        XCTAssertTrue(MealMatcher.dislikedBy(memberID: emma).matches(disliked, context: context))
        XCTAssertFalse(MealMatcher.dislikedBy(memberID: emma).matches(other, context: context))
        XCTAssertTrue(
            MealMatcher.dislikedBy(memberID: emma).label(meals: meals, context: context).contains("Emma")
        )
    }

    // MARK: - Saying the same thing twice, or the opposite

    func testDuplicateAndContradictionDetection() {
        let fishTuesday = RuleConstraint.requiredOn(day: .day(.tuesday), matcher: .tag(.fish))
        XCTAssertTrue(fishTuesday.saysTheSameAs(.requiredOn(day: .day(.tuesday), matcher: .tag(.fish))))
        XCTAssertFalse(fishTuesday.saysTheSameAs(.requiredOn(day: .day(.friday), matcher: .tag(.fish))))

        XCTAssertTrue(fishTuesday.contradicts(.excludedOn(day: .day(.tuesday), matcher: .tag(.fish))))
        // A group scope overlapping a single day still contradicts.
        XCTAssertTrue(fishTuesday.contradicts(.excludedOn(day: .weekdays, matcher: .tag(.fish))))
        XCTAssertFalse(fishTuesday.contradicts(.excludedOn(day: .weekend, matcher: .tag(.fish))))
        XCTAssertFalse(fishTuesday.contradicts(.excludedOn(day: .day(.tuesday), matcher: .tag(.pizza))))

        XCTAssertTrue(
            RuleConstraint.minimumPerWeek(matcher: .tag(.fish), count: 3)
                .contradicts(.maximumPerWeek(matcher: .tag(.fish), count: 1))
        )
        XCTAssertTrue(
            RuleConstraint.maximumPerWeek(matcher: .tag(.fish), count: 0).contradicts(fishTuesday)
        )
        // Two different plans for the same evening.
        XCTAssertTrue(
            RuleConstraint.dinnerMode(day: .day(.friday), mode: .takeaway)
                .contradicts(.dinnerMode(day: .day(.friday), mode: .away))
        )
        // A dinner required on a day nobody is eating at home.
        XCTAssertTrue(
            RuleConstraint.dinnerMode(day: .day(.tuesday), mode: .away).contradicts(fishTuesday)
        )
        XCTAssertFalse(
            RuleConstraint.dinnerMode(day: .day(.friday), mode: .away).contradicts(fishTuesday),
            "Tuesday and Friday do not overlap"
        )
        XCTAssertFalse(
            RuleConstraint.dinnerMode(day: .day(.tuesday), mode: .cook).contradicts(fishTuesday),
            "Cooking is what a required dinner needs"
        )
    }

    // MARK: - Summaries

    func testEveryConstraintReadsAsASentence() {
        let constraints: [RuleConstraint] = [
            .requiredOn(day: .weekend, matcher: .tag(.pizza)),
            .excludedOn(day: .weekdays, matcher: .ingredient("almonds")),
            .maximumPerWeek(matcher: .tag(.chicken), count: 2),
            .maximumPerWeek(matcher: .tag(.chicken), count: 0),
            .minimumPerWeek(matcher: .tag(.vegetarian), count: 2),
            .maximumPrepTime(day: .weekdays, minutes: 30),
            .dinnerMode(day: .day(.friday), mode: .takeaway),
            .noRepeatWithin(weeks: 1),
            .noRepeatWithin(weeks: 4),
            .requiredEvery(weeks: 3, matcher: .customTag("grandma's")),
            .notOnConsecutiveDays(matcher: .tag(.pasta))
        ]
        for constraint in constraints {
            let summary = PlanningRule(title: "x", constraint: constraint).summary(meals: meals)
            XCTAssertFalse(summary.trimmingCharacters(in: .whitespaces).isEmpty)
            XCTAssertFalse(summary.contains("%"), "Unfilled placeholder in: \(summary)")
        }
    }

    /// "Never" needed seven separate day rules before a count of zero was reachable.
    func testZeroPerWeekReadsAsNever() {
        let summary = PlanningRule(
            title: "x",
            constraint: .maximumPerWeek(matcher: .tag(.fish), count: 0)
        ).summary(meals: meals)
        XCTAssertTrue(summary.lowercased().contains("never") || summary.lowercased().contains("aldri"))
    }
}
