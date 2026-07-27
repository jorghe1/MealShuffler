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
    var source: MealSource = .manual
}

enum RecipeImportError: LocalizedError {
    case invalidURL
    case recipeNotFound
    case unreadableImage

    var errorDescription: String? {
        switch self {
        case .invalidURL: L10n.string("The link is not valid.")
        case .recipeNotFound: L10n.string("No structured recipe was found on this page.")
        case .unreadableImage: L10n.string("Could not read text from the image.")
        }
    }
}

struct RecipeImportService {
    func importRecipe(from url: URL) async throws -> ImportedRecipeDraft {
        guard url.scheme?.lowercased() == "https" else { throw RecipeImportError.invalidURL }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        guard let html = String(data: data, encoding: .utf8),
              let recipe = extractRecipeObject(from: html) else {
            throw RecipeImportError.recipeNotFound
        }

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
            source: .web(url)
        )
    }

    private func extractRecipeObject(from html: String) -> [String: Any]? {
        let pattern = #"<script[^>]*type\s*=\s*["']application/ld\+json["'][^>]*>(.*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        for match in regex.matches(in: html, range: range) {
            guard let contentRange = Range(match.range(at: 1), in: html) else { continue }
            let text = String(html[contentRange]).replacingOccurrences(of: "&quot;", with: "\"")
            guard let data = text.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            if let recipe = findRecipe(in: json) { return recipe }
        }
        return nil
    }

    private func findRecipe(in value: Any) -> [String: Any]? {
        if let dictionary = value as? [String: Any] {
            let type = dictionary["@type"]
            let isRecipe = (type as? String) == "Recipe" || (type as? [String])?.contains("Recipe") == true
            if isRecipe { return dictionary }
            for child in dictionary.values {
                if let result = findRecipe(in: child) { return result }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let result = findRecipe(in: child) { return result }
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

struct RecipeOCRService {
    func recognizeRecipe(from data: Data) async throws -> ImportedRecipeDraft {
        guard let image = UIImage(data: data), let cgImage = image.cgImage else {
            throw RecipeImportError.unreadableImage
        }
        let lines: [String] = try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error { continuation.resume(throwing: error); return }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            let norwegianFirst = Bundle.main.preferredLocalizations.first?.hasPrefix("nb") == true
            request.recognitionLanguages = norwegianFirst
                ? ["nb-NO", "nn-NO", "en-US"]
                : ["en-US", "nb-NO", "nn-NO"]
            request.usesLanguageCorrection = true
            DispatchQueue.global(qos: .userInitiated).async {
                do { try VNImageRequestHandler(cgImage: cgImage).perform([request]) }
                catch { continuation.resume(throwing: error) }
            }
        }
        guard let title = lines.first, !title.isEmpty else { throw RecipeImportError.unreadableImage }
        return ImportedRecipeDraft(
            name: title,
            subtitle: L10n.string("Imported from photo – check the text before saving"),
            emoji: "📷",
            ingredientLines: Array(lines.dropFirst()),
            source: .photo
        )
    }
}

enum IngredientParser {
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

    private static func inferAisle(from name: String) -> GroceryAisle {
        let value = name.lowercased()
        if ["kylling", "kjøtt", "laks", "torsk", "fisk", "chicken", "meat", "beef", "pork", "salmon", "cod", "fish"].contains(where: value.contains) { return .meatAndFish }
        if ["melk", "fløte", "ost", "smør", "yoghurt", "egg", "milk", "cream", "cheese", "butter"].contains(where: value.contains) { return .dairy }
        if ["brød", "deig", "lefse", "pita", "bread", "dough", "tortilla"].contains(where: value.contains) { return .bread }
        if ["frossen", "erter", "wokgrønnsaker", "frozen", "peas", "stir-fry vegetables"].contains(where: value.contains) { return .frozen }
        if ["løk", "potet", "tomat", "salat", "agurk", "sitron", "lime", "gulrot", "brokkoli", "spinat", "kål",
            "onion", "potato", "tomato", "lettuce", "cucumber", "lemon", "carrot", "broccoli", "spinach", "cabbage"
        ].contains(where: value.contains) { return .produce }
        return .pantry
    }
}

private extension String {
    var capitalizedSentence: String {
        guard let first else { return self }
        return first.uppercased() + String(dropFirst())
    }
}
