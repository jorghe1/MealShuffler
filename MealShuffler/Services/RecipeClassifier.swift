import Foundation

/// Guesses a recipe's categories from its own words.
///
/// Imported recipes used to arrive with no tags at all, which made them invisible to every
/// rule the household had written: a salmon dish brought in from a link could never satisfy
/// "fish on Tuesday", and no amount of shuffling would put it there. The service tags what it
/// extracts; this does the same for the on-device path so the two agree.
///
/// Deliberately conservative. A wrong tag silently changes which day a meal can land on, so
/// each keyword here is one a cook would accept without argument, and the editor shows the
/// result before anything is saved.
enum RecipeClassifier {
    private static let keywords: [(tag: MealTag, words: [String])] = [
        (.fish, ["laks", "torsk", "sei", "fisk", "reker", "tunfisk", "makrell", "scampi",
                 "salmon", "cod", "haddock", "fish", "prawn", "shrimp", "tuna", "mackerel"]),
        (.chicken, ["kylling", "kalkun", "chicken", "turkey"]),
        (.meat, ["kjøttdeig", "biff", "svin", "lam", "bacon", "pølse", "skinke", "kjøtt",
                 "beef", "pork", "lamb", "mince", "sausage", "ham", "steak", "meatball"]),
        (.pizza, ["pizza"]),
        (.pasta, ["pasta", "spaghetti", "lasagne", "tagliatelle", "penne", "makaroni",
                  "fettuccine", "linguine", "noodle"]),
        (.soup, ["suppe", "soup", "broth", "gryte", "stew"]),
        (.taco, ["taco", "tacos", "tortilla", "fajita", "burrito", "quesadilla", "enchilada"])
    ]

    /// Ingredients that make a dish not vegetarian, checked before the tag is offered.
    private static let animalWords: Set<MealTag> = [.fish, .chicken, .meat]

    static func tags(name: String, ingredients: [String], prepMinutes: Int? = nil) -> Set<MealTag> {
        let haystack = ([name] + ingredients)
            .map { $0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) }
            .joined(separator: " ")

        var found: Set<MealTag> = []
        for entry in keywords where entry.words.contains(where: { haystack.contains(fold($0)) }) {
            found.insert(entry.tag)
        }

        // Vegetarian is the absence of something rather than the presence of a word, so it is
        // only claimed when nothing animal was recognised at all.
        if found.isDisjoint(with: animalWords), !found.isEmpty || !ingredients.isEmpty {
            if !haystack.contains(fold("egg")) || found.isEmpty {
                found.insert(.vegetarian)
            }
        }

        if let prepMinutes, prepMinutes <= 25 { found.insert(.quick) }
        if found.contains(.pizza) { found.insert(.weekend) }
        return found
    }

    /// A face for the meal. Emoji-only cards are the app's clearest prototype tell, and an
    /// imported recipe that arrives as 🍽️ looks like the app failed at it.
    static func emoji(for tags: Set<MealTag>) -> String {
        if tags.contains(.pizza) { return "🍕" }
        if tags.contains(.taco) { return "🌮" }
        if tags.contains(.soup) { return "🥣" }
        if tags.contains(.fish) { return "🐟" }
        if tags.contains(.pasta) { return "🍝" }
        if tags.contains(.chicken) { return "🍗" }
        if tags.contains(.meat) { return "🍖" }
        if tags.contains(.vegetarian) { return "🥗" }
        return "🍽️"
    }

    private static func fold(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}
