import Foundation

struct ShoppingSession: Codable, Hashable {
    var checked: Set<String> = []
    var stocked: Set<String> = []
    var manual: [ManualGroceryItem] = []
    var amounts: [String: Double]?
}

struct CookingProgress: Codable, Hashable {
    var step = 0
    var gathered: Set<String> = []
    var timerEndsAt: Date?
}

struct FreezerBatch: Codable, Identifiable, Hashable {
    var id = UUID()
    var recipe: Meal
    var portions: Double
    var frozenOn = Date.now
    var label: String
}

/// A dinner a child wished for, waiting for a grown-up to say yes.
struct MealWish: Codable, Hashable, Identifiable {
    var id = UUID()
    let memberID: UUID
    let mealID: UUID
    var createdAt = Date.now
}

/// Household-wide tools and lists.
///
/// Decoded with the synthesized initializer, which requires every non-optional key to be
/// present. Anything added after the first release must be optional, or every saved
/// household fails to load.
struct HouseholdTools: Codable, Hashable {
    var shoppingStart: Date?
    var shoppingEnd: Date?
    var shoppingSessions: [String: ShoppingSession] = [:]
    var cooking: [String: CookingProgress] = [:]
    var freezer: [FreezerBatch] = []
    var collections: [String: Set<UUID>] = [:]
    var dinnerHour: Int = 18
    /// Wishes from the kids view, until a grown-up adds or declines them.
    var wishes: [MealWish]?
    /// "Fewer things to buy": the generator leans towards dinners that share ingredients
    /// with the rest of the week. Off unless chosen.
    var sharesIngredients: Bool?
}
