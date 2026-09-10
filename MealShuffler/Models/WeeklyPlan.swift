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
    var portionScale: Double?
    var freezerBatch: FreezerBatch?
    var freezerConsumed: Bool?
    var effectiveServings: Double { Double(servings) * max(0.25, portionScale ?? 1) }

    init(
        day: Weekday,
        mealID: UUID?,
        isLocked: Bool,
        servings: Int = 4,
        kind: PlannedMealKind = .meal,
        portionScale: Double? = nil
    ) {
        self.day = day
        self.mealID = mealID
        self.isLocked = isLocked
        self.servings = max(servings, 0)
        self.kind = kind
        self.portionScale = portionScale
    }

    private enum CodingKeys: String, CodingKey {
        case day, mealID, isLocked, servings, kind, portionScale, freezerBatch, freezerConsumed
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        day = try values.decode(Weekday.self, forKey: .day)
        mealID = try values.decodeIfPresent(UUID.self, forKey: .mealID)
        isLocked = try values.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        servings = try values.decodeIfPresent(Int.self, forKey: .servings) ?? 4
        kind = try values.decodeIfPresent(PlannedMealKind.self, forKey: .kind) ?? .meal
        portionScale = try values.decodeIfPresent(Double.self, forKey: .portionScale)
        freezerBatch = try values.decodeIfPresent(FreezerBatch.self, forKey: .freezerBatch)
        freezerConsumed = try values.decodeIfPresent(Bool.self, forKey: .freezerConsumed)
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
    var recipeSnapshots: [Meal]?

    var startDate: Date { plan.startDate }

    init(id: UUID = UUID(), plan: WeeklyPlan, archivedAt: Date = .now, recipes: [Meal] = []) {
        self.id = id
        self.plan = plan
        self.archivedAt = archivedAt
        let ids = Set(plan.meals.compactMap(\.mealID))
        recipeSnapshots = recipes.filter { ids.contains($0.id) }
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
    var overridesDinnerMode: Bool?
    var attendingMemberIDs: Set<UUID>?
    var freezerBatchID: UUID?
    var portionScale: Double?
    var effectiveDiners: Double { Double(diners) * max(0.25, portionScale ?? 1) }

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
    var plan: WeeklyPlan
    let conflicts: [PlanConflict]
}

/// Something the user added to the list themselves.
///
/// The list was derived purely from the plan, so there was no way to add milk to your own
/// shopping list -- which quietly undermines trust in the whole list.
struct ManualGroceryItem: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var quantity: Double?
    var unit: String
    var aisle: GroceryAisle
    var addedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        quantity: Double? = nil,
        unit: String = "",
        aisle: GroceryAisle = .pantry,
        addedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.aisle = aisle
        self.addedAt = addedAt
    }

    /// Matches the derived items' key so a manual entry merges with a planned one.
    var groceryID: String { IngredientUnits.key(name: name, unit: unit) }
}

struct GroceryItem: Identifiable, Hashable {
    let name: String
    let quantity: Double
    let unit: String
    let aisle: GroceryAisle
    let mealNames: Set<String>
    /// True when nothing in the plan calls for it -- the user typed it in.
    var isManual: Bool = false
    var hasUnspecifiedAmount: Bool = false
    var amountNote: String?

    var id: String { IngredientUnits.key(name: name, unit: unit) }

    var quantityText: String {
        // A manual item with no amount reads better as a bare name than as "1".
        guard quantity > 0 else { return hasUnspecifiedAmount ? (amountNote ?? L10n.string("Amount not specified")) : "" }
        let amount = IngredientUnits.display(quantity: quantity, unit: unit)
        return hasUnspecifiedAmount ? amount + " + " + (amountNote ?? L10n.string("Amount not specified")) : amount
    }
}
