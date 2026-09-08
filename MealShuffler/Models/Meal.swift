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
    /// Labels the household invented, alongside the fixed ten.
    ///
    /// Families think in "kid-friendly", "cheap", "freezer" and "grandma's", none of which a
    /// closed enum can grow to hold. Kept separate from `tags` so the built-in categories
    /// stay a known set the generator can reason about.
    let customTags: Set<String>
    let ingredients: [Ingredient]
    let defaultServings: Int
    /// Rough cost of the whole meal, in the household's currency (minor units not used).
    ///
    /// Renamed from `estimatedCostNOK`, which baked a currency into the persisted schema.
    /// The legacy key is still read so existing installs keep their prices.
    let estimatedCost: Int?
    let instructions: [String]
    let source: MealSource
    /// Photography captured at import. Remote, not stored: emoji-only cards were the app's
    /// clearest "prototype" tell, and the page already carries an image worth using.
    let heroImageURL: URL?
    var updatedAt: Date
    var updatedBy: UUID
    /// Soft delete. A hard delete is indistinguishable from "never existed here" once two
    /// devices compare libraries, which is how deleted meals come back.
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        subtitle: String,
        emoji: String,
        prepMinutes: Int,
        tags: Set<MealTag>,
        customTags: Set<String> = [],
        ingredients: [Ingredient],
        defaultServings: Int = 4,
        estimatedCost: Int? = nil,
        instructions: [String] = [],
        source: MealSource = .builtIn,
        heroImageURL: URL? = nil,
        updatedAt: Date = .now,
        updatedBy: UUID = DeviceIdentity.current,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.emoji = emoji
        self.prepMinutes = prepMinutes
        self.tags = tags
        self.customTags = customTags
        self.ingredients = ingredients
        self.defaultServings = max(defaultServings, 1)
        self.estimatedCost = estimatedCost
        self.instructions = instructions
        self.source = source
        self.heroImageURL = heroImageURL
        self.updatedAt = updatedAt
        self.updatedBy = updatedBy
        self.deletedAt = deletedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, subtitle, emoji, prepMinutes, tags, customTags, ingredients
        case defaultServings, estimatedCost, instructions, source, heroImageURL
        case updatedAt, updatedBy, deletedAt
        /// Pre-rename key, decoded only.
        case estimatedCostNOK
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        subtitle = try values.decode(String.self, forKey: .subtitle)
        emoji = try values.decode(String.self, forKey: .emoji)
        prepMinutes = try values.decode(Int.self, forKey: .prepMinutes)
        tags = try values.decode(Set<MealTag>.self, forKey: .tags)
        customTags = try values.decodeIfPresent(Set<String>.self, forKey: .customTags) ?? []
        ingredients = try values.decode([Ingredient].self, forKey: .ingredients)
        defaultServings = try values.decodeIfPresent(Int.self, forKey: .defaultServings) ?? 4
        estimatedCost = try values.decodeIfPresent(Int.self, forKey: .estimatedCost)
            ?? values.decodeIfPresent(Int.self, forKey: .estimatedCostNOK)
        instructions = try values.decodeIfPresent([String].self, forKey: .instructions) ?? []
        source = try values.decodeIfPresent(MealSource.self, forKey: .source) ?? .manual
        heroImageURL = try values.decodeIfPresent(URL.self, forKey: .heroImageURL)
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
        updatedBy = try values.decodeIfPresent(UUID.self, forKey: .updatedBy) ?? DeviceIdentity.current
        deletedAt = try values.decodeIfPresent(Date.self, forKey: .deletedAt)
    }

    // Written explicitly because the legacy cost key has no matching property, which would
    // otherwise defeat synthesis.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(subtitle, forKey: .subtitle)
        try container.encode(emoji, forKey: .emoji)
        try container.encode(prepMinutes, forKey: .prepMinutes)
        try container.encode(tags, forKey: .tags)
        try container.encode(customTags, forKey: .customTags)
        try container.encode(ingredients, forKey: .ingredients)
        try container.encode(defaultServings, forKey: .defaultServings)
        try container.encodeIfPresent(estimatedCost, forKey: .estimatedCost)
        try container.encode(instructions, forKey: .instructions)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(heroImageURL, forKey: .heroImageURL)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(updatedBy, forKey: .updatedBy)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
    }

    var isDeleted: Bool { deletedAt != nil }

    /// Copy stamped as changed on this device, so a later merge can order edits.
    func touched(at date: Date = .now) -> Meal {
        var copy = self
        copy.updatedAt = date
        copy.updatedBy = DeviceIdentity.current
        return copy
    }

    var planningCost: Int {
        if let estimatedCost { return estimatedCost }
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

/// Renders a meal's rough price in the reader's own currency.
///
/// `estimatedCost` was deliberately renamed off `estimatedCostNOK` to get a currency out of
/// the persisted schema, but the editor still said "NOK" out loud. The number is a household's
/// own rough figure, so it is shown in their locale's currency rather than converted.
enum MealCost {
    static func formatted(_ amount: Int) -> String {
        let code = Locale.current.currency?.identifier ?? "USD"
        return amount.formatted(.currency(code: code).precision(.fractionLength(0)))
    }
}
