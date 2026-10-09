import Foundation

/// Text folded for comparison: lowercase, no accents, and the Nordic letters spelled out.
///
/// Diacritic folding leaves æ, ø and å alone because they are letters of their own rather than
/// accented vowels, so "gulrotter" typed into a rule would miss "Gulrøtter" on the shelf. The
/// rule parser, the matcher and the vocabulary all fold the same way, so a word read from a
/// sentence and a word read from an ingredient list meet in the same spelling.
enum TextFolding {
    private static let letters: [(String, String)] = [
        ("æ", "ae"), ("ø", "o"), ("å", "a"), ("ö", "o"), ("ä", "a")
    ]

    static func fold(_ value: String) -> String {
        var folded = value.lowercased()
        for (letter, ascii) in letters {
            folded = folded.replacingOccurrences(of: letter, with: ascii)
        }
        return folded
            .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The words of a folded name, split on anything that is not a letter or a digit.
    static func words(_ folded: String) -> [String] {
        folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }
}

/// Foods a household names in a rule, and what each one should catch on the shelf.
///
/// An ingredient rule used to be a bare substring. "Ingen svinekjøtt" then protected nothing,
/// because no recipe lists "svinekjøtt" -- they list bacon, skinke and pølser -- and "laks" was
/// read as an unknown word and trimmed to "lak". Each entry here names the forms a household
/// types (inflections included), the words that find it in an ingredient list or a dish name,
/// and the category it belongs to, so a rule about salmon can also be offered as a rule about
/// fish.
///
/// Matching never verifies allergens: a recipe can hide what its ingredient list does not name.
enum IngredientVocabulary {
    struct Entry: Hashable {
        /// The word stored in the rule and shown back in its sentence.
        let canonical: String
        /// The same, for a household that typed it in English.
        let english: String
        /// Folded forms that name this food in a sentence.
        let forms: Set<String>
        /// Folded words that find it among ingredients and dish names.
        let needles: [String]
        /// The category this food belongs to, offered as the broader reading.
        let category: MealTag?
    }

    static let entries: [Entry] = [
        // Fish and seafood
        Entry(canonical: "laks", english: "salmon", forms: ["laks", "laksen", "laksefilet", "laksefileter", "salmon", "salmons"],
              needles: ["laks", "salmon"], category: .fish),
        Entry(canonical: "torsk", english: "cod", forms: ["torsk", "torsken", "torskefilet", "skrei", "cod"],
              needles: ["torsk", "skrei", "cod"], category: .fish),
        Entry(canonical: "sei", english: "pollock", forms: ["sei", "seien", "seifilet", "pollock", "saithe", "coalfish"],
              needles: ["sei", "pollock", "saithe", "coalfish"], category: .fish),
        Entry(canonical: "hyse", english: "haddock", forms: ["hyse", "hysa", "haddock"], needles: ["hyse", "haddock"], category: .fish),
        Entry(canonical: "ørret", english: "trout", forms: ["orret", "orreten", "trout"], needles: ["orret", "trout"], category: .fish),
        Entry(canonical: "makrell", english: "mackerel", forms: ["makrell", "makrellen", "mackerel"], needles: ["makrell", "mackerel"], category: .fish),
        Entry(canonical: "tunfisk", english: "tuna", forms: ["tunfisk", "tunfisken", "tuna"], needles: ["tunfisk", "tuna"], category: .fish),
        Entry(canonical: "kveite", english: "halibut", forms: ["kveite", "kveita", "halibut"], needles: ["kveite", "halibut"], category: .fish),
        Entry(canonical: "sild", english: "herring", forms: ["sild", "silda", "herring"], needles: ["sild", "herring"], category: .fish),
        Entry(canonical: "reker", english: "shrimp", forms: ["reke", "reker", "rekene", "shrimp", "shrimps", "prawn", "prawns", "scampi"],
              needles: ["reke", "shrimp", "prawn", "scampi"], category: .fish),
        Entry(canonical: "skalldyr", english: "shellfish", forms: ["skalldyr", "skalldyret", "shellfish"],
              needles: ["reke", "shrimp", "prawn", "scampi", "krabbe", "crab", "hummer", "lobster", "skjell", "mussel",
                        "scallop", "kamskjell", "blaskjell", "osters", "oyster"], category: .fish),
        Entry(canonical: "fiskekaker", english: "fishcakes", forms: ["fiskekake", "fiskekaker", "fiskekakene", "fishcake", "fishcakes"],
              needles: ["fiskekake", "fishcake", "fiskeboll"], category: .fish),
        Entry(canonical: "fiskepinner", english: "fish fingers", forms: ["fiskepinne", "fiskepinner", "fiskepinnene"],
              needles: ["fiskepinne", "fish finger", "fish stick"], category: .fish),

        // Meat and poultry
        Entry(canonical: "kjøttdeig", english: "mince", forms: ["kjottdeig", "kjottdeigen", "mince", "mincemeat"],
              needles: ["kjottdeig", "karbonadedeig", "mince", "minced"], category: .meat),
        Entry(canonical: "svinekjøtt", english: "pork", forms: ["svin", "svinekjott", "svinekjottet", "pork", "flesk"],
              needles: ["svin", "bacon", "skinke", "polse", "ribbe", "flesk", "medister", "pork", "ham", "sausage",
                        "chorizo", "salami", "pancetta", "prosciutto"], category: .meat),
        Entry(canonical: "storfe", english: "beef", forms: ["storfe", "storfekjott", "okse", "oksekjott", "biff", "biffen", "beef", "steak"],
              needles: ["storfe", "okse", "biff", "entrecote", "kjottdeig", "beef", "steak", "minced beef"], category: .meat),
        Entry(canonical: "bacon", english: "bacon", forms: ["bacon", "baconet"], needles: ["bacon"], category: .meat),
        Entry(canonical: "pølser", english: "sausages", forms: ["polse", "polser", "polsene", "sausage", "sausages", "wiener"],
              needles: ["polse", "sausage", "wiener", "chorizo"], category: .meat),
        Entry(canonical: "skinke", english: "ham", forms: ["skinke", "skinka", "skinken", "ham"], needles: ["skinke", "ham"], category: .meat),
        Entry(canonical: "lam", english: "lamb", forms: ["lam", "lammet", "lammekjott", "lamb"], needles: ["lam", "lamb"], category: .meat),
        Entry(canonical: "kalkun", english: "turkey", forms: ["kalkun", "kalkunen", "turkey"], needles: ["kalkun", "turkey"], category: .chicken),

        // Allergens and dislikes
        Entry(canonical: "nøtter", english: "nuts", forms: ["nott", "notter", "nottene", "nut", "nuts", "notteallergi"],
              needles: ["nott", "nut", "mandel", "almond", "cashew", "pistasj", "pistachio", "pecan", "macadamia",
                        "valnott", "walnut", "hasselnott", "hazelnut", "paranott", "peanott", "peanut"], category: nil),
        Entry(canonical: "peanøtter", english: "peanuts", forms: ["peanott", "peanotter", "peanut", "peanuts", "jordnott", "jordnotter"],
              needles: ["peanott", "peanut", "jordnott"], category: nil),
        Entry(canonical: "mandler", english: "almonds", forms: ["mandel", "mandler", "mandlene", "almond", "almonds"],
              needles: ["mandel", "almond"], category: nil),
        Entry(canonical: "sopp", english: "mushrooms", forms: ["sopp", "soppen", "mushroom", "mushrooms", "sjampinjong", "sjampinjonger"],
              needles: ["sopp", "sjampinjong", "kantarell", "portobello", "shiitake", "mushroom"], category: nil),
        Entry(canonical: "løk", english: "onion", forms: ["lok", "loken", "onion", "onions"], needles: ["lok", "onion", "sjalott", "shallot"],
              category: nil),
        Entry(canonical: "hvitløk", english: "garlic", forms: ["hvitlok", "hvitloken", "garlic"], needles: ["hvitlok", "garlic"], category: nil),
        Entry(canonical: "egg", english: "eggs", forms: ["egg", "eggene", "eggs"], needles: ["egg"], category: nil),
        Entry(canonical: "melk", english: "dairy", forms: ["melk", "melka", "laktose", "meieri", "meieriprodukter", "milk", "lactose", "dairy"],
              needles: ["melk", "milk", "flote", "cream", "smor", "butter", "ost", "cheese", "yoghurt", "yogurt", "romme",
                        "sour cream", "creme fraiche", "parmesan", "mozzarella", "kesam", "cottage"], category: nil),
        Entry(canonical: "ost", english: "cheese", forms: ["ost", "osten", "cheese"], needles: ["ost", "cheese", "parmesan", "mozzarella",
                                                                              "cheddar", "feta", "halloumi"], category: nil),
        Entry(canonical: "gluten", english: "gluten", forms: ["gluten", "hvete", "wheat"],
              needles: ["hvete", "wheat", "mel", "flour", "pasta", "spaghetti", "lasagne", "tortilla", "brod", "bread",
                        "nudler", "noodle", "pita", "bun", "couscous", "bulgur", "panko", "pizzadeig", "pizza dough"],
              category: nil),
        Entry(canonical: "chili", english: "chili", forms: ["chili", "chilli", "chilien"], needles: ["chili", "chilli", "jalapeno", "cayenne",
                                                                                   "sriracha"], category: nil),
        Entry(canonical: "koriander", english: "coriander", forms: ["koriander", "korianderen", "coriander", "cilantro"],
              needles: ["koriander", "coriander", "cilantro"], category: nil),
        Entry(canonical: "sesam", english: "sesame", forms: ["sesam", "sesame"], needles: ["sesam", "sesame"], category: nil),
        Entry(canonical: "selleri", english: "celery", forms: ["selleri", "celery"], needles: ["selleri", "celery"], category: nil),
        Entry(canonical: "soya", english: "soy", forms: ["soya", "soy"], needles: ["soya", "soy"], category: nil),
        Entry(canonical: "ris", english: "rice", forms: ["ris", "risen", "rice"], needles: ["ris", "rice"], category: nil),
        Entry(canonical: "poteter", english: "potatoes", forms: ["potet", "poteter", "potetene", "potato", "potatoes"], needles: ["potet", "potato"],
              category: nil),
        Entry(canonical: "tomat", english: "tomatoes", forms: ["tomat", "tomater", "tomatene", "tomato", "tomatoes"], needles: ["tomat", "tomato"],
              category: nil),
        Entry(canonical: "bønner", english: "beans", forms: ["bonne", "bonner", "bonnene", "bean", "beans"], needles: ["bonne", "bean"],
              category: nil),
        Entry(canonical: "linser", english: "lentils", forms: ["linse", "linser", "linsene", "lentil", "lentils"], needles: ["linse", "lentil"],
              category: nil),
        Entry(canonical: "kokos", english: "coconut", forms: ["kokos", "kokosmelk", "coconut"], needles: ["kokos", "coconut"], category: nil)
    ]

    /// Short needles that also find their food at the start of a longer word: "eggnudler",
    /// "risotto", "ostesaus". Others of three letters only match a whole word or the end of a
    /// compound ("rødløk"), because "ham" would otherwise find "hamburger" and "sei" "seitan".
    private static let prefixableShortNeedles: Set<String> = ["egg", "ris", "ost", "lok", "lam", "nut", "cod", "soy"]

    /// Words a needle runs into that are not that food: an aubergine is not an egg, nutmeg is
    /// not a nut, and an oyster ("østers") is not cheese.
    private static let falseFriends: [String: [String]] = [
        "egg": ["eggplant"], "nut": ["nutmeg"], "nott": ["muskatnott"], "ost": ["osters"],
        "lam": ["lampe"]
    ]

    private static let byForm: [String: Entry] = {
        var index: [String: Entry] = [:]
        for entry in entries {
            for form in entry.forms where index[form] == nil { index[form] = entry }
        }
        return index
    }()

    /// The entry a folded word names, if any.
    static func entry(forFolded word: String) -> Entry? { byForm[word] }

    /// The entry a stored rule word belongs to, whatever its spelling.
    static func entry(for typed: String) -> Entry? {
        let folded = TextFolding.fold(typed)
        if let entry = byForm[folded] { return entry }
        return entries.first { TextFolding.fold($0.canonical) == folded || TextFolding.fold($0.english) == folded }
    }

    /// The word to store for a food typed as `folded`: English if it was typed in English, so
    /// "salmon on Monday" reads back as salmon and "laks på torsdag" as laks.
    static func displayWord(for entry: Entry, typedFolded folded: String) -> String {
        let canonical = TextFolding.fold(entry.canonical)
        // A word both languages share ("egg", "bacon") stays as the Norwegian spelling.
        if variants(of: folded).contains(canonical) || variants(of: canonical).contains(folded) { return entry.canonical }
        let english = TextFolding.fold(entry.english)
        let typedInEnglish = variants(of: folded).contains(english) || variants(of: english).contains(folded)
        return typedInEnglish ? entry.english : entry.canonical
    }

    /// The words that find `typed` on the shelf: the vocabulary's own list for a known food,
    /// and otherwise the typed word with its common Norwegian and English endings taken off.
    static func needles(for typed: String) -> [String] {
        if let entry = entry(for: typed) { return entry.needles }
        let folded = TextFolding.fold(typed)
        guard !folded.isEmpty else { return [] }
        return variants(of: folded)
    }

    /// "nøtter" also as "nøtt", "laksen" as "laks", "nuts" as "nut" -- but never "laks" as
    /// "lak" or "hummus" as "hummu": an English plural is only taken off a word that does not
    /// end in -ks, -ss, -us or -is.
    static func variants(of folded: String) -> [String] {
        var result = [folded]
        func add(_ value: String) {
            if value.count >= 3, !result.contains(value) { result.append(value) }
        }
        guard !folded.contains(" ") else { return result }
        for suffix in ["ene", "ane", "er", "en", "et"] where folded.hasSuffix(suffix) && folded.count - suffix.count >= 3 {
            add(String(folded.dropLast(suffix.count)))
        }
        if folded.hasSuffix("oes") {
            add(String(folded.dropLast(2)))
        } else if folded.hasSuffix("ies") {
            add(String(folded.dropLast(3)) + "y")
        } else if folded.hasSuffix("s"), !["ss", "us", "is", "ks"].contains(where: folded.hasSuffix) {
            add(String(folded.dropLast()))
        }
        return result
    }

    /// Whether any of `needles` names something in `text` (an ingredient line or a dish name).
    static func text(_ text: String, containsAnyOf needles: [String]) -> Bool {
        let folded = TextFolding.fold(text)
        guard !folded.isEmpty else { return false }
        let words = TextFolding.words(folded)
        for needle in needles where !needle.isEmpty {
            if needle.contains(" ") {
                if folded.contains(needle) { return true }
                continue
            }
            for word in words where matches(word: word, needle: needle) { return true }
        }
        return false
    }

    private static func matches(word: String, needle: String) -> Bool {
        if let friends = falseFriends[needle], friends.contains(where: { word.hasPrefix($0) || word.hasSuffix($0) }) {
            return false
        }
        if needle.count >= 4 { return word.contains(needle) }
        if word == needle || word.hasSuffix(needle) { return true }
        return prefixableShortNeedles.contains(needle) && word.hasPrefix(needle)
    }
}
