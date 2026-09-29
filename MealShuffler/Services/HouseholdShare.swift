import Compression
import Foundation

/// Household-to-household sharing without an account, a server or a moderation queue.
///
/// The community tab is off until identity and moderation exist, and it should stay off. But
/// the way meal ideas actually travel between families is a message to a friend: "our rules
/// are taco Friday and fish twice a week", "here is the lasagne". That needs no backend at
/// all. Rules and recipes are packed into the link itself, after the `#`, so the whole payload
/// lives in the message: nothing is uploaded, nothing is stored, and a fragment is never sent
/// to any server -- not even to the landing page, when the recipe service hosts one.
///
/// Link shape: `mealshuffler://share/<kind>#1.<payload>`, or, when the recipe service is
/// deployed, `https://<service>/s/<kind>#1.<payload>` -- a page that shows the content to
/// someone without the app and hands it over to the app for someone with it. The payload is
/// JSON, raw-DEFLATE compressed, base64url encoded. The leading `1.` is the format version.
enum ShareCodec {
    enum ShareError: LocalizedError, Equatable {
        case unreadable
        case tooLarge

        var errorDescription: String? {
            switch self {
            case .unreadable: L10n.string("This shared link could not be read. Ask for a new one.")
            case .tooLarge: L10n.string("That is too much to fit in one link. Share fewer recipes at a time.")
            }
        }
    }

    static let version = "1"
    /// Past this, messaging apps start mangling links. A week of recipes fits comfortably.
    static let maximumEncodedLength = 60_000
    /// A decompression bomb stops here rather than filling memory.
    static let maximumDecodedBytes = 1_000_000

    static func encode<Value: Encodable>(_ value: Value) throws -> String {
        let json = try JSONEncoder().encode(value)
        guard json.count < maximumDecodedBytes else { throw ShareError.tooLarge }
        guard let compressed = deflate(json) else { throw ShareError.unreadable }
        let encoded = version + "." + base64url(compressed)
        guard encoded.count <= maximumEncodedLength else { throw ShareError.tooLarge }
        return encoded
    }

    static func decode<Value: Decodable>(_ type: Value.Type, from payload: String) throws -> Value {
        guard payload.count <= maximumEncodedLength, payload.hasPrefix(version + "."),
              let compressed = data(base64url: String(payload.dropFirst(version.count + 1))),
              let json = inflate(compressed, limit: maximumDecodedBytes) else { throw ShareError.unreadable }
        do { return try JSONDecoder().decode(Value.self, from: json) }
        catch { throw ShareError.unreadable }
    }

    static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func data(base64url text: String) -> Data? {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 { base64 += String(repeating: "=", count: 4 - remainder) }
        return Data(base64Encoded: base64)
    }

    /// Raw DEFLATE (RFC 1951), which is what `COMPRESSION_ZLIB` writes: no zlib header, the
    /// same format a browser's `DecompressionStream("deflate-raw")` reads on the landing page.
    static func deflate(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        let capacity = data.count + 1024
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { (destination: UnsafeMutableRawBufferPointer) -> Int in
            data.withUnsafeBytes { (source: UnsafeRawBufferPointer) -> Int in
                guard let target = destination.bindMemory(to: UInt8.self).baseAddress,
                      let origin = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_encode_buffer(target, capacity, origin, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }
        return Data(output.prefix(written))
    }

    /// Decodes into a fixed buffer, so an oversized payload is refused instead of allocated.
    static func inflate(_ data: Data, limit: Int) -> Data? {
        guard !data.isEmpty else { return nil }
        var output = Data(count: limit)
        let written = output.withUnsafeMutableBytes { (destination: UnsafeMutableRawBufferPointer) -> Int in
            data.withUnsafeBytes { (source: UnsafeRawBufferPointer) -> Int in
                guard let target = destination.bindMemory(to: UInt8.self).baseAddress,
                      let origin = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(target, limit, origin, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        // Filling the buffer exactly means the payload may have been cut short.
        guard written > 0, written < limit else { return nil }
        return Data(output.prefix(written))
    }
}

// MARK: - Links

enum ShareKind: String, CaseIterable {
    case rules, recipes
}

enum ShareLinks {
    /// The service's landing page when one is deployed; otherwise the app's own scheme.
    static func url(kind: ShareKind, payload: String, serviceBase: URL? = RemoteRecipeExtractor.Configuration.fromBundle()?.baseURL) -> URL {
        var components: URLComponents
        if let serviceBase, var web = URLComponents(url: serviceBase, resolvingAgainstBaseURL: false) {
            let base = web.path.hasSuffix("/") ? String(web.path.dropLast()) : web.path
            web.path = base + "/s/" + kind.rawValue
            web.query = nil
            components = web
        } else {
            components = URLComponents()
            components.scheme = "mealshuffler"
            components.host = "share"
            components.path = "/" + kind.rawValue
        }
        // Base64url and the version dot are all fragment-safe, so nothing needs escaping.
        components.percentEncodedFragment = payload
        return components.url ?? URL(string: "mealshuffler://share")!
    }

    /// The kind and payload of a share link, or nil for any other URL.
    static func parse(_ url: URL, serviceBase: URL? = RemoteRecipeExtractor.Configuration.fromBundle()?.baseURL) -> (kind: ShareKind, payload: String)? {
        guard let fragment = url.fragment, !fragment.isEmpty else { return nil }
        let scheme = url.scheme?.lowercased()
        let path = url.pathComponents.filter { $0 != "/" }
        if scheme == "mealshuffler", url.host == "share", let last = path.last, let kind = ShareKind(rawValue: last) {
            return (kind: kind, payload: fragment)
        }
        if scheme == "https", let serviceBase, url.host == serviceBase.host,
           path.count >= 2, path[path.count - 2] == "s", let kind = ShareKind(rawValue: path[path.count - 1]) {
            return (kind: kind, payload: fragment)
        }
        return nil
    }
}

// MARK: - House rules

/// A household's rules, as sent to another household.
struct SharedRules: Codable, Equatable {
    /// Who sent them, as their household is named.
    var from: String
    var rules: [PlanningRule]
    /// Each rule as the sender's app phrased it, for the landing page to show someone without
    /// the app. The receiving app re-phrases the rules itself and ignores these.
    var lines: [String]

    static let maximumRules = 30

    private enum CodingKeys: String, CodingKey { case from = "f", rules = "r", lines = "l" }

    init(from: String, rules: [PlanningRule], lines: [String]) {
        self.from = from
        self.rules = rules
        self.lines = lines
    }

    /// One unreadable rule -- a constraint from a newer version -- is dropped, not the lot.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        from = String((try values.decodeIfPresent(String.self, forKey: .from) ?? "").prefix(60))
        rules = (try values.decodeIfPresent([FailableRule].self, forKey: .rules) ?? []).compactMap(\.rule)
        lines = try values.decodeIfPresent([String].self, forKey: .lines) ?? []
    }

    private struct FailableRule: Decodable {
        let rule: PlanningRule?
        init(from decoder: Decoder) throws { rule = try? PlanningRule(from: decoder) }
    }
}

enum HouseRulesShare {
    /// Rules that mean the same thing in someone else's kitchen.
    ///
    /// A rule about what one member dislikes names a person the other household does not have,
    /// and a rule about one of this household's own recipes names a dish the other library
    /// lacks. Built-in dishes exist everywhere, so rules about them travel.
    static func shareableRules(_ rules: [PlanningRule], meals: [Meal]) -> [PlanningRule] {
        let builtIn = Set(SampleMeals.all.map(\.id))
        return rules.filter { rule in
            guard rule.isEnabled else { return false }
            switch rule.constraint.matcher {
            case .dislikedBy?: return false
            case .exactMeal(let id)?: return builtIn.contains(id)
            default: return true
            }
        }
        .prefix(SharedRules.maximumRules)
        .map { $0 }
    }

    static func payload(rules: [PlanningRule], household: String, meals: [Meal], context: MealMatcher.MatchContext = .empty) -> SharedRules {
        let shared = shareableRules(rules, meals: meals)
        return SharedRules(from: household, rules: shared, lines: shared.map { $0.summary(meals: meals, context: context) })
    }

    static func link(rules: [PlanningRule], household: String, meals: [Meal]) -> URL {
        let encoded = (try? ShareCodec.encode(payload(rules: rules, household: household, meals: meals))) ?? ""
        return ShareLinks.url(kind: .rules, payload: encoded)
    }

    /// The message that travels with the link, readable on its own.
    static func message(rules: [PlanningRule], household: String, meals: [Meal], context: MealMatcher.MatchContext) -> String {
        let lines = payload(rules: rules, household: household, meals: meals, context: context).lines.map { "• " + $0 }
        return ([L10n.string("House rules from %@:", household)] + lines + ["", L10n.string("Shuffle a week with our rules in Meal Shuffler:")])
            .joined(separator: "\n")
    }

    /// Makes received rules safe to add: fresh identities, sane numbers, no references this
    /// library cannot resolve, and the recurring ones restarted from this week.
    static func sanitized(_ rules: [PlanningRule], meals: [Meal], now: Date = .now) -> [PlanningRule] {
        let known = Set(meals.map(\.id))
        return rules.prefix(SharedRules.maximumRules).compactMap { incoming -> PlanningRule? in
            guard isSane(incoming.constraint, knownMeals: known) else { return nil }
            var rule = PlanningRule(
                title: String(incoming.title.prefix(80)),
                strength: incoming.strength,
                constraint: incoming.constraint
            )
            if let interval = incoming.repeatEveryWeeks, interval > 1 {
                rule.repeatEveryWeeks = min(interval, 8)
                rule.firstWeek = WeekAnchor.startOfWeek(containing: now)
            }
            return rule
        }
    }

    private static func isSane(_ constraint: RuleConstraint, knownMeals: Set<UUID>) -> Bool {
        switch constraint.matcher {
        case .dislikedBy?: return false
        case .exactMeal(let id)?: guard knownMeals.contains(id) else { return false }
        case .ingredient(let text)?, .customTag(let text)?:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count <= 60 else { return false }
        case .tag?, nil: break
        }
        switch constraint {
        case .maximumPerWeek(_, let count), .minimumPerWeek(_, let count): return (0...7).contains(count)
        case .maximumPrepTime(_, let minutes): return (5...480).contains(minutes)
        case .noRepeatWithin(let weeks), .requiredEvery(let weeks, _): return (1...12).contains(weeks)
        case .requiredOn(let scope, _), .excludedOn(let scope, _), .dinnerMode(let scope, _): return !scope.days().isEmpty
        case .notOnConsecutiveDays: return true
        }
    }
}

// MARK: - Recipes

/// A recipe as it travels: the dish, not this device's bookkeeping about it.
///
/// Source photos, drafts, revision history and edit stamps stay home. Short keys because every
/// byte is part of a link someone pastes into a chat.
struct SharedRecipe: Codable, Equatable {
    var name: String
    var subtitle: String
    var emoji: String
    var prepMinutes: Int
    var tags: [String]
    var labels: [String]?
    var servings: Int
    var ingredients: [SharedIngredient]
    var instructions: [String]
    var source: URL?
    var image: URL?
    var servingsConfirmed: Bool?
    var activeMinutes: Int?

    private enum CodingKeys: String, CodingKey {
        case name = "n", subtitle = "s", emoji = "e", prepMinutes = "p", tags = "t", labels = "c"
        case servings = "v", ingredients = "i", instructions = "x", source = "u", image = "h"
        case servingsConfirmed = "vc", activeMinutes = "am"
    }

    init(meal: Meal) {
        name = meal.name
        subtitle = meal.subtitle
        emoji = meal.emoji
        prepMinutes = meal.prepMinutes
        tags = meal.tags.map(\.rawValue).sorted()
        labels = meal.customTags.isEmpty ? nil : meal.customTags.sorted()
        servings = meal.defaultServings
        ingredients = meal.ingredients.map(SharedIngredient.init(ingredient:))
        instructions = meal.instructions
        if case .web(let url) = meal.source { source = url } else { source = nil }
        image = meal.heroImageURL
        servingsConfirmed = meal.servingsConfirmed
        activeMinutes = meal.activeMinutes
    }

    /// A new meal in the receiving library, or nil when there is nothing usable in it.
    func meal() -> Meal? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, cleanName.count <= 200 else { return nil }
        let parts = ingredients.prefix(200).compactMap { $0.ingredient() }
        func web(_ url: URL?) -> URL? {
            guard let url, let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return nil }
            return url
        }
        var result = Meal(
            name: cleanName,
            subtitle: String(subtitle.prefix(300)),
            emoji: emoji.isEmpty ? "🍽️" : String(emoji.prefix(4)),
            prepMinutes: min(max(prepMinutes, 0), 10_080),
            tags: Set(tags.compactMap(MealTag.init(rawValue:))),
            customTags: Set((labels ?? []).prefix(20).map { String($0.prefix(40)) }),
            ingredients: parts,
            defaultServings: min(max(servings, 1), 100),
            instructions: instructions.prefix(200).map { String($0.prefix(10_000)) },
            source: web(source).map { MealSource.web($0) } ?? MealSource.manual,
            heroImageURL: image.flatMap { $0.scheme?.lowercased() == "https" ? $0 : nil }
        )
        result.servingsConfirmed = servingsConfirmed
        result.activeMinutes = activeMinutes.flatMap { (0...10_080).contains($0) ? $0 : nil }
        return result
    }
}

struct SharedIngredient: Codable, Equatable {
    var name: String
    var quantity: Double
    var unit: String
    var aisle: String
    var text: String?
    var upper: Double?
    var packageQuantity: Double?
    var packageUnit: String?
    var amountNote: String?
    var section: String?
    var requiresReview: Bool?

    private enum CodingKeys: String, CodingKey {
        case name = "n", quantity = "q", unit = "u", aisle = "a", text = "o", upper = "r"
        case packageQuantity = "pq", packageUnit = "pu", amountNote = "an", section = "s", requiresReview = "rr"
    }

    init(ingredient: Ingredient) {
        name = ingredient.name
        quantity = ingredient.quantity
        unit = ingredient.unit
        aisle = ingredient.aisle.rawValue
        text = ingredient.originalText
        upper = ingredient.upperQuantity
        packageQuantity = ingredient.packageQuantity
        packageUnit = ingredient.packageUnit
        amountNote = ingredient.amountNote
        section = ingredient.section
        requiresReview = ingredient.requiresReview
    }

    func ingredient() -> Ingredient? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, cleanName.count <= 300, quantity.isFinite, (0...1_000_000).contains(quantity) else { return nil }
        var result = Ingredient(
            name: cleanName,
            quantity: quantity,
            unit: String(unit.prefix(20)),
            aisle: GroceryAisle(rawValue: aisle) ?? .pantry,
            originalText: text.map { String($0.prefix(500)) }
        )
        if let upper, upper.isFinite, upper >= quantity, upper <= 1_000_000 { result.upperQuantity = upper }
        result.amountNote = amountNote.map { String($0.prefix(200)) }
        result.section = section.map { String($0.prefix(200)) }
        result.requiresReview = requiresReview
        if packageQuantity != nil || packageUnit != nil {
            if let amount = packageQuantity, amount.isFinite, amount > 0, amount <= 1_000_000,
               let unit = packageUnit?.trimmingCharacters(in: .whitespacesAndNewlines), !unit.isEmpty, unit.count <= 20 {
                result.packageQuantity = amount
                result.packageUnit = unit
            } else {
                result.requiresReview = true
            }
        }
        if upper != nil && result.upperQuantity == nil { result.requiresReview = true }
        return result
    }
}

struct SharedRecipes: Codable, Equatable {
    var from: String
    var recipes: [SharedRecipe]

    static let maximumRecipes = 24

    private enum CodingKeys: String, CodingKey { case from = "f", recipes = "r" }

    init(from: String, recipes: [SharedRecipe]) {
        self.from = from
        self.recipes = recipes
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        from = String((try values.decodeIfPresent(String.self, forKey: .from) ?? "").prefix(60))
        recipes = (try values.decodeIfPresent([FailableRecipe].self, forKey: .recipes) ?? [])
            .compactMap(\.recipe)
            .prefix(Self.maximumRecipes)
            .map { $0 }
    }

    private struct FailableRecipe: Decodable {
        let recipe: SharedRecipe?
        init(from decoder: Decoder) throws { recipe = try? SharedRecipe(from: decoder) }
    }
}

enum RecipeShare {
    /// A link carrying these recipes, or nil when they will not fit in one.
    static func link(meals: [Meal], household: String) -> URL? {
        guard !meals.isEmpty, meals.count <= SharedRecipes.maximumRecipes else { return nil }
        let payload = SharedRecipes(from: household, recipes: meals.map(SharedRecipe.init(meal:)))
        guard let encoded = try? ShareCodec.encode(payload) else { return nil }
        return ShareLinks.url(kind: .recipes, payload: encoded)
    }

    static func message(meals: [Meal], household: String) -> String {
        let names = meals.map { "\($0.emoji) \($0.name)" }
        let header = meals.count == 1
            ? L10n.string("A recipe from %@:", household)
            : L10n.string("Recipes from %@:", household)
        return ([header] + names + ["", L10n.string("Add them to your meals in Meal Shuffler:")]).joined(separator: "\n")
    }
}

// MARK: - Receiving

/// Something another household sent, waiting for this one to look at it.
enum IncomingShare: Identifiable, Equatable {
    case rules(SharedRules)
    case recipes(SharedRecipes)

    var id: String {
        switch self {
        case .rules(let shared): "rules-\(shared.from)-\(shared.rules.count)"
        case .recipes(let shared): "recipes-\(shared.from)-\(shared.recipes.count)"
        }
    }

    /// Nil for a URL that is not a share link; throws for one that is but cannot be read.
    static func parse(_ url: URL) throws -> IncomingShare? {
        guard let link = ShareLinks.parse(url) else { return nil }
        let payload = link.payload
        switch link.kind {
        case .rules:
            let shared = try ShareCodec.decode(SharedRules.self, from: payload)
            guard !shared.rules.isEmpty else { throw ShareCodec.ShareError.unreadable }
            return .rules(shared)
        case .recipes:
            let shared = try ShareCodec.decode(SharedRecipes.self, from: payload)
            guard !shared.recipes.isEmpty else { throw ShareCodec.ShareError.unreadable }
            return .recipes(shared)
        }
    }
}
