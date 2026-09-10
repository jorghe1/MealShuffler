import Foundation

/// Turns a flat run of recognised text into a recipe's parts.
///
/// A scanned page is not a list of ingredients. Treating every line after the first as one
/// put headings, timings, photo credits, page numbers and whole instruction steps into the
/// user's shopping list -- with step numbers read as quantities.
enum RecipeTextStructurer {
    struct Structured {
        var title: String
        var ingredientLines: [String]
        var instructions: [String]
    }

    /// Turns a pasted block into a reviewable draft.
    ///
    /// Pasting text used to be the one path that genuinely required the service, so with no
    /// service deployed it answered with an error instead of a recipe. The same structurer
    /// that reads a scanned page reads a pasted one; the service, when configured, still gets
    /// first refusal because it reads prose far better than these heuristics.
    static func draft(fromPastedText text: String) throws -> ImportedRecipeDraft {
        let lines = text.components(separatedBy: .newlines)
        let structured = structure(lines: lines)
        guard !structured.title.isEmpty,
              !(structured.ingredientLines.isEmpty && structured.instructions.isEmpty) else {
            throw RecipeImportError.recipeNotFound
        }
        let parsed = IngredientParser.parse(lines: structured.ingredientLines)
        let details = metadata(in: text)
        let tags = RecipeClassifier.tags(name: structured.title, ingredients: parsed.map(\.name))
        return ImportedRecipeDraft(
            name: structured.title,
            subtitle: L10n.string("Pasted in – check the details before saving"),
            emoji: RecipeClassifier.emoji(for: tags),
            prepMinutes: details.minutes ?? 30,
            servings: details.servings ?? 4,
            ingredientLines: structured.ingredientLines,
            instructions: structured.instructions,
            tags: tags,
            parsedIngredients: parsed,
            needsReview: true,
            source: .manual,
            sourceText: text,
            servingsConfirmed: details.servings != nil,
            activeMinutes: details.activeMinutes,
            timingNeedsReview: details.minutes == nil
        )
    }

    static func structure(lines rawLines: [String]) -> Structured {
        let lines = rawLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let title = lines.first else {
            return Structured(title: "", ingredientLines: [], instructions: [])
        }
        let body = Array(lines.dropFirst())

        var ingredientHeader: Int?
        var methodHeader: Int?
        for (index, line) in body.enumerated() {
            if ingredientHeader == nil, matches(line, ingredientHeaderPattern) {
                ingredientHeader = index
            } else if methodHeader == nil, matches(line, methodHeaderPattern) {
                methodHeader = index
            }
        }

        let ingredientBlock: [String]
        let instructionBlock: [String]
        if let start = ingredientHeader {
            let end = (methodHeader.map { $0 > start ? $0 : body.count }) ?? body.count
            ingredientBlock = Array(body[(start + 1)..<end])
            instructionBlock = methodHeader.map { Array(body[($0 + 1)...]) } ?? []
        } else if let start = methodHeader {
            ingredientBlock = Array(body[..<start])
            instructionBlock = Array(body[(start + 1)...])
        } else {
            // No headings on the page: fall back to classifying each line.
            ingredientBlock = body
            instructionBlock = []
        }

        var joined: [String] = []
        for line in ingredientBlock {
            if let previous = joined.last, matches(previous, #"^\s*[\d.,/½¼¾ ]+\s*(?:g|kg|ml|dl|l|ss|ts|tbsp|tsp|cups?|fedd)?\s*$"#),
               !isNoise(line), !isInstruction(line), !matches(line, quantityStartPattern) {
                joined[joined.count - 1] += " " + line
            } else { joined.append(line) }
        }
        let ingredients = joined.filter { !isNoise($0) && (ingredientHeader != nil || isIngredient($0)) }
        var instructions = instructionBlock
            .filter { !isNoise($0) }
            .map(strippingStepNumber)
        if instructions.isEmpty {
            // Unlabelled page: recover steps that fell into the ingredient block.
            instructions = ingredientBlock
                .filter { !isNoise($0) && isInstruction($0) }
                .map(strippingStepNumber)
        }

        return Structured(title: title, ingredientLines: ingredients, instructions: instructions)
    }

    // MARK: - Classification

    struct Metadata {
        var servings: Int?
        var minutes: Int?
        var activeMinutes: Int?
    }

    static func metadata(in text: String) -> Metadata {
        func number(_ pattern: String) -> Int? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text), let n = Int(text[range]), n > 0 else { return nil }
            return n
        }
        // Yield must be a yield statement, never an instruction such as "til 200 grader".
        let servings = number(#"(?m)^\s*(?:serves|servings|porsjoner|serverer|antall porsjoner)\s*:?\s*(\d+)\s*[.!]?\s*$"#)
            ?? number(#"(?m)^\s*(?:til\s+)?(\d+)\s*(?:servings|porsjoner|personer|people)\s*[.!]?\s*$"#)
        func duration(labels: String) -> Int? {
            let prefix = "(?m)^\\s*(?:" + labels + ")\\s*:?\\s*"
            let hours = number(prefix + #"(\d+)\s*(?:hours?|timer?|t)\b"#)
            let minutes = number(prefix + #"(?:\d+\s*(?:hours?|timer?|t)\s*(?:og|and)?\s*)?(\d+)\s*(?:minutes?|minutt(?:er)?|min|m)\b"#)
            guard hours != nil || minutes != nil else { return nil }
            return (hours ?? 0) * 60 + (minutes ?? 0)
        }
        let total = duration(labels: "total time|total tid|totalt|tidsbruk|tid|time")
        let active = duration(labels: "prep time|preparation time|forberedelsestid|forberedelse|aktiv tid")
        return Metadata(servings: servings, minutes: total, activeMinutes: active)
    }

    /// Page furniture: timings, yields, credits, page numbers, stray headings.
    static func isNoise(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        if matches(trimmed, decorationPattern) { return true }
        if matches(trimmed, noisePattern) { return true }
        if matches(trimmed, #"^(?:(?:prep time|cook time|total time|total tid|totalt|tidsbruk|forberedelsestid|forberedelse|aktiv tid|steketid|koketid|tid|time|porsjoner|servings|serves)\s*:?\s*\d|(?:til\s+)?\d+\s*(?:porsjoner|personer|people|servings)\s*$)"#) { return true }
        if trimmed == trimmed.uppercased(),
           trimmed.rangeOfCharacter(from: .letters) != nil,
           trimmed.split(separator: " ").count <= 3 {
            return true
        }
        return false
    }

    static func isInstruction(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split(separator: " ").count
        if matches(trimmed, stepPrefixPattern), words >= 4 { return true }
        if words >= 9 { return true }
        if trimmed.hasSuffix("."), words >= 6 { return true }
        return false
    }

    static func isIngredient(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split(separator: " ").map(String.init)
        guard !words.isEmpty, !isInstruction(trimmed) else { return false }
        if matches(trimmed, quantityStartPattern) { return true }
        if words.count >= 2,
           IngredientParser.isKnownUnit(words[1].trimmingCharacters(in: CharacterSet(charactersIn: ".,"))) {
            return true
        }
        // Bare pantry items: "salt and pepper", "olive oil".
        return words.count <= 5 && !trimmed.hasSuffix(".")
    }

    private static func strippingStepNumber(_ line: String) -> String {
        replacing(line, pattern: stepPrefixPattern, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Patterns

    private static let ingredientHeaderPattern =
        #"^\s*(ingredients?|ingredienser|du trenger|you (will )?need)\s*:?\s*$"#
    private static let methodHeaderPattern =
        #"^\s*(method|instructions?|directions?|preparation|steps?|fremgangsm\w*|framgangsm\w*|slik gj\w+r du|slik lager du)\s*:?\s*$"#
    private static let noisePattern =
        #"^\s*(serves\b|serverer\b|porsjoner\b|antall\b|prep\b|cook(ing)?\s+time\b|total\s+time\b|tid\b|forberedelse\b|photo(graphy)?\b|foto\b|oppskrift\s+av\b|recipe\s+by\b|text\s+by\b|tips?\b)"#
    /// Nothing but digits, punctuation and bullets: page numbers and rules.
    private static let decorationPattern = #"^[\s\d\-\x{2013}\x{2014}\x{2022}\x{00B7}|]+$"#
    private static let stepPrefixPattern = #"^\s*\d+\s*[.)]\s+"#
    private static let quantityStartPattern = #"^\s*(\d+([.,]\d+)?|[\x{00BD}\x{00BC}\x{00BE}\x{2153}\x{2154}]|\d+/\d+)\b"#

    private static func matches(_ value: String, _ pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(value.startIndex..., in: value)
        return regex.firstMatch(in: value, range: range) != nil
    }

    private static func replacing(_ value: String, pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return value
        }
        let range = NSRange(value.startIndex..., in: value)
        return regex.stringByReplacingMatches(in: value, range: range, withTemplate: template)
    }
}
