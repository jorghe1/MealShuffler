import Foundation

/// Which days a rule speaks about.
///
/// Rules used to name one weekday, so "no pizza on weekdays" was five rules and "at most 30
/// minutes on a school night" was five more. A household states that once.
///
/// Encodes as a single string whose weekday values are exactly `Weekday`'s raw values, so
/// rules written before scopes existed decode straight into `.day`.
enum DayScope: Hashable, Codable, Identifiable {
    case day(Weekday)
    case weekdays
    case weekend
    case everyDay
    case selected(Set<Weekday>)

    var id: String { storedValue }

    /// Saturday and Sunday. Deliberately fixed rather than read from the locale: a household
    /// saying "weekend" means the days it does not work, and `Calendar` cannot know those.
    static let weekendDays: Set<Weekday> = [.saturday, .sunday]

    static var selectableCases: [DayScope] {
        [.everyDay, .weekdays, .weekend] + Weekday.ordered().map(DayScope.day)
    }

    func days() -> Set<Weekday> {
        switch self {
        case .day(let day): [day]
        case .weekdays: Set(Weekday.allCases).subtracting(Self.weekendDays)
        case .weekend: Self.weekendDays
        case .everyDay: Set(Weekday.allCases)
        case .selected(let days): days
        }
    }

    func covers(_ day: Weekday) -> Bool { days().contains(day) }

    var name: String {
        switch self {
        case .day(let day): day.name
        case .weekdays: L10n.string("weekdays")
        case .weekend: L10n.string("the weekend")
        case .everyDay: L10n.string("every day")
        case .selected(let days): Weekday.ordered().filter(days.contains).map(\.name).joined(separator: ", ")
        }
    }

    var sentencePhrase: String {
        switch self {
        case .day(let day): return day.recurringPhrase
        case .weekdays: return L10n.string("on weekdays")
        case .weekend: return L10n.string("at weekends")
        case .everyDay: return L10n.string("every day")
        case .selected(let days):
            return ListFormatter.localizedString(byJoining: Weekday.ordered().filter(days.contains).map(\.recurringPhrase))
        }
    }

    // MARK: - Coding

    private var storedValue: String {
        switch self {
        case .day(let day): day.rawValue
        case .weekdays: "scope.weekdays"
        case .weekend: "scope.weekend"
        case .everyDay: "scope.everyDay"
        case .selected(let days): "scope.selected:" + days.map(\.rawValue).sorted().joined(separator: ",")
        }
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if let day = Weekday(rawValue: raw) {
            self = .day(day)
            return
        }
        if raw.hasPrefix("scope.selected:") {
            let values = raw.dropFirst("scope.selected:".count).split(separator: ",").compactMap { Weekday(rawValue: String($0)) }
            if !values.isEmpty { self = .selected(Set(values)); return }
        }
        switch raw {
        case "scope.weekdays": self = .weekdays
        case "scope.weekend": self = .weekend
        case "scope.everyDay": self = .everyDay
        default:
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Unknown day scope \(raw)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storedValue)
    }
}

/// What a rule is about.
///
/// Tags alone could not express the two things households state most often: an allergy, which
/// is a fact about ingredients rather than about categories, and "whatever Emma will not eat",
/// which is a fact about a person.
enum MealMatcher: Codable, Hashable {
    case tag(MealTag)
    case exactMeal(UUID)
    /// Substring match against ingredient names, case- and diacritic-insensitively.
    ///
    /// Allergies live here. A nut allergy is not a category, and no amount of tagging makes
    /// "contains almonds" visible to a tag matcher.
    case ingredient(String)
    /// A label the household invented: "kid-friendly", "cheap", "freezer", "grandma's".
    case customTag(String)
    /// Anything this member swiped left on, read live from their stored preferences.
    case dislikedBy(memberID: UUID)

    func matches(_ meal: Meal, context: MatchContext = .empty) -> Bool {
        switch self {
        case .tag(let tag):
            return meal.tags.contains(tag)
        case .exactMeal(let id):
            return meal.id == id
        case .ingredient(let needle):
            let target = Self.fold(needle)
            guard !target.isEmpty else { return false }
            return meal.ingredients.contains { Self.fold($0.name).contains(target) }
        case .customTag(let label):
            let target = Self.fold(label)
            return meal.customTags.contains { Self.fold($0) == target }
        case .dislikedBy(let memberID):
            return context.dislikes[memberID]?.contains(meal.id) ?? false
        }
    }

    /// Everything a matcher needs that does not live on the meal itself.
    struct MatchContext: Hashable {
        var dislikes: [UUID: Set<UUID>] = [:]
        var memberNames: [UUID: String] = [:]
        var attendance: [Weekday: Set<UUID>] = [:]

        func forDay(_ day: Weekday) -> MatchContext {
            guard let present = attendance[day] else { return self }
            var copy = self
            copy.dislikes = dislikes.filter { present.contains($0.key) }
            return copy
        }

        static let empty = MatchContext()
    }

    /// Diacritic folding cannot be relied on for the Nordic letters: æ, ø and å are letters
    /// in their own right rather than accented vowels, so they are spelled out here. Without
    /// it, "gulrotter" typed into an allergy rule misses "Gulrøtter" on the shelf.
    private static let letterFolding: [(String, String)] = [
        ("\u{00E6}", "ae"), ("\u{00F8}", "o"), ("\u{00E5}", "a"), ("\u{00F6}", "o"), ("\u{00E4}", "a")
    ]

    private static func fold(_ value: String) -> String {
        var folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        for (letter, ascii) in letterFolding {
            folded = folded.replacingOccurrences(of: letter, with: ascii, options: .caseInsensitive)
        }
        return folded.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func sentenceLabel(meals: [Meal], context: MatchContext = .empty) -> String {
        if case .tag(let tag) = self {
            switch tag {
            case .vegetarian: return L10n.string("vegetarian meals")
            case .quick: return L10n.string("quick meals")
            case .weekend: return L10n.string("weekend meals")
            default: return tag.name.lowercased()
            }
        }
        switch self {
        case .ingredient(let name): return L10n.string("meals containing %@", name)
        case .customTag(let name): return L10n.string("meals labelled “%@”", name)
        case .dislikedBy(let id): return L10n.string("meals %@ dislikes", context.memberNames[id] ?? L10n.string("a family member"))
        default: return label(meals: meals, context: context)
        }
    }

    func label(meals: [Meal], context: MatchContext = .empty) -> String {
        switch self {
        case .tag(let tag): tag.name
        case .exactMeal(let id): meals.first(where: { $0.id == id })?.name ?? L10n.string("Selected meal")
        case .ingredient(let name): name
        case .customTag(let label): label
        case .dislikedBy(let memberID):
            L10n.string("what %@ dislikes", context.memberNames[memberID] ?? L10n.string("a family member"))
        }
    }
}

enum RuleConstraint: Codable, Hashable {
    case requiredOn(day: DayScope, matcher: MealMatcher)
    case excludedOn(day: DayScope, matcher: MealMatcher)
    case maximumPerWeek(matcher: MealMatcher, count: Int)
    case minimumPerWeek(matcher: MealMatcher, count: Int)
    case maximumPrepTime(day: DayScope, minutes: Int)
    /// Eating out, nobody home, or living off Sunday's leftovers -- stated once rather than
    /// re-entered in "Plan this day" every week.
    case dinnerMode(day: DayScope, mode: DayDinnerMode)
    /// Keeps a meal off the plan for a while after it was last served.
    ///
    /// The generator has always refused to repeat within one week and quietly discouraged
    /// anything cooked in the last fortnight. Neither was sayable, so neither was tunable.
    case noRepeatWithin(weeks: Int)
    /// The other direction: bring something back if it has been away too long.
    case requiredEvery(weeks: Int, matcher: MealMatcher)
    /// "Not pasta two days running."
    case notOnConsecutiveDays(matcher: MealMatcher)
}

extension RuleConstraint {
    /// Days whose dinner this constraint can change.
    ///
    /// Day-scoped rules only ever affect their own days, so editing one no longer needs to
    /// re-roll the whole week. Everything else genuinely spans it.
    var affectedDays: Set<Weekday> {
        switch self {
        case .requiredOn(let scope, _), .excludedOn(let scope, _),
             .maximumPrepTime(let scope, _), .dinnerMode(let scope, _):
            scope.days()
        case .maximumPerWeek, .minimumPerWeek, .noRepeatWithin,
             .requiredEvery, .notOnConsecutiveDays:
            Set(Weekday.allCases)
        }
    }

    var matcher: MealMatcher? {
        switch self {
        case .requiredOn(_, let matcher), .excludedOn(_, let matcher),
             .maximumPerWeek(let matcher, _), .minimumPerWeek(let matcher, _),
             .requiredEvery(_, let matcher), .notOnConsecutiveDays(let matcher):
            matcher
        case .maximumPrepTime, .dinnerMode, .noRepeatWithin:
            nil
        }
    }

    /// Two rules that say the same thing, whatever they are titled.
    ///
    /// `PlanningRule` carries an id and a title, so equality on the rule cannot answer this.
    func saysTheSameAs(_ other: RuleConstraint) -> Bool { self == other }

    /// Two rules that cannot both hold.
    ///
    /// Caught when a rule is offered rather than after a week has been built around it. Not
    /// exhaustive -- the generator still reports what it could not satisfy -- but it covers
    /// the flat contradictions a household writes by accident.
    func contradicts(_ other: RuleConstraint) -> Bool {
        switch (self, other) {
        case (.requiredOn(let scopeA, let matcherA), .excludedOn(let scopeB, let matcherB)),
             (.excludedOn(let scopeA, let matcherA), .requiredOn(let scopeB, let matcherB)):
            return matcherA == matcherB && !scopeA.days().isDisjoint(with: scopeB.days())

        case (.minimumPerWeek(let matcherA, let low), .maximumPerWeek(let matcherB, let high)),
             (.maximumPerWeek(let matcherB, let high), .minimumPerWeek(let matcherA, let low)):
            return matcherA == matcherB && low > high

        // "Never X" against "X on Tuesday".
        case (.maximumPerWeek(let matcherA, 0), .requiredOn(_, let matcherB)),
             (.requiredOn(_, let matcherB), .maximumPerWeek(let matcherA, 0)):
            return matcherA == matcherB

        // Two different plans for the same evening.
        case (.dinnerMode(let scopeA, let modeA), .dinnerMode(let scopeB, let modeB)):
            return modeA != modeB && !scopeA.days().isDisjoint(with: scopeB.days())

        // A dinner required on a day nobody is eating at home.
        case (.dinnerMode(let scopeA, let mode), .requiredOn(let scopeB, _)),
             (.requiredOn(let scopeB, _), .dinnerMode(let scopeA, let mode)):
            return mode != .cook && !scopeA.days().isDisjoint(with: scopeB.days())

        default:
            return false
        }
    }
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
    var repeatEveryWeeks: Int?
    var firstWeek: Date?

    var supportsPreference: Bool {
        if case .dinnerMode = constraint { return false }
        return true
    }

    func isActive(inWeek date: Date, calendar: Calendar = .current) -> Bool {
        guard isEnabled else { return false }
        guard let firstWeek else { return true }
        let start = WeekAnchor.startOfWeek(containing: firstWeek, calendar: calendar)
        let target = WeekAnchor.startOfWeek(containing: date, calendar: calendar)
        let weeks = calendar.dateComponents([.weekOfYear], from: start, to: target).weekOfYear ?? 0
        return weeks >= 0 && weeks % max(repeatEveryWeeks ?? 1, 1) == 0
    }

    func hasSameSchedule(as other: PlanningRule) -> Bool {
        let interval = max(repeatEveryWeeks ?? 1, 1)
        guard interval == max(other.repeatEveryWeeks ?? 1, 1) else { return false }
        if firstWeek == nil && other.firstWeek == nil { return true }
        let left = WeekAnchor.startOfWeek(containing: firstWeek ?? .distantPast)
        let right = WeekAnchor.startOfWeek(containing: other.firstWeek ?? .distantPast)
        if left == right { return true }
        let now = WeekAnchor.startOfWeek(containing: .now)
        if interval == 1, left <= now, right <= now { return true }
        return false
    }

    func nextActiveWeek(from date: Date) -> Date? {
        guard isEnabled else { return nil }
        var week = max(WeekAnchor.startOfWeek(containing: date), firstWeek.map { WeekAnchor.startOfWeek(containing: $0) } ?? .distantPast)
        for _ in 0..<max(repeatEveryWeeks ?? 1, 1) {
            if isActive(inWeek: week) { return week }
            week = WeekAnchor.startOfNextWeek(after: week)
        }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, isEnabled, strength, constraint, repeatEveryWeeks, firstWeek
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
        if !supportsPreference { self.strength = .required }
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try values.decode(String.self, forKey: .title)
        isEnabled = try values.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        strength = try values.decodeIfPresent(RuleStrength.self, forKey: .strength) ?? .required
        constraint = try values.decode(RuleConstraint.self, forKey: .constraint)
        repeatEveryWeeks = try values.decodeIfPresent(Int.self, forKey: .repeatEveryWeeks)
        firstWeek = try values.decodeIfPresent(Date.self, forKey: .firstWeek)
        if !supportsPreference { strength = .required }
    }

    func summary(meals: [Meal], context: MealMatcher.MatchContext = .empty) -> String {
        switch constraint {
        case .requiredOn(let scope, let matcher):
            return L10n.string("We cook %@ %@.", matcher.sentenceLabel(meals: meals, context: context), scope.sentencePhrase)
        case .excludedOn(let scope, let matcher):
            return L10n.string("We avoid %@ %@.", matcher.sentenceLabel(meals: meals, context: context), scope.sentencePhrase)
        case .maximumPerWeek(let matcher, let count):
            if count == 0 {
                return L10n.string("We never cook %@.", matcher.sentenceLabel(meals: meals, context: context))
            }
            return L10n.string("We cook %@ at most %ld times per week.", matcher.sentenceLabel(meals: meals, context: context), count)
        case .minimumPerWeek(let matcher, let count):
            return L10n.string("We cook %@ at least %ld times per week.", matcher.sentenceLabel(meals: meals, context: context), count)
        case .maximumPrepTime(let scope, let minutes):
            return L10n.string("Dinner takes at most %ld minutes %@.", minutes, scope.sentencePhrase)
        case .dinnerMode(let scope, let mode):
            switch mode {
            case .cook: return L10n.string("We cook dinner %@.", scope.sentencePhrase)
            case .leftovers: return L10n.string("We eat leftovers %@.", scope.sentencePhrase)
            case .takeaway: return L10n.string("We order takeaway %@.", scope.sentencePhrase)
            case .away: return L10n.string("We do not eat dinner at home %@.", scope.sentencePhrase)
            }
        case .noRepeatWithin(let weeks):
            return weeks == 1
                ? L10n.string("We do not cook the same dinner twice in one week.")
                : L10n.string("We do not cook the same dinner again within %ld weeks.", weeks)
        case .requiredEvery(let weeks, let matcher):
            return L10n.string("We cook %@ at least once every %ld weeks.", matcher.sentenceLabel(meals: meals, context: context), weeks)
        case .notOnConsecutiveDays(let matcher):
            return L10n.string("We do not cook %@ on consecutive days.", matcher.sentenceLabel(meals: meals, context: context))
        }
    }
}

extension PlanningRule {
    /// Saturday asks for *a* pizza rather than one specific one.
    ///
    /// This pinned `.exactMeal` to whichever pizza happened to sort first, so every Saturday
    /// for the life of the install served the same dinner -- a shuffling app with one
    /// permanently fixed day. A tag matcher gives the generator the whole pizza shelf.
    static func starterRules(meals: [Meal] = SampleMeals.all) -> [PlanningRule] {
        [
            PlanningRule(title: L10n.string("Fish on Tuesday"), constraint: .requiredOn(day: .day(.tuesday), matcher: .tag(.fish))),
            PlanningRule(title: L10n.string("Fish on Thursday"), constraint: .requiredOn(day: .day(.thursday), matcher: .tag(.fish))),
            PlanningRule(title: L10n.string("Varied protein"), constraint: .maximumPerWeek(matcher: .tag(.chicken), count: 2)),
            PlanningRule(title: L10n.string("Saturday pizza"), constraint: .requiredOn(day: .day(.saturday), matcher: .tag(.pizza))),
            PlanningRule(
                title: L10n.string("Keep it varied"),
                strength: .preferred,
                constraint: .noRepeatWithin(weeks: 3)
            )
        ]
    }
}
