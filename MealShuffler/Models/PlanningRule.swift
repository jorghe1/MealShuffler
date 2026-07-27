import Foundation

enum MealMatcher: Codable, Hashable {
    case tag(MealTag)
    case exactMeal(UUID)

    func matches(_ meal: Meal) -> Bool {
        switch self {
        case .tag(let tag): meal.tags.contains(tag)
        case .exactMeal(let id): meal.id == id
        }
    }

    func label(meals: [Meal]) -> String {
        switch self {
        case .tag(let tag): tag.name
        case .exactMeal(let id): meals.first(where: { $0.id == id })?.name ?? L10n.string("Selected meal")
        }
    }
}

enum RuleConstraint: Codable, Hashable {
    case requiredOn(day: Weekday, matcher: MealMatcher)
    case excludedOn(day: Weekday, matcher: MealMatcher)
    case maximumPerWeek(matcher: MealMatcher, count: Int)
    case minimumPerWeek(matcher: MealMatcher, count: Int)
    case maximumPrepTime(day: Weekday, minutes: Int)
}

enum RuleStrength: String, Codable, CaseIterable, Identifiable {
    case required
    case preferred

    var id: String { rawValue }
    var name: String {
        self == .required ? L10n.string("Required") : L10n.string("Preferred")
    }
}

struct PlanningRule: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var isEnabled = true
    var strength: RuleStrength = .required
    var constraint: RuleConstraint

    private enum CodingKeys: String, CodingKey {
        case id, title, isEnabled, strength, constraint
    }

    init(
        id: UUID = UUID(),
        title: String,
        isEnabled: Bool = true,
        strength: RuleStrength = .required,
        constraint: RuleConstraint
    ) {
        self.id = id
        self.title = title
        self.isEnabled = isEnabled
        self.strength = strength
        self.constraint = constraint
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try values.decode(String.self, forKey: .title)
        isEnabled = try values.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        strength = try values.decodeIfPresent(RuleStrength.self, forKey: .strength) ?? .required
        constraint = try values.decode(RuleConstraint.self, forKey: .constraint)
    }

    func summary(meals: [Meal]) -> String {
        switch constraint {
        case .requiredOn(let day, let matcher):
            L10n.string("%@ on %@", matcher.label(meals: meals), day.name.lowercased())
        case .excludedOn(let day, let matcher):
            L10n.string("No %@ on %@", matcher.label(meals: meals).lowercased(), day.name.lowercased())
        case .maximumPerWeek(let matcher, let count):
            L10n.string("Maximum %ld × %@ per week", count, matcher.label(meals: meals).lowercased())
        case .minimumPerWeek(let matcher, let count):
            L10n.string("At least %ld × %@ per week", count, matcher.label(meals: meals).lowercased())
        case .maximumPrepTime(let day, let minutes):
            L10n.string("Maximum %ld min on %@", minutes, day.name.lowercased())
        }
    }
}

extension PlanningRule {
    static func starterRules(meals: [Meal]) -> [PlanningRule] {
        let pizzaID = meals.first(where: { $0.tags.contains(.pizza) })?.id
        var rules = [
            PlanningRule(title: L10n.string("Fish on Tuesday"), constraint: .requiredOn(day: .tuesday, matcher: .tag(.fish))),
            PlanningRule(title: L10n.string("Fish on Thursday"), constraint: .requiredOn(day: .thursday, matcher: .tag(.fish))),
            PlanningRule(title: L10n.string("Varied protein"), constraint: .maximumPerWeek(matcher: .tag(.chicken), count: 2))
        ]
        if let pizzaID {
            rules.append(PlanningRule(title: L10n.string("Saturday pizza"), constraint: .requiredOn(day: .saturday, matcher: .exactMeal(pizzaID))))
        }
        return rules
    }
}
