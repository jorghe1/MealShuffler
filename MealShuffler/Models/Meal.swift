import Foundation

enum MealTag: String, CaseIterable, Codable, Identifiable, Hashable {
    case fish, chicken, meat, vegetarian, pizza, pasta, soup, taco, quick, weekend

    var id: String { rawValue }

    var name: String {
        switch self {
        case .fish: L10n.string("Fish")
        case .chicken: L10n.string("Chicken")
        case .meat: L10n.string("Meat")
        case .vegetarian: L10n.string("Vegetarian")
        case .pizza: L10n.string("Pizza")
        case .pasta: L10n.string("Pasta")
        case .soup: L10n.string("Soup")
        case .taco: L10n.string("Taco")
        case .quick: L10n.string("Quick")
        case .weekend: L10n.string("Weekend")
        }
    }

    var symbol: String {
        switch self {
        case .fish: "fish.fill"
        case .chicken: "bird.fill"
        case .meat: "fork.knife"
        case .vegetarian: "leaf.fill"
        case .pizza: "circle.grid.cross.fill"
        case .pasta: "takeoutbag.and.cup.and.straw.fill"
        case .soup: "cup.and.saucer.fill"
        case .taco: "flame.fill"
        case .quick: "bolt.fill"
        case .weekend: "sparkles"
        }
    }
}

enum GroceryAisle: String, CaseIterable, Codable, Identifiable, Hashable {
    case produce, bread, meatAndFish, dairy, pantry, frozen

    var id: String { rawValue }

    var name: String {
        switch self {
        case .produce: L10n.string("Produce")
        case .bread: L10n.string("Bread & bakery")
        case .meatAndFish: L10n.string("Meat & fish")
        case .dairy: L10n.string("Dairy")
        case .pantry: L10n.string("Pantry")
        case .frozen: L10n.string("Frozen")
        }
    }
}

struct Ingredient: Identifiable, Codable, Hashable {
    let name: String
    let quantity: Double
    let unit: String
    let aisle: GroceryAisle

    var id: String { "\(name.lowercased())|\(unit.lowercased())" }
}

enum MealSource: Codable, Hashable {
    case builtIn
    case manual
    case web(URL)
    case photo
    case community(UUID)
}

struct Meal: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let subtitle: String
    let emoji: String
    let prepMinutes: Int
    let tags: Set<MealTag>
    let ingredients: [Ingredient]
    let defaultServings: Int
    let estimatedCostNOK: Int?
    let instructions: [String]
    let source: MealSource

    init(
        id: UUID = UUID(),
        name: String,
        subtitle: String,
        emoji: String,
        prepMinutes: Int,
        tags: Set<MealTag>,
        ingredients: [Ingredient],
        defaultServings: Int = 4,
        estimatedCostNOK: Int? = nil,
        instructions: [String] = [],
        source: MealSource = .builtIn
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.emoji = emoji
        self.prepMinutes = prepMinutes
        self.tags = tags
        self.ingredients = ingredients
        self.defaultServings = max(defaultServings, 1)
        self.estimatedCostNOK = estimatedCostNOK
        self.instructions = instructions
        self.source = source
    }


    private enum CodingKeys: String, CodingKey {
        case id, name, subtitle, emoji, prepMinutes, tags, ingredients
        case defaultServings, estimatedCostNOK, instructions, source
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        subtitle = try values.decode(String.self, forKey: .subtitle)
        emoji = try values.decode(String.self, forKey: .emoji)
        prepMinutes = try values.decode(Int.self, forKey: .prepMinutes)
        tags = try values.decode(Set<MealTag>.self, forKey: .tags)
        ingredients = try values.decode([Ingredient].self, forKey: .ingredients)
        defaultServings = try values.decodeIfPresent(Int.self, forKey: .defaultServings) ?? 4
        estimatedCostNOK = try values.decodeIfPresent(Int.self, forKey: .estimatedCostNOK)
        instructions = try values.decodeIfPresent([String].self, forKey: .instructions) ?? []
        source = try values.decodeIfPresent(MealSource.self, forKey: .source) ?? .manual
    }

    var planningCostNOK: Int {
        if let estimatedCostNOK { return estimatedCostNOK }
        if tags.contains(.fish) { return 170 }
        if tags.contains(.chicken) || tags.contains(.meat) { return 145 }
        if tags.contains(.pizza) { return 120 }
        return 95
    }

    var isBuiltIn: Bool {
        if case .builtIn = source { return true }
        return false
    }
}

enum MealPreference: String, Codable {
    case liked, neutral, disliked
}
