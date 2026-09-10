import Foundation

enum MealFeedbackKind: String, Codable {
    case snoozed, cooked, skipped
}

/// An append-only record of what the household actually did with a planned meal.
///
/// Immutable, identified and timestamped, which makes merging two devices' logs a union by id
/// with no conflict resolution needed. Lives in `Models` rather than beside `AppStore` so the
/// widget and share extensions can decode saved state without pulling in the store.
struct MealFeedbackEvent: Identifiable, Codable, Hashable {
    let id: UUID
    let mealID: UUID
    let kind: MealFeedbackKind
    let timestamp: Date
    let weekday: Weekday?
    var plannedDate: Date?
    var recipeSnapshot: Meal?

    init(
        id: UUID = UUID(),
        mealID: UUID,
        kind: MealFeedbackKind,
        timestamp: Date = .now,
        weekday: Weekday? = nil,
        plannedDate: Date? = nil,
        recipeSnapshot: Meal? = nil
    ) {
        self.id = id
        self.mealID = mealID
        self.kind = kind
        self.timestamp = timestamp
        self.weekday = weekday
        self.plannedDate = plannedDate
        self.recipeSnapshot = recipeSnapshot
    }
}

/// Resolves the library the planner and the widgets draw from.
///
/// Shared so an extension shows exactly the meals the app would: a customised built-in is an
/// override of the original, not a second copy of it.
enum MealCatalog {
    static func resolve(builtIn: [Meal] = SampleMeals.all, custom: [Meal]) -> [Meal] {
        let live = custom.filter { !$0.isDeleted }
        let overrides = Dictionary(live.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        let builtInIDs = Set(builtIn.map(\.id))
        let hidden = Set(custom.filter(\.isDeleted).map(\.id))
        return builtIn.filter { !hidden.contains($0.id) }.map { overrides[$0.id] ?? $0 }
            + live.filter { !builtInIDs.contains($0.id) }
    }
}
