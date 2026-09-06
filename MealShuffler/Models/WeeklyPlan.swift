import Foundation

enum PlannedMealKind: Codable, Hashable {
    case meal
    case leftovers(sourceDay: Weekday)
    case away
    case takeaway
}
struct PlannedMeal: Identifiable, Codable, Hashable {
    var id: Weekday { day }
    let day: Weekday
    var mealID: UUID?
    var isLocked: Bool
    var servings: Int
    var kind: PlannedMealKind

    init(
        day: Weekday,
        mealID: UUID?,
        isLocked: Bool,
        servings: Int = 4,
        kind: PlannedMealKind = .meal
    ) {
        self.day = day
        self.mealID = mealID
        self.isLocked = isLocked
        self.servings = max(servings, 0)
        self.kind = kind
    }

    private enum CodingKeys: String, CodingKey {
        case day, mealID, isLocked, servings, kind
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        day = try values.decode(Weekday.self, forKey: .day)
        mealID = try values.decodeIfPresent(UUID.self, forKey: .mealID)
        isLocked = try values.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        servings = try values.decodeIfPresent(Int.self, forKey: .servings) ?? 4
        kind = try values.decodeIfPresent(PlannedMealKind.self, forKey: .kind) ?? .meal
    }
}

struct WeeklyPlan: Codable, Hashable {
    /// Midnight on the first day of the week this plan covers.
    ///
    /// Without it the plan is a floating artefact: it cannot roll over, cannot be archived
    /// against a date, and nothing can be scheduled from it.
    var startDate: Date
    var meals: [PlannedMeal]

    init(startDate: Date = WeekAnchor.startOfCurrentWeek(), meals: [PlannedMeal]) {
        self.startDate = startDate
        self.meals = meals
    }

    static var empty: WeeklyPlan { WeeklyPlan(meals: []) }

    /// True once the calendar has moved past this plan's week.
    func isStale(now: Date = .now, calendar: Calendar = .current) -> Bool {
        startDate < WeekAnchor.startOfWeek(containing: now, calendar: calendar)
    }

    func date(for day: Weekday, calendar: Calendar = .current) -> Date {
        day.date(inWeekStarting: startDate, calendar: calendar)
    }

    /// Same plan, re-anchored to another week.
    func anchored(to start: Date) -> WeeklyPlan {
        var copy = self
        copy.startDate = start
        return copy
    }

    subscript(day: Weekday) -> PlannedMeal? {
        get { meals.first(where: { $0.day == day }) }
        set {
            meals.removeAll(where: { $0.day == day })
            if let newValue { meals.append(newValue) }
            let order = Weekday.ordered()
            meals.sort {
                (order.firstIndex(of: $0.day) ?? 0) < (order.firstIndex(of: $1.day) ?? 0)
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case startDate, meals
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // Plans written before the week was dated are adopted into the current week.
        startDate = try values.decodeIfPresent(Date.self, forKey: .startDate)
            ?? WeekAnchor.startOfCurrentWeek()
        meals = try values.decodeIfPresent([PlannedMeal].self, forKey: .meals) ?? []
    }
}

/// A finished week, kept so history can answer "what did we eat".
struct ArchivedWeek: Codable, Hashable, Identifiable {
    let id: UUID
    let plan: WeeklyPlan
    let archivedAt: Date

    var startDate: Date { plan.startDate }

    init(id: UUID = UUID(), plan: WeeklyPlan, archivedAt: Date = .now) {
        self.id = id
        self.plan = plan
        self.archivedAt = archivedAt
    }
}

enum DayDinnerMode: String, Codable, CaseIterable, Identifiable {
    case cook, leftovers, away, takeaway
    var id: String { rawValue }

    var name: String {
        switch self {
        case .cook: L10n.string("Cook dinner")
        case .leftovers: L10n.string("Eat leftovers")
        case .away: L10n.string("Nobody home")
        case .takeaway: L10n.string("Takeaway")
        }
    }
}

struct DayPlanContext: Codable, Hashable {
    var diners: Int = 4
    var extraServings: Int = 0
    var maximumPrepMinutes: Int?
    var mode: DayDinnerMode = .cook
    var leftoverSourceDay: Weekday?

    var cookedServings: Int { max(diners + extraServings, 1) }
}

enum MealSwapIntent: String, CaseIterable, Identifiable {
    case different, quicker, cheaper, favorite, surprise
    var id: String { rawValue }

    var name: String {
        switch self {
        case .different: L10n.string("Something else")
        case .quicker: L10n.string("Something quicker")
        case .cheaper: L10n.string("Something cheaper")
        case .favorite: L10n.string("A favorite")
        case .surprise: L10n.string("Surprise me")
        }
    }

    var symbol: String {
        switch self {
        case .different: "arrow.triangle.2.circlepath"
        case .quicker: "bolt.fill"
        case .cheaper: "banknote.fill"
        case .favorite: "heart.fill"
        case .surprise: "sparkles"
        }
    }
}

enum PlanConflictSeverity: Hashable {
    /// A required rule the plan could not satisfy. Needs the user to decide something.
    case blocking
    /// An observation about how the week was built. Worth surfacing, but nothing is wrong.
    case informational
}

struct PlanConflict: Identifiable, Hashable {
    let id = UUID()
    let ruleID: UUID?
    let message: String
    let suggestion: String?
    let severity: PlanConflictSeverity

    init(
        ruleID: UUID? = nil,
        message: String,
        suggestion: String? = nil,
        severity: PlanConflictSeverity = .blocking
    ) {
        self.ruleID = ruleID
        self.message = message
        self.suggestion = suggestion
        self.severity = severity
    }
}

struct GenerationResult {
    let plan: WeeklyPlan
    let conflicts: [PlanConflict]
}

struct GroceryItem: Identifiable, Hashable {
    let name: String
    let quantity: Double
    let unit: String
    let aisle: GroceryAisle
    let mealNames: Set<String>

    var id: String { "\(name.lowercased())|\(unit.lowercased())" }

    var quantityText: String {
        IngredientUnits.display(quantity: quantity, unit: unit)
    }
}
