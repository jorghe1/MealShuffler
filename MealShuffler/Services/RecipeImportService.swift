import CoreGraphics
import Foundation
import UIKit
import Vision

struct ImportedRecipeDraft: Hashable, Codable, Identifiable {
    var id = UUID()
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
    var sourceText: String?
    var sourceImages: [Data] = []
    var sourceImageNames: [String]?
    var servingsConfirmed = false
    var activeMinutes: Int?
    var captureID: UUID?
    var updatingMealID: UUID?
    var extractionNote: String?
    var timingNeedsReview: Bool?
    var parentRecipeID: UUID?

    var hasUsableIngredients: Bool { !(parsedIngredients ?? IngredientParser.parse(lines: ingredientLines)).isEmpty }
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
        var partial: ImportedRecipeDraft?
        for extractor in extractors {
            try Task.checkCancellation()
            do {
                let draft = try await attempt(extractor)
                if draft.hasUsableIngredients && draft.servingsConfirmed { return draft }
                if partial == nil { partial = draft }
            } catch is CancellationError { throw CancellationError() }
            catch { lastError = error }
        }
        if var partial { partial.needsReview = true; return partial }
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

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let http = response as? HTTPURLResponse
        if let http, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        // A response larger than this is not a recipe page worth parsing.
        var data = Data()
        for try await byte in bytes {
            if data.count >= 5_000_000 { throw RecipeImportError.recipeNotFound }
            data.append(byte)
        }

        guard let html = Self.decodeHTML(data, response: http) else {
            throw RecipeImportError.recipeNotFound
        }
        let heroImage = Self.heroImageURL(in: html, pageURL: url)

        if let recipe = Self.extractRecipeObject(from: html, pageURL: url) {
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
                prepMinutes: Self.parseDuration(recipe["totalTime"] as? String),
                activeMinutes: Self.parseDuration(recipe["prepTime"] as? String),
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
        guard let html = recipeScope(in: html) else { throw RecipeImportError.recipeNotFound }
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
            activeMinutes: parseDuration(microdataValues(in: html, property: "prepTime").first),
            servings: parseServings(microdataValues(in: html, property: "recipeYield").first),
            ingredientLines: ingredients,
            instructions: instructions,
            heroImage: heroImage,
            url: url
        )
    }

    static func recipeScope(in html: String) -> String? {
        guard let tags = try? NSRegularExpression(pattern: #"</?([a-z][a-z0-9]*)\b[^>]*>"#, options: [.caseInsensitive]),
              let type = try? NSRegularExpression(pattern: #"itemtype\s*=\s*["'][^"']*schema\.org/Recipe["']"#, options: [.caseInsensitive]) else { return nil }
        var start: String.Index?; var rootTag = ""; var depth = 0
        for token in tags.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let range = Range(token.range, in: html), let nameRange = Range(token.range(at: 1), in: html) else { continue }
            let tag = String(html[range]); let name = html[nameRange].lowercased()
            if start == nil, type.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) != nil {
                start = range.lowerBound; rootTag = name; depth = 1; continue
            }
            guard let beginning = start, name == rootTag else { continue }
            if tag.hasPrefix("</") { depth -= 1 } else if !tag.hasSuffix("/>") { depth += 1 }
            if depth == 0 { return String(html[beginning..<range.upperBound]) }
        }
        return nil
    }

    static func draft(
        name: String,
        subtitle: String,
        prepMinutes: Int,
        activeMinutes: Int = 0,
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
            prepMinutes: prepMinutes > 0 ? prepMinutes : 30,
            servings: servings > 0 ? servings : 4,
            ingredientLines: ingredientLines,
            instructions: instructions,
            tags: tags,
            parsedIngredients: parsed,
            heroImageURL: heroImage,
            needsReview: true,
            source: .web(url),
            sourceText: ingredientLines.joined(separator: "\n") + "\n\n" + instructions.joined(separator: "\n"),
            servingsConfirmed: servings > 0,
            activeMinutes: activeMinutes > 0 ? activeMinutes : nil,
            timingNeedsReview: prepMinutes <= 0
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
    static func extractRecipeObject(from html: String, pageURL: URL? = nil) -> [String: Any]? {
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
        func identityScore(_ candidate: [String: Any]) -> Int {
            guard let pageURL else { return 0 }
            let identities = [candidate["url"] as? String, candidate["@id"] as? String,
                candidate["mainEntityOfPage"] as? String, (candidate["mainEntityOfPage"] as? [String: Any])?["@id"] as? String].compactMap { $0 }
            return identities.contains { value in
                URL(string: value, relativeTo: pageURL).map { RecipeURLIdentity.normalized($0.absoluteURL) == RecipeURLIdentity.normalized(pageURL) } ?? false
            } ? 1000 : 0
        }
        return candidates.max { left, right in
            if identityScore(left) != identityScore(right) { return identityScore(left) < identityScore(right) }
            let leftScore = parseIngredients(left["recipeIngredient"] ?? left["ingredients"]).count
            let rightScore = parseIngredients(right["recipeIngredient"] ?? right["ingredients"]).count
            if leftScore != rightScore { return leftScore < rightScore }
            return parseInstructions(left["recipeInstructions"]).count < parseInstructions(right["recipeInstructions"]).count
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
        guard let value else { return 0 }
        let hours = captureNumber(in: value, pattern: #"(\d+)H"#) ?? 0
        let minutes = captureNumber(in: value, pattern: #"(\d+)M"#) ?? 0
        return hours * 60 + minutes
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
        return captureNumber(in: text, pattern: #"(\d+)"#) ?? 0
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
                    try VNImageRequestHandler(cgImage: cgImage, orientation: RecipeImagePreparation.orientation(image.imageOrientation)).perform([request])
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
        let pages = Dictionary(grouping: recognised) { Int($0.top) }
        let ordered = pages.keys.sorted().flatMap { page -> [RecognisedLine] in
            let lines = pages[page] ?? []
            let left = lines.filter { $0.left < 0.38 }
            let right = lines.filter { $0.left > 0.48 }
            let columns = left.count >= 4 && right.count >= 4 && right.contains { r in left.contains { abs($0.top - r.top) < 0.035 } }
            if columns, let columnTop = right.map(\.top).min() {
                let heading = lines.filter { $0.top + $0.height < columnTop }.sorted { $0.top < $1.top }
                let body = lines.filter { $0.top + $0.height >= columnTop }
                return heading + body.filter { $0.left < 0.48 }.sorted { $0.top < $1.top }
                    + body.filter { $0.left >= 0.48 }.sorted { $0.top < $1.top }
            }
            return lines.sorted { l, r in
                let a = Int((l.top / 0.012).rounded()); let b = Int((r.top / 0.012).rounded())
                return a == b ? l.left < r.left : a < b
            }
        }
        let structured = RecipeTextStructurer.structure(lines: ordered.map(\.text))

        // The structurer takes the first line as the title, which on a screenshot is the
        // status bar or the site's navigation. The largest text in the upper half is a much
        // better guess at what the page calls itself.
        let title = headline(in: ordered) ?? structured.title
        guard !title.isEmpty else { throw RecipeImportError.unreadableImage }

        let parsed = IngredientParser.parse(lines: structured.ingredientLines)
        let sourceText = ordered.map(\.text).joined(separator: "\n")
        let metadata = RecipeTextStructurer.metadata(in: sourceText)
        return ImportedRecipeDraft(
            name: title,
            subtitle: L10n.string("Imported from photo – check the text before saving"),
            emoji: RecipeClassifier.emoji(for: RecipeClassifier.tags(name: title, ingredients: parsed.map(\.name))),
            prepMinutes: metadata.minutes ?? 30,
            servings: metadata.servings ?? 4,
            ingredientLines: structured.ingredientLines,
            instructions: structured.instructions,
            tags: RecipeClassifier.tags(name: title, ingredients: parsed.map(\.name)),
            parsedIngredients: parsed,
            needsReview: true,
            source: .photo,
            sourceText: sourceText,
            servingsConfirmed: metadata.servings != nil,
            activeMinutes: metadata.activeMinutes,
            timingNeedsReview: metadata.minutes == nil
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
    static func reconcile(lines: [String], originalLines: [String], ingredients: [Ingredient]) -> [Ingredient] {
        var usedIDs = Set<String>()
        var available = ingredients.enumerated().map { index, ingredient in
            (ingredient.originalText ?? (originalLines.indices.contains(index) ? originalLines[index] : ingredient.editableLine), ingredient)
        }
        return parse(lines: lines).map { parsed in
            guard let index = available.firstIndex(where: { $0.0 == parsed.originalText }) else { return parsed }
            var retained = available.remove(at: index).1
            if !usedIDs.insert(retained.id).inserted { retained.lineID = parsed.id }
            return retained
        }
    }

    static func isKnownUnit(_ token: String) -> Bool {
        knownUnits.contains(token.lowercased())
    }

    private static let knownUnits = Set([
        "g", "kg", "ml", "dl", "cl", "l", "liter", "litre",
        "ss", "tbsp", "tablespoon", "tablespoons",
        "ts", "tsp", "teaspoon", "teaspoons",
        "stk", "pc", "pcs", "piece", "pieces",
        "boks", "bokser", "can", "cans", "tin", "tins",
        "pose", "bag", "bags", "beger", "tub", "tubs",
        "glass", "jar", "jars", "potte", "pot", "pots",
        "flaske", "flasker", "poser", "pakke", "pakker", "bottle", "bottles"
        , "cup", "cups", "oz", "ounce", "ounces", "lb", "lbs", "pound", "pounds",
        "clove", "cloves", "fedd", "pinch", "klype", "handful", "håndfull"
    ])

    static func parse(lines: [String]) -> [Ingredient] {
        var section: String?
        return lines.enumerated().compactMap { index, line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasSuffix(":"), trimmed.rangeOfCharacter(from: .decimalDigits) == nil {
                section = String(trimmed.dropLast()); return nil
            }
            guard var ingredient = parse(line) else { return nil }
            ingredient.lineID = "line-\(index)-\(line)"
            ingredient.section = section
            return ingredient
        }
    }

    static func parse(_ rawLine: String) -> Ingredient? {
        var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^[•*\-]\s*"#, with: "", options: .regularExpression)
        guard !line.isEmpty else { return nil }
        // Normalize container-first notation before reading amounts; retain the untouched source.
        line = line.replacingOccurrences(of: #"^(\d+)\s+(boks(?:er)?|cans?|tins?|pakker?|poser?)\s*(?:à|a|of|[x×])\s*(\d+(?:[.,]\d+)?)\s*(g|kg|ml|dl|l)\b"#,
            with: "$1 × $3 $4 $2", options: [.regularExpression, .caseInsensitive])
        let numberPattern = #"(?:\d+\s+\d+/\d+|\d+\s*[½¼¾⅓⅔⅛⅜⅝⅞]|\d+/\d+|\d+(?:[.,]\d+)?|[½¼¾⅓⅔⅛⅜⅝⅞])"#
        var quantity = 0.0
        var upper: Double?
        func consumeNumber() -> Double? {
            guard let range = line.range(of: "^" + numberPattern, options: .regularExpression),
                  let value = parseNumber(String(line[range])), value > 0, value.isFinite else { return nil }
            line = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            return value
        }
        if let amount = consumeNumber() { quantity = amount }
        line = line.replacingOccurrences(of: #"^\(\s*(\d+(?:[.,]\d+)?)\s*(g|kg|ml|l)\s*\)"#,
                                        with: "× $1 $2", options: .regularExpression)
        if quantity > 0, let separator = line.first, "-–—".contains(separator) {
            line.removeFirst()
            line = line.trimmingCharacters(in: .whitespaces)
            upper = consumeNumber()
        }
        var packageQuantity: Double?
        var packageUnit: String?
        if quantity > 0, let first = line.first, "x×".contains(first) {
            line.removeFirst(); line = line.trimmingCharacters(in: .whitespaces)
            packageQuantity = consumeNumber()
            if let token = line.split(separator: " ").first, isKnownUnit(String(token)) {
                packageUnit = String(token)
                line = String(line.dropFirst(token.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        if let upper, upper < quantity { return Ingredient(name: rawLine.capitalizedSentence, quantity: 0, unit: "", aisle: inferAisle(from: rawLine), originalText: rawLine, amountNote: L10n.string("Check amount range"), requiresReview: true) }
        if (packageQuantity == nil) != (packageUnit == nil) { return Ingredient(name: rawLine.capitalizedSentence, quantity: 0, unit: "", aisle: inferAisle(from: rawLine), originalText: rawLine, amountNote: L10n.string("Check package size"), requiresReview: true) }
        var tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
        var unit = ""
        if let first = tokens.first, isKnownUnit(first.trimmingCharacters(in: .punctuationCharacters)) {
            unit = first.trimmingCharacters(in: .punctuationCharacters).lowercased()
            tokens.removeFirst()
        }
        let name = tokens.joined(separator: " ").replacingOccurrences(of: #"[, ]*\b(to taste|as needed|etter smak|etter behov)\b[. ]*$"#, with: "", options: [.regularExpression, .caseInsensitive])
        guard !name.isEmpty else { return nil }
        let isToTaste = rawLine.range(of: #"\b(to taste|as needed|etter smak|etter behov|smak til)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
        return Ingredient(name: name.capitalizedSentence, quantity: quantity, unit: unit, aisle: inferAisle(from: name),
                          originalText: rawLine, upperQuantity: upper, amountNote: isToTaste ? (rawLine.range(of: #"to taste|etter smak|smak til"#, options: [.regularExpression, .caseInsensitive]) != nil ? L10n.string("To taste") : L10n.string("As needed")) : nil,
                          packageQuantity: packageQuantity, packageUnit: packageUnit)
    }

    private static func parseNumber(_ value: String) -> Double? {
        let fractions: [String: Double] = ["½": 0.5, "¼": 0.25, "¾": 0.75, "⅓": 1.0/3, "⅔": 2.0/3,
                                           "⅛": 0.125, "⅜": 0.375, "⅝": 0.625, "⅞": 0.875]
        if let fraction = fractions[value] { return fraction }
        if let last = value.last, let fraction = fractions[String(last)],
           let whole = Double(value.dropLast().trimmingCharacters(in: .whitespaces)) { return whole + fraction }
        let mixed = value.split(whereSeparator: \.isWhitespace)
        if mixed.count == 2, let whole = Double(mixed[0]), let fraction = parseNumber(String(mixed[1])) {
            return whole + fraction
        }
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
