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

struct HouseholdTools: Codable, Hashable {
    var shoppingStart: Date?
    var shoppingEnd: Date?
    var shoppingSessions: [String: ShoppingSession] = [:]
    var cooking: [String: CookingProgress] = [:]
    var freezer: [FreezerBatch] = []
    var collections: [String: Set<UUID>] = [:]
    var dinnerHour: Int = 18
}
