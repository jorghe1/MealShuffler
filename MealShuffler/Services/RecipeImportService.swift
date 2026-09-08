import CoreGraphics
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
    var customTags: Set<String> = []
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

        guard let html = Self.decodeHTML(data, response: http) else {
            throw RecipeImportError.recipeNotFound
        }
        let heroImage = Self.heroImageURL(in: html, pageURL: url)

        if let recipe = Self.extractRecipeObject(from: html) {
            let ingredients = Self.parseIngredients(recipe["recipeIngredient"] ?? recipe["ingredients"])
            let instructions = Self.parseInstructions(recipe["recipeInstructions"])
            guard !ingredients.isEmpty || !instructions.isEmpty else {
                // A name on its own is not an import; fall through to the markup below rather
                // than saving a meal with nothing in it.
                return try Self.microdataDraft(html: html, url: url, heroImage: heroImage)
            }
            let name = (recipe["name"] as? String).map(Self.decodingEntities) ?? L10n.string("Imported recipe")
            return Self.draft(
                name: name,
                subtitle: Self.shortSubtitle(recipe["description"] as? String, fallback: url.host),
                prepMinutes: Self.parseDuration(recipe["totalTime"] as? String ?? recipe["prepTime"] as? String),
                servings: Self.parseServings(recipe["recipeYield"]),
                ingredientLines: ingredients,
                instructions: instructions,
                heroImage: heroImage,
                url: url
            )
        }
        return try Self.microdataDraft(html: html, url: url, heroImage: heroImage)
    }

    /// Last resort before giving up: schema.org expressed as attributes on the markup.
    ///
    /// Only JSON-LD was ever read, so a page carrying its recipe as microdata reported "no
    /// structured recipe found" -- or worse, matched a thin JSON-LD blob that held the name
    /// and nothing else, which is how an import arrives with a title and an empty shopping
    /// list.
    static func microdataDraft(html: String, url: URL, heroImage: URL?) throws -> ImportedRecipeDraft {
        let ingredients = microdataValues(in: html, property: "recipeIngredient")
        guard !ingredients.isEmpty else { throw RecipeImportError.recipeNotFound }
        let instructions = microdataValues(in: html, property: "recipeInstructions")
        let name = microdataValues(in: html, property: "name").first
            ?? titleTag(in: html)
            ?? L10n.string("Imported recipe")
        return draft(
            name: name,
            subtitle: shortSubtitle(microdataValues(in: html, property: "description").first, fallback: url.host),
            prepMinutes: parseDuration(microdataValues(in: html, property: "totalTime").first),
            servings: parseServings(microdataValues(in: html, property: "recipeYield").first),
            ingredientLines: ingredients,
            instructions: instructions,
            heroImage: heroImage,
            url: url
        )
    }

    static func draft(
        name: String,
        subtitle: String,
        prepMinutes: Int,
        servings: Int,
        ingredientLines: [String],
        instructions: [String],
        heroImage: URL?,
        url: URL
    ) -> ImportedRecipeDraft {
        let parsed = IngredientParser.parse(lines: ingredientLines)
        // Tagged locally so an imported recipe is visible to rules straight away. Without
        // this, "fish on Tuesday" could never match anything the household brought in.
        let tags = RecipeClassifier.tags(name: name, ingredients: parsed.map(\.name))
        return ImportedRecipeDraft(
            name: name,
            subtitle: subtitle,
            emoji: RecipeClassifier.emoji(for: tags),
            prepMinutes: prepMinutes,
            servings: servings,
            ingredientLines: ingredientLines,
            instructions: instructions,
            tags: tags,
            parsedIngredients: parsed,
            heroImageURL: heroImage,
            source: .web(url)
        )
    }

    /// A one-line subtitle. Descriptions are often a marketing paragraph.
    static func shortSubtitle(_ description: String?, fallback: String?) -> String {
        guard let description else { return fallback ?? L10n.string("From the web") }
        let cleaned = decodingEntities(description)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return fallback ?? L10n.string("From the web") }
        if let sentenceEnd = cleaned.firstIndex(where: { ".!?".contains($0) }) {
            let sentence = String(cleaned[..<sentenceEnd])
            if sentence.count >= 12 { return sentence }
        }
        return cleaned.count > 90 ? String(cleaned.prefix(90)) + "…" : cleaned
    }

    static func titleTag(in html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"<title[^>]*>(.*?)</title>"#,
                                                   options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        let value = decodingEntities(String(html[range])).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// Text carried by elements marked with a schema.org `itemprop`.
    ///
    /// Deliberately shallow: a simple text node or a `content` attribute. Anything richer is
    /// the service's job, not a regex's.
    static func microdataValues(in html: String, property: String) -> [String] {
        let patterns = [
            "<[^>]+itemprop=[\"']\(property)[\"'][^>]*content=[\"']([^\"']+)[\"'][^>]*>",
            "<[^>]+itemprop=[\"']\(property)[\"'][^>]*>([^<]{2,400})<"
        ]
        var found: [String] = []
        var seen = Set<String>()
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
                guard let range = Range(match.range(at: 1), in: html) else { continue }
                let value = decodingEntities(String(html[range]))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty, seen.insert(value).inserted else { continue }
                found.append(value)
            }
        }
        return found
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

    /// The best Recipe node on the page, not merely the first one reached.
    ///
    /// This walked `dictionary.values`, whose order Swift does not define, and returned the
    /// first hit. A page with related-recipe cards therefore imported a *different* recipe on
    /// different runs of the same URL. Collecting every candidate and picking the richest one
    /// is both stable and more often right.
    static func extractRecipeObject(from html: String) -> [String: Any]? {
        let pattern = #"<script[^>]*type\s*=\s*["']application/ld\+json["'][^>]*>(.*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        var candidates: [[String: Any]] = []
        for match in regex.matches(in: html, range: range) {
            guard let contentRange = Range(match.range(at: 1), in: html) else { continue }
            let text = decodingEntities(String(html[contentRange]))
            guard let data = text.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            collectRecipes(in: json, depth: 0, into: &candidates)
        }
        return candidates.max { left, right in
            let leftScore = parseIngredients(left["recipeIngredient"] ?? left["ingredients"]).count
            let rightScore = parseIngredients(right["recipeIngredient"] ?? right["ingredients"]).count
            if leftScore != rightScore { return leftScore < rightScore }
            return parseInstructions(left["recipeInstructions"]).count
                < parseInstructions(right["recipeInstructions"]).count
        }
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
    /// Keys are walked in sorted order so the traversal is reproducible.
    static func collectRecipes(in value: Any, depth: Int, into found: inout [[String: Any]]) {
        guard depth < 24 else { return }
        if let dictionary = value as? [String: Any] {
            let type = dictionary["@type"]
            let isRecipe = (type as? String) == "Recipe" || (type as? [String])?.contains("Recipe") == true
            if isRecipe { found.append(dictionary) }
            for key in dictionary.keys.sorted() {
                collectRecipes(in: dictionary[key] as Any, depth: depth + 1, into: &found)
            }
        } else if let array = value as? [Any] {
            for child in array {
                collectRecipes(in: child, depth: depth + 1, into: &found)
            }
        }
    }

    /// Ingredients in whichever shape the page emitted them.
    ///
    /// Only `[String]` was ever read. A site listing them as objects, or as one newline-joined
    /// string, yielded an empty array -- an import with a title and nothing to shop for.
    static func parseIngredients(_ value: Any?) -> [String] {
        func text(from element: Any) -> String? {
            if let string = element as? String { return string }
            if let dictionary = element as? [String: Any] {
                return (dictionary["name"] as? String) ?? (dictionary["text"] as? String)
            }
            return nil
        }
        let raw: [String]
        if let array = value as? [Any] {
            raw = array.compactMap(text)
        } else if let single = value as? String {
            raw = single.components(separatedBy: .newlines)
        } else {
            raw = []
        }
        return raw
            .map { decodingEntities($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func parseDuration(_ value: String?) -> Int {
        guard let value else { return 30 }
        let hours = captureNumber(in: value, pattern: #"(\d+)H"#) ?? 0
        let minutes = captureNumber(in: value, pattern: #"(\d+)M"#) ?? 0
        return max(hours * 60 + minutes, 5)
    }

    static func captureNumber(in value: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range(at: 1), in: value) else { return nil }
        return Int(value[range])
    }

    static func parseServings(_ value: Any?) -> Int {
        if let number = value as? Int { return max(number, 1) }
        let text = (value as? String) ?? (value as? [String])?.first ?? ""
        return captureNumber(in: text, pattern: #"(\d+)"#) ?? 4
    }

    /// Flattens `HowToStep` and `HowToSection` alike.
    ///
    /// A section carries its steps in `itemListElement` and has no `text` of its own, so
    /// reading `text` off each element returned nothing at all for any page that groups its
    /// method into parts -- which most modern recipe sites do.
    static func parseInstructions(_ value: Any?) -> [String] {
        var steps: [String] = []
        func walk(_ node: Any, depth: Int) {
            guard depth < 8 else { return }
            if let string = node as? String {
                let cleaned = decodingEntities(string).trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty { steps.append(cleaned) }
            } else if let array = node as? [Any] {
                for child in array { walk(child, depth: depth + 1) }
            } else if let dictionary = node as? [String: Any] {
                if let nested = dictionary["itemListElement"] {
                    walk(nested, depth: depth + 1)
                } else if let text = dictionary["text"] as? String {
                    walk(text, depth: depth + 1)
                } else if let name = dictionary["name"] as? String {
                    walk(name, depth: depth + 1)
                }
            }
        }
        walk(value as Any, depth: 0)
        return steps
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
        try Self.draft(from: try await recognisedLines(from: data))
    }

    /// A recipe spread across several scanned pages.
    ///
    /// Each page's lines keep their position within the page, offset by the page number, so
    /// the structurer still reads the whole thing top to bottom in the order it was scanned.
    func recognizeRecipe(fromPages pages: [Data]) async throws -> ImportedRecipeDraft {
        var all: [RecognisedLine] = []
        for (index, page) in pages.enumerated() {
            let lines = try await recognisedLines(from: page)
            all.append(contentsOf: lines.map { $0.onPage(index) })
        }
        return try Self.draft(from: all)
    }

    private func recognisedLines(from data: Data) async throws -> [RecognisedLine] {
        guard let image = UIImage(data: data), let cgImage = image.cgImage else {
            throw RecipeImportError.unreadableImage
        }
        // `perform` invokes each request's completion handler *and* rethrows the first
        // request error. Resuming from both paths would resume the continuation twice,
        // which traps. Read the results after `perform` returns instead, so there is
        // exactly one resume on each path.
        // The languages are read here; the request itself is built on the worker, because a
        // `VNRecognizeTextRequest` is not Sendable and crossing into the closure with one is
        // an error under the Swift 6 language mode.
        let languages = Bundle.main.preferredLocalizations.first?.hasPrefix("nb") == true
            ? ["nb-NO", "nn-NO", "en-US"]
            : ["en-US", "nb-NO", "nn-NO"]

        let recognised: [RecognisedLine] = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = languages
                request.usesLanguageCorrection = true
                do {
                    // `perform` both calls each request's completion handler and rethrows the
                    // first error, so results are read after it returns: exactly one resume.
                    try VNImageRequestHandler(cgImage: cgImage).perform([request])
                    continuation.resume(returning: (request.results ?? []).compactMap(RecognisedLine.init))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        return recognised
    }

    /// One recognised line, with where it sat on the page.
    ///
    /// Vision hands back observations in no guaranteed order, and the structurer reads its
    /// input as a document: the first line is the title and a heading separates ingredients
    /// from method. Without position, a two-column cookbook page interleaves its sidebar with
    /// its method and every one of those assumptions breaks.
    struct RecognisedLine {
        let text: String
        /// Distance from the top of the page, 0 at the top. Vision's origin is bottom-left.
        let top: CGFloat
        let left: CGFloat
        let height: CGFloat

        /// Internal rather than private so a test can lay out a page without Vision.
        init(text: String, top: CGFloat, left: CGFloat, height: CGFloat) {
            self.text = text
            self.top = top
            self.left = left
            self.height = height
        }

        /// The same line, placed after every earlier page.
        func onPage(_ index: Int) -> RecognisedLine {
            RecognisedLine(text: text, top: top + CGFloat(index), left: left, height: height)
        }

        init?(_ observation: VNRecognizedTextObservation) {
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            text = candidate.string
            top = 1 - box.maxY
            left = box.minX
            height = box.height
        }
    }

    static func draft(from recognised: [RecognisedLine]) throws -> ImportedRecipeDraft {
        // Reading order. Lines within roughly the same band count as the same row, so a
        // two-column layout reads left column then right rather than zig-zagging.
        let ordered = recognised.sorted { left, right in
            if abs(left.top - right.top) > 0.012 { return left.top < right.top }
            return left.left < right.left
        }
        let structured = RecipeTextStructurer.structure(lines: ordered.map(\.text))

        // The structurer takes the first line as the title, which on a screenshot is the
        // status bar or the site's navigation. The largest text in the upper half is a much
        // better guess at what the page calls itself.
        let title = headline(in: ordered) ?? structured.title
        guard !title.isEmpty else { throw RecipeImportError.unreadableImage }

        let parsed = IngredientParser.parse(lines: structured.ingredientLines)
        return ImportedRecipeDraft(
            name: title,
            subtitle: L10n.string("Imported from photo – check the text before saving"),
            emoji: RecipeClassifier.emoji(for: RecipeClassifier.tags(name: title, ingredients: parsed.map(\.name))),
            ingredientLines: structured.ingredientLines,
            instructions: structured.instructions,
            tags: RecipeClassifier.tags(name: title, ingredients: parsed.map(\.name)),
            parsedIngredients: parsed,
            needsReview: true,
            source: .photo
        )
    }

    /// The biggest line in the top half that is not page furniture.
    static func headline(in ordered: [RecognisedLine]) -> String? {
        let upper = ordered.filter { $0.top < 0.5 }
        let candidates = (upper.isEmpty ? ordered : upper).filter {
            !RecipeTextStructurer.isNoise($0.text) && $0.text.count >= 3
        }
        guard let tallest = candidates.max(by: { $0.height < $1.height }) else { return nil }
        return tallest.text.trimmingCharacters(in: .whitespacesAndNewlines)
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
