import Foundation

/// Everything the shareable week picture says, worked out without drawing anything.
///
/// A shuffled week is the one thing this app makes that people want to show someone: the
/// family chat asking "what's for dinner", a friend who asked how you plan. The picture carries
/// the week, the household's own rule next to the day it decided ("Taco Friday"), and the number
/// of active rules, without claiming that every preference was satisfied.
struct WeekPosterContent: Equatable {
    struct Day: Identifiable, Equatable {
        let day: Weekday
        let emoji: String
        let title: String
        /// The household's own words for the rule that decided this day, when one did.
        let badge: String?
        let tags: Set<MealTag>
        let imageURL: URL?

        var id: Weekday { day }
    }

    let heading: String
    let weekLabel: String
    let days: [Day]
    let activeRuleCount: Int
    /// Emoji and count per kind of dinner, most first.
    let mix: [String]
    /// Active rules the week keeps. Set by the store, which knows the conflicts; nil leaves
    /// the claim off rather than guessing.
    var rulesKept: Int? = nil

    /// The week in one line of emoji, for a chat where a picture is too much:
    ///
    ///     Uke 41 🐟🌮🥦🍗♻️🍕🥘
    ///     5 av 5 husregler holdt ✓
    ///     https://apps.apple.com/…
    func emojiSummary(link: URL?) -> String {
        var lines = ["\(weekLabel) \(days.map(\.emoji).filter { $0 != "·" }.joined())"]
        if activeRuleCount > 0, let rulesKept {
            lines.append(L10n.string("%ld of %ld house rules kept ✓", rulesKept, activeRuleCount))
        }
        if let link { lines.append(link.absoluteString) }
        return lines.joined(separator: "\n")
    }

    static func make(
        plan: WeeklyPlan,
        meals: [Meal],
        rules: [PlanningRule],
        household: String,
        context: MealMatcher.MatchContext = .empty
    ) -> WeekPosterContent {
        let active = rules.filter { $0.isActive(inWeek: plan.startDate) }
        let days = Weekday.ordered().map { day -> Day in
            guard let item = plan[day] else {
                return Day(day: day, emoji: "·", title: L10n.string("Not planned"), badge: nil, tags: [], imageURL: nil)
            }
            let meal = item.freezerBatch?.recipe ?? item.mealID.flatMap { id in meals.first { $0.id == id } }
            let badge = Self.badge(for: day, item: item, meal: meal, rules: active, context: context)
            switch item.kind {
            case .away:
                return Day(day: day, emoji: "🏃", title: L10n.string("No dinner at home"), badge: badge, tags: [], imageURL: nil)
            case .takeaway:
                return Day(day: day, emoji: "🥡", title: L10n.string("Takeaway"), badge: badge, tags: [], imageURL: nil)
            case .leftovers:
                let title = meal.map { L10n.string("Leftovers: %@", $0.name) } ?? L10n.string("Leftovers")
                return Day(day: day, emoji: "♻️", title: title, badge: badge, tags: [], imageURL: nil)
            case .meal:
                guard let meal else {
                    return Day(day: day, emoji: "·", title: L10n.string("Not planned"), badge: nil, tags: [], imageURL: nil)
                }
                return Day(day: day, emoji: meal.emoji, title: meal.name, badge: badge, tags: meal.tags, imageURL: meal.heroImageURL)
            }
        }

        let isDefaultName = household.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || household == L10n.string("My family")
        return WeekPosterContent(
            heading: isDefaultName ? L10n.string("Our dinner week") : household,
            weekLabel: WeekAnchor.label(forWeekStarting: plan.startDate),
            days: days,
            activeRuleCount: active.count,
            mix: Self.mix(plan: plan, meals: meals)
        )
    }

    /// The most specific rule that put this dinner here: a Friday rule beats an every-day one.
    static func badge(for day: Weekday, item: PlannedMeal, meal: Meal?, rules: [PlanningRule], context: MealMatcher.MatchContext) -> String? {
        let deciding = rules.compactMap { rule -> (rule: PlanningRule, breadth: Int)? in
            switch rule.constraint {
            case .requiredOn(let scope, let matcher):
                guard item.kind == .meal, scope.covers(day), let meal, matcher.matches(meal, context: context.forDay(day)) else { return nil }
                return (rule: rule, breadth: scope.days().count)
            case .dinnerMode(let scope, let mode):
                guard scope.covers(day), DayDinnerMode.matching(item.kind) == mode else { return nil }
                return (rule: rule, breadth: scope.days().count)
            default:
                return nil
            }
        }
        guard let best = deciding.min(by: { $0.breadth < $1.breadth }) else { return nil }
        let title = best.rule.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : String(title.prefix(28))
    }

    private static func mix(plan: WeeklyPlan, meals: [Meal]) -> [String] {
        let kinds: [(tag: MealTag, emoji: String)] = [
            (tag: .fish, emoji: "🐟"), (tag: .chicken, emoji: "🍗"), (tag: .meat, emoji: "🥩"), (tag: .vegetarian, emoji: "🥦")
        ]
        var tally: [String: Int] = [:]
        for item in plan.meals where item.kind == .meal {
            guard let id = item.mealID, let meal = meals.first(where: { $0.id == id }) else { continue }
            let emoji = kinds.first { meal.tags.contains($0.tag) }?.emoji ?? "🍽️"
            tally[emoji, default: 0] += 1
        }
        return tally.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { "\($0.key) \($0.value)" }
    }

}

extension DayDinnerMode {
    /// The day plan a planned dinner is the result of.
    static func matching(_ kind: PlannedMealKind) -> DayDinnerMode {
        switch kind {
        case .meal: .cook
        case .leftovers: .leftovers
        case .away: .away
        case .takeaway: .takeaway
        }
    }
}
