import Foundation
import UIKit
import Vision

struct ImportedRecipeDraft: Hashable {
    var name = ""
    var subtitle = ""
    var emoji = "🍽️"
    var prepMinutes = 30
    var servings = 4
    var ingredientLines: [String] = []
    var instructions: [String] = []
    /// Categories, so an imported recipe is immediately visible to rules. Local imports
    /// leave this empty, which is why "fish on Tuesday" could never match one before.
    var tags: Set<MealTag> = []
    /// Ingredients already parsed with a classified aisle. Used when the user accepts the
    /// import unedited; editing the text falls back to parsing it again.
    var parsedIngredients: [Ingredient]?
    var heroImageURL: URL?
    /// The source was partial or hard to read. Worth the user's eye before saving.
    var needsReview = false
    var source: MealSource = .manual
}

enum RecipeImportError: LocalizedError {
    case invalidURL
    case recipeNotFound
    case unreadableImage
    /// The extraction service explained itself; prefer its wording to a status code.
    case service(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: L10n.string("The link is not valid.")
        case .recipeNotFound: L10n.string("No structured recipe was found on this page.")
        case .unreadableImage: L10n.string("Could not read text from the image.")
        case .service(let message): message
        }
    }
}

/// Turns a source into a reviewable draft.
///
/// The seam a server-side extractor slots into. The local implementations below stay useful
/// as a fast path even once one exists: structured markup is instant and free, and a service
/// outage should degrade import rather than break it.
protocol RecipeExtractor: Sendable {
    func extract(from url: URL) async throws -> ImportedRecipeDraft
    func extract(fromImage data: Data) async throws -> ImportedRecipeDraft
}

/// Tries each extractor in turn, returning the first draft one produces.
struct ChainedRecipeExtractor: RecipeExtractor {
    let extractors: [any RecipeExtractor]

    func extract(from url: URL) async throws -> ImportedRecipeDraft {
        try await first { try await $0.extract(from: url) }
    }

    func extract(fromImage data: Data) async throws -> ImportedRecipeDraft {
        try await first { try await $0.extract(fromImage: data) }
    }

    private func first(
        _ attempt: (any RecipeExtractor) async throws -> ImportedRecipeDraft
    ) async throws -> ImportedRecipeDraft {
        var lastError: Error = RecipeImportError.recipeNotFound
        for extractor in extractors {
            do { return try await attempt(extractor) } catch { lastError = error }
        }
        throw lastError
    }
}

struct RecipeImportService: RecipeExtractor {
    /// Identifies the app to publishers. Several reject the default URLSession agent
    /// outright, which read as "no recipe found" rather than as a refusal.
    private static let userAgent =
        "MealShuffler/1.0 (+https://mealshuffler.no) URLSession"

    func extract(from url: URL) async throws -> ImportedRecipeDraft {
        try await importRecipe(from: url)
    }

    func extract(fromImage data: Data) async throws -> ImportedRecipeDraft {
        try await RecipeOCRService().recognizeRecipe(from: data)
    }

    func importRecipe(from url: URL) async throws -> ImportedRecipeDraft {
        guard url.scheme?.lowercased() == "https" else { throw RecipeImportError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        if let http, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        // A response larger than this is not a recipe page worth parsing.
        guard data.count <= 5_000_000 else { throw RecipeImportError.recipeNotFound }

        guard let html = Self.decodeHTML(data, response: http),
              let recipe = extractRecipeObject(from: html) else {
            throw RecipeImportError.recipeNotFound
        }
        let heroImage = Self.heroImageURL(in: html, pageURL: url)

        let ingredients = recipe["recipeIngredient"] as? [String] ?? []
        let instructions = parseInstructions(recipe["recipeInstructions"])
        return ImportedRecipeDraft(
            name: recipe["name"] as? String ?? L10n.string("Imported recipe"),
            subtitle: recipe["description"] as? String ?? url.host ?? L10n.string("From the web"),
            emoji: "🍽️",
            prepMinutes: parseDuration(recipe["totalTime"] as? String ?? recipe["prepTime"] as? String),
            servings: parseServings(recipe["recipeYield"]),
            ingredientLines: ingredients,
            instructions: instructions,
            heroImageURL: heroImage,
            source: .web(url)
        )
    }

    /// The page's own hero image. Real photography for no picker, no upload and no storage.
    static func heroImageURL(in html: String, pageURL: URL) -> URL? {
        let patterns = [
            #"<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']"#,
            #"<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:image["']"#,
            #"<meta[^>]+name=["']twitter:image["'][^>]+content=["']([^"']+)["']"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let range = Range(match.range(at: 1), in: html) else { continue }
            let candidate = String(html[range])
            if let resolved = URL(string: candidate, relativeTo: pageURL)?.absoluteURL,
               resolved.scheme?.lowercased() == "https" {
                return resolved
            }
        }
        return nil
    }

    /// Decodes a page that may not be UTF-8.
    ///
    /// Norwegian food sites still serve ISO-8859-1 and Windows-1252, where a plain UTF-8
    /// decode returns nil and the import reports "no recipe found" for a page that has one.
    static func decodeHTML(_ data: Data, response: HTTPURLResponse?) -> String? {
        if let text = String(data: data, encoding: .utf8) { return text }

        if let charset = response?.textEncodingName {
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
            if cfEncoding != kCFStringEncodingInvalidId {
                let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
                if let text = String(data: data, encoding: encoding) { return text }
            }
        }

        for encoding in [String.Encoding.isoLatin1, .windowsCP1252, .utf16, .macOSRoman] {
            if let text = String(data: data, encoding: encoding) { return text }
        }
        return nil
    }

    private func extractRecipeObject(from html: String) -> [String: Any]? {
        let pattern = #"<script[^>]*type\s*=\s*["']application/ld\+json["'][^>]*>(.*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        for match in regex.matches(in: html, range: range) {
            guard let contentRange = Range(match.range(at: 1), in: html) else { continue }
            let text = Self.decodingEntities(String(html[contentRange]))
            guard let data = text.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            if let recipe = findRecipe(in: json, depth: 0) { return recipe }
        }
        return nil
    }

    private static let entities: [String: String] = [
        "&quot;": "\"", "&#34;": "\"", "&apos;": "'", "&#39;": "'",
        "&amp;": "&", "&#38;": "&", "&lt;": "<", "&gt;": ">",
        "&nbsp;": " ", "&#160;": " "
    ]

    static func decodingEntities(_ value: String) -> String {
        // &amp; is applied last so "&amp;quot;" does not become a quote.
        var result = value
        for (entity, replacement) in entities where entity != "&amp;" && entity != "&#38;" {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        return result.replacingOccurrences(of: "&#38;", with: "&")
    }

    /// Depth-limited: a hostile or merely odd document should not exhaust the stack.
    private func findRecipe(in value: Any, depth: Int) -> [String: Any]? {
        guard depth < 24 else { return nil }
        if let dictionary = value as? [String: Any] {
            let type = dictionary["@type"]
            let isRecipe = (type as? String) == "Recipe" || (type as? [String])?.contains("Recipe") == true
            if isRecipe { return dictionary }
            for child in dictionary.values {
                if let result = findRecipe(in: child, depth: depth + 1) { return result }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let result = findRecipe(in: child, depth: depth + 1) { return result }
            }
        }
        return nil
    }

    private func parseDuration(_ value: String?) -> Int {
        guard let value else { return 30 }
        let hours = captureNumber(in: value, pattern: #"(\d+)H"#) ?? 0
        let minutes = captureNumber(in: value, pattern: #"(\d+)M"#) ?? 0
        return max(hours * 60 + minutes, 5)
    }

    private func captureNumber(in value: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range(at: 1), in: value) else { return nil }
        return Int(value[range])
    }

    private func parseServings(_ value: Any?) -> Int {
        if let number = value as? Int { return max(number, 1) }
        let text = (value as? String) ?? (value as? [String])?.first ?? ""
        return captureNumber(in: text, pattern: #"(\d+)"#) ?? 4
    }

    private func parseInstructions(_ value: Any?) -> [String] {
        if let strings = value as? [String] { return strings }
        if let text = value as? String { return [text] }
        guard let items = value as? [[String: Any]] else { return [] }
        return items.compactMap { $0["text"] as? String }
    }
}

struct RecipeOCRService: RecipeExtractor {
    func extract(from url: URL) async throws -> ImportedRecipeDraft {
        throw RecipeImportError.invalidURL
    }

    func extract(fromImage data: Data) async throws -> ImportedRecipeDraft {
        try await recognizeRecipe(from: data)
    }

    func recognizeRecipe(from data: Data) async throws -> ImportedRecipeDraft {
        guard let image = UIImage(data: data), let cgImage = image.cgImage else {
            throw RecipeImportError.unreadableImage
        }
        // `perform` invokes each request's completion handler *and* rethrows the first
        // request error. Resuming from both paths would resume the continuation twice,
        // which traps. Read the results after `perform` returns instead, so there is
        // exactly one resume on each path.
        let lines: [String] = try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            let norwegianFirst = Bundle.main.preferredLocalizations.first?.hasPrefix("nb") == true
            request.recognitionLanguages = norwegianFirst
                ? ["nb-NO", "nn-NO", "en-US"]
                : ["en-US", "nb-NO", "nn-NO"]
            request.usesLanguageCorrection = true
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try VNImageRequestHandler(cgImage: cgImage).perform([request])
                    let observations = request.results as? [VNRecognizedTextObservation] ?? []
                    continuation.resume(returning: observations.compactMap { $0.topCandidates(1).first?.string })
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        let structured = RecipeTextStructurer.structure(lines: lines)
        guard !structured.title.isEmpty else { throw RecipeImportError.unreadableImage }
        return ImportedRecipeDraft(
            name: structured.title,
            subtitle: L10n.string("Imported from photo – check the text before saving"),
            emoji: "📷",
            ingredientLines: structured.ingredientLines,
            instructions: structured.instructions,
            needsReview: true,
            source: .photo
        )
    }
}

enum IngredientParser {
    static func isKnownUnit(_ token: String) -> Bool {
        knownUnits.contains(token.lowercased())
    }

    private static let knownUnits = Set([
        "g", "kg", "ml", "dl", "cl", "l", "liter", "litre",
        "ss", "tbsp", "tablespoon", "tablespoons",
        "ts", "tsp", "teaspoon", "teaspoons",
        "stk", "pc", "pcs", "piece", "pieces",
        "boks", "can", "cans", "tin", "tins",
        "pose", "bag", "bags", "beger", "tub", "tubs",
        "glass", "jar", "jars", "potte", "pot", "pots",
        "flaske", "bottle", "bottles"
    ])

    static func parse(lines: [String]) -> [Ingredient] {
        lines.compactMap(parse)
    }

    static func parse(_ rawLine: String) -> Ingredient? {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }
        let tokens = line.split(separator: " ").map(String.init)
        var index = 0
        var quantity = 1.0
        if let first = tokens.first, let parsed = parseNumber(first) {
            quantity = parsed
            index += 1
        }
        var unit = ""
        if tokens.indices.contains(index), knownUnits.contains(tokens[index].lowercased()) {
            unit = tokens[index].lowercased()
            index += 1
        }
        let name = tokens.dropFirst(index).joined(separator: " ")
        guard !name.isEmpty else { return nil }
        return Ingredient(name: name.capitalizedSentence, quantity: quantity, unit: unit, aisle: inferAisle(from: name))
    }

    private static func parseNumber(_ value: String) -> Double? {
        let fractions: [String: Double] = ["½": 0.5, "¼": 0.25, "¾": 0.75]
        if let fraction = fractions[value] { return fraction }
        if value.contains("/") {
            let parts = value.split(separator: "/").compactMap { Double($0) }
            if parts.count == 2, parts[1] != 0 { return parts[0] / parts[1] }
        }
        return Double(value.replacingOccurrences(of: ",", with: "."))
    }

    /// Phrases whose aisle contradicts the word they contain.
    ///
    /// Substring matching alone sent coconut milk and egg noodles to the dairy counter and
    /// butternut squash to the butter. Checked before anything else.
    private static let aisleOverrides: [(phrase: String, aisle: GroceryAisle)] = [
        ("coconut milk", .pantry), ("kokosmelk", .pantry),
        ("almond milk", .pantry), ("oat milk", .pantry), ("havremelk", .pantry),
        ("egg noodles", .pantry), ("eggnudler", .pantry),
        ("butternut", .produce), ("buttermilk", .dairy),
        ("peanut butter", .pantry), ("peanøttsmør", .pantry),
        ("fish sauce", .pantry), ("fiskesaus", .pantry),
        ("chicken stock", .pantry), ("chicken broth", .pantry),
        ("kyllingbuljong", .pantry), ("fiskebuljong", .pantry),
        ("beef stock", .pantry), ("oksebuljong", .pantry),
        ("cream of tartar", .pantry), ("ice cream", .frozen), ("iskrem", .frozen),
        ("bread crumbs", .pantry), ("breadcrumbs", .pantry), ("griljermel", .pantry)
    ]

    private static let aisleKeywords: [(aisle: GroceryAisle, words: [String])] = [
        (.frozen, ["frossen", "frosne", "frozen", "wokgrønnsaker", "erter", "peas"]),
        (.meatAndFish, ["kylling", "kjøtt", "laks", "torsk", "fisk", "kjøttdeig", "bacon", "skinke",
                        "chicken", "meat", "beef", "pork", "salmon", "cod", "fish", "mince", "ham"]),
        (.dairy, ["melk", "fløte", "ost", "smør", "yoghurt", "egg", "rømme", "kesam",
                  "milk", "cream", "cheese", "butter", "yoghurt", "yogurt", "eggs",
                  "parmesan", "mozzarella", "feta", "cheddar"]),
        (.bread, ["brød", "deig", "lefse", "pita", "rundstykker", "bread", "dough", "tortilla",
                  "wrap", "wraps", "bun", "buns", "baguette"]),
        (.produce, ["løk", "potet", "tomat", "salat", "agurk", "sitron", "lime", "gulrot", "brokkoli",
                    "spinat", "kål", "hvitløk", "paprika", "sopp", "eple", "banan",
                    "onion", "potato", "tomato", "lettuce", "cucumber", "lemon", "carrot", "broccoli",
                    "spinach", "cabbage", "garlic", "pepper", "mushroom", "apple", "banana"])
    ]

    private static func inferAisle(from name: String) -> GroceryAisle {
        let value = name.lowercased()
        for override in aisleOverrides where value.contains(override.phrase) {
            return override.aisle
        }
        // Whole-word matching: "butter" must not fire inside "butternut".
        let words = Set(
            value.split(whereSeparator: { !$0.isLetter && $0 != "-" })
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "-")) }
        )
        for entry in aisleKeywords where entry.words.contains(where: words.contains) {
            return entry.aisle
        }
        return .pantry
    }
}

private extension String {
    var capitalizedSentence: String {
        guard let first else { return self }
        return first.uppercased() + String(dropFirst())
    }
}
