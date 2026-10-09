import SwiftUI

// MARK: - Dish form

/// What a dinner looks like on the table, drawn as one flat picture.
///
/// The bundled category photographs this replaces were realistic and often wrong: every fish
/// dish was the same salmon fillet, chili con carne was meatballs and mash. A simple drawing
/// of the right *kind* of dish reads as the app knowing what it is showing; the household's
/// own photo replaces it once they take one.
enum DishForm: String, CaseIterable {
    case fishFillet, fishCakes, casserole, soup, pasta, lasagne, pizza, taco, wrap, noodles
    case curry, stew, meatballs, burger, sausages, roastChicken, steak, salad, grainBowl
    case rice, omelette, porridge, pancakes, plate
}

extension DishForm {
    static func form(for meal: Meal) -> DishForm {
        form(name: meal.name, tags: meal.tags, ingredientNames: meal.ingredients.map(\.name))
    }

    /// The dish's name decides first, in English or Norwegian, because the name says what is
    /// served ("Fiskegrateng" is a baking dish, whatever its protein). Dish tags come next,
    /// then a few unmistakable ingredients, then the protein tags, and finally a plain plate.
    static func form(name: String, tags: Set<MealTag>, ingredientNames: [String] = []) -> DishForm {
        let title = DishText([name])
        if let rule = nameRules.first(where: { title.has($0.keys) }) { return rule.form }
        if let dish = dishTags.first(where: { tags.contains($0.tag) }) { return dish.form }
        let pantry = DishText(ingredientNames)
        if let rule = ingredientRules.first(where: { pantry.has($0.keys) }) { return rule.form }
        if let protein = proteinTags.first(where: { tags.contains($0.tag) }) { return protein.form }
        return .plate
    }

    /// First match wins, so the more specific dish comes first: soup before noodles
    /// ("Kyllingsuppe med nudler"), pasta salad before pasta, fish cakes before fish.
    /// Keys are folded (lowercase, "ø" → "o"); a leading "=" means a whole word only.
    private static let nameRules: [(form: DishForm, keys: [String])] = [
        (.lasagne, ["lasagn"]),
        (.pizza, ["pizza"]),
        (.porridge, ["grot", "porridge", "oatmeal"]),
        (.pancakes, ["pannekake", "pancake", "crepe", "=lapper", "=sveler", "=svele"]),
        (.soup, ["suppe", "soup", "minestrone", "chowder", "bisque", "gazpacho", "ramen", "=pho",
                 "=laksa", "buljong", "broth", "borsjtsj", "borscht"]),
        (.casserole, ["grateng", "gratin", "deigform", "fiskeform", "ovnsform", "kyllingform", "=pie",
                      "=pai", "quiche", "moussaka", "casserole", "=bake", "fiskepudding"]),
        (.fishCakes, ["fiskekak", "fishcake", "fish cake", "fiskeboll", "fish ball", "fishball",
                      "krabbekak", "crab cake"]),
        (.taco, ["taco"]),
        (.wrap, ["wrap", "fajita", "burrito", "pita", "kebab", "gyro", "quesadilla", "tortilla",
                 "enchilada", "shawarma"]),
        (.burger, ["burger"]),
        (.salad, ["pastasalat", "pasta salad"]),
        (.noodles, ["wok", "stir fry", "stirfry", "nudl", "noodle", "pad thai", "chow mein",
                    "lo mein", "yakisoba", "udon", "=soba"]),
        (.curry, ["curry", "tikka", "korma", "masala", "=dal", "=dhal", "butter chicken", "vindaloo",
                  "sweet and sour", "sursot", "satay"]),
        (.stew, ["chili", "gryte", "stew", "lapskaus", "farikal", "gulasj", "goulash", "cassoulet",
                 "tagine"]),
        (.meatballs, ["kjottboll", "meatball", "kjottkak", "frikadell", "kofta", "polpette",
                      "medisterkak"]),
        (.sausages, ["polse", "sausage", "wiener", "bratwurst", "hot dog", "=hotdog"]),
        (.pasta, ["pasta", "spaghetti", "spagetti", "carbonara", "bolognese", "penne", "tagliatelle",
                  "fettuccine", "linguine", "makaroni", "macaroni", "ravioli", "tortellini", "gnocchi",
                  "pesto", "fusilli", "=orzo", "mac and cheese"]),
        (.fishFillet, ["laks", "salmon", "torsk", "=cod", "=sei", "hyse", "haddock", "orret", "trout",
                       "kveite", "halibut", "makrell", "mackerel", "rodspette", "plaice", "skrei",
                       "klippfisk", "fisk", "fish"]),
        (.roastChicken, ["kyllinglar", "drumstick", "roast chicken", "chicken thigh", "chicken leg",
                         "helstekt kylling", "grillkylling", "kyllingvinge", "chicken wing",
                         "kyllingklubb"]),
        (.steak, ["kotelett", "pork chop", "=chop", "=chops", "steak", "biff", "entrecote", "ribbe",
                  "svinestek", "roast beef", "indrefilet", "ytrefilet", "=stek", "schnitzel",
                  "pinnekjott", "lammelar", "lammeskank"]),
        (.rice, ["stekt ris", "fried rice", "risotto", "=ris", "=rice", "paella", "nasi goreng",
                 "jambalaya", "biryani", "pilaf"]),
        (.omelette, ["omelett", "omelet", "eggerore", "scrambled", "frittata", "shakshuka", "=egg",
                     "=eggs"]),
        (.salad, ["salat", "salad", "coleslaw", "caesar"]),
        (.grainBowl, ["falafel", "bowl", "couscous", "quinoa", "bulgur", "=poke", "buddha",
                      "tabbouleh"])
    ]

    /// Tags that already name a dish form, in the order the old category artwork used.
    private static let dishTags: [(tag: MealTag, form: DishForm)] = [
        (.pizza, .pizza), (.pasta, .pasta), (.soup, .soup), (.taco, .taco)
    ]

    /// Ingredients that give the dish away when the name does not.
    private static let ingredientRules: [(form: DishForm, keys: [String])] = [
        (.lasagne, ["lasagn"]),
        (.pizza, ["pizza"]),
        (.taco, ["taco"]),
        (.burger, ["burger"]),
        (.noodles, ["nudl", "noodle"]),
        (.wrap, ["tortilla", "pita", "wrap"]),
        (.pasta, ["pasta", "spaghetti", "spagetti", "penne", "tagliatelle", "makaroni", "macaroni"]),
        (.fishCakes, ["fiskekak", "fish cake"]),
        (.meatballs, ["kjottboll", "meatball", "kjottkak"]),
        (.sausages, ["polse", "sausage"])
    ]

    private static let proteinTags: [(tag: MealTag, form: DishForm)] = [
        (.fish, .fishFillet), (.chicken, .roastChicken), (.meat, .steak), (.vegetarian, .grainBowl)
    ]
}

/// A name or ingredient list folded into words, matched by stem ("kjottboll") or whole word.
struct DishText {
    private let spaced: String

    init(_ parts: [String]) {
        let words = parts.flatMap { TextFolding.words(TextFolding.fold($0)) }
        spaced = " " + words.joined(separator: " ") + " "
    }

    func has(_ keys: [String]) -> Bool {
        keys.contains { key in
            if key.hasPrefix("=") { return spaced.contains(" \(key.dropFirst()) ") }
            return spaced.contains(key)
        }
    }
}

// MARK: - Colours

/// Fixed food colours. Like a photograph, the drawings keep their colours in dark mode.
enum DishColor {
    static let ink = Color(red: 0.239, green: 0.192, blue: 0.153)
    static let rim = Color(red: 0.886, green: 0.843, blue: 0.749)
    static let rimShade = Color(red: 0.820, green: 0.769, blue: 0.667)
    static let well = Color(red: 0.992, green: 0.980, blue: 0.949)
    static let wood = Color(red: 0.851, green: 0.682, blue: 0.451)
    static let dish = Color(red: 0.420, green: 0.557, blue: 0.682)

    static let salmon = Color(red: 0.957, green: 0.561, blue: 0.431)
    static let whiteFish = Color(red: 0.973, green: 0.941, blue: 0.871)
    static let flake = Color(red: 0.851, green: 0.792, blue: 0.690)
    static let shrimp = Color(red: 0.976, green: 0.588, blue: 0.502)
    static let tuna = Color(red: 0.890, green: 0.749, blue: 0.659)
    static let fishCake = Color(red: 0.886, green: 0.706, blue: 0.471)
    static let chicken = Color(red: 0.906, green: 0.722, blue: 0.502)
    static let roast = Color(red: 0.820, green: 0.522, blue: 0.267)
    static let mince = Color(red: 0.553, green: 0.333, blue: 0.212)
    static let meatball = Color(red: 0.588, green: 0.361, blue: 0.231)
    static let beef = Color(red: 0.478, green: 0.267, blue: 0.180)
    static let lamb = Color(red: 0.541, green: 0.310, blue: 0.231)
    static let pork = Color(red: 0.769, green: 0.529, blue: 0.396)
    static let bacon = Color(red: 0.835, green: 0.416, blue: 0.392)
    static let ham = Color(red: 0.937, green: 0.635, blue: 0.616)
    static let sausage = Color(red: 0.749, green: 0.384, blue: 0.278)
    static let pepperoni = Color(red: 0.765, green: 0.224, blue: 0.180)
    static let patty = Color(red: 0.431, green: 0.259, blue: 0.180)
    static let veggiePatty = Color(red: 0.561, green: 0.502, blue: 0.282)
    static let falafel = Color(red: 0.588, green: 0.447, blue: 0.204)
    static let halloumi = Color(red: 0.949, green: 0.851, blue: 0.604)
    static let tofu = Color(red: 0.973, green: 0.941, blue: 0.839)
    static let chickpea = Color(red: 0.886, green: 0.741, blue: 0.475)
    static let sear = Color(red: 0.420, green: 0.243, blue: 0.153)
    static let browned = Color(red: 0.788, green: 0.506, blue: 0.227)

    static let potato = Color(red: 0.957, green: 0.808, blue: 0.447)
    static let mash = Color(red: 0.984, green: 0.918, blue: 0.698)
    static let rice = Color(red: 0.996, green: 0.988, blue: 0.957)
    static let grain = Color(red: 0.886, green: 0.851, blue: 0.769)
    static let friedRice = Color(red: 0.937, green: 0.839, blue: 0.627)
    static let risotto = Color(red: 0.965, green: 0.918, blue: 0.784)
    static let couscous = Color(red: 0.949, green: 0.851, blue: 0.584)
    static let quinoa = Color(red: 0.902, green: 0.827, blue: 0.678)
    static let pasta = Color(red: 0.976, green: 0.847, blue: 0.506)
    static let pastaLine = Color(red: 0.878, green: 0.690, blue: 0.318)
    static let noodle = Color(red: 0.973, green: 0.835, blue: 0.478)
    static let noodleLine = Color(red: 0.867, green: 0.675, blue: 0.302)
    static let crust = Color(red: 0.902, green: 0.690, blue: 0.416)
    static let shell = Color(red: 0.961, green: 0.776, blue: 0.400)
    static let tortilla = Color(red: 0.945, green: 0.812, blue: 0.557)
    static let bun = Color(red: 0.890, green: 0.604, blue: 0.298)
    static let crouton = Color(red: 0.882, green: 0.639, blue: 0.333)
    static let pancake = Color(red: 0.949, green: 0.765, blue: 0.471)
    static let oat = Color(red: 0.918, green: 0.835, blue: 0.690)
    static let ricePorridge = Color(red: 0.980, green: 0.949, blue: 0.871)
    static let golden = Color(red: 0.937, green: 0.722, blue: 0.337)

    static let tomato = Color(red: 0.875, green: 0.318, blue: 0.231)
    static let tomatoSoup = Color(red: 0.890, green: 0.400, blue: 0.267)
    static let rose = Color(red: 0.925, green: 0.545, blue: 0.420)
    static let creamSauce = Color(red: 0.976, green: 0.906, blue: 0.722)
    static let cream = Color(red: 0.973, green: 0.929, blue: 0.800)
    static let sourCream = Color(red: 0.992, green: 0.976, blue: 0.937)
    static let broth = Color(red: 0.949, green: 0.788, blue: 0.443)
    static let orangeSoup = Color(red: 0.945, green: 0.596, blue: 0.271)
    static let greenSoup = Color(red: 0.553, green: 0.722, blue: 0.369)
    static let pesto = Color(red: 0.420, green: 0.596, blue: 0.290)
    static let oil = Color(red: 0.886, green: 0.780, blue: 0.353)
    static let gravy = Color(red: 0.553, green: 0.369, blue: 0.239)
    static let curry = Color(red: 0.918, green: 0.596, blue: 0.231)
    static let redCurry = Color(red: 0.894, green: 0.420, blue: 0.227)
    static let greenCurry = Color(red: 0.584, green: 0.690, blue: 0.329)
    static let lentil = Color(red: 0.937, green: 0.690, blue: 0.271)
    static let sweetSour = Color(red: 0.925, green: 0.380, blue: 0.255)
    static let chili = Color(red: 0.659, green: 0.251, blue: 0.161)
    static let bean = Color(red: 0.471, green: 0.137, blue: 0.137)
    static let cheese = Color(red: 0.988, green: 0.808, blue: 0.380)
    static let mozzarella = Color(red: 0.992, green: 0.969, blue: 0.910)
    static let feta = Color(red: 0.996, green: 0.984, blue: 0.957)
    static let egg = Color(red: 0.988, green: 0.835, blue: 0.341)
    static let eggWhite = Color(red: 0.996, green: 0.980, blue: 0.941)
    static let butter = Color(red: 0.992, green: 0.871, blue: 0.420)
    static let jam = Color(red: 0.773, green: 0.204, blue: 0.267)
    static let syrup = Color(red: 0.812, green: 0.533, blue: 0.165)
    static let cinnamon = Color(red: 0.639, green: 0.400, blue: 0.235)

    static let green = Color(red: 0.341, green: 0.596, blue: 0.306)
    static let basil = Color(red: 0.302, green: 0.573, blue: 0.302)
    static let leaf = Color(red: 0.584, green: 0.769, blue: 0.388)
    static let pea = Color(red: 0.420, green: 0.678, blue: 0.290)
    static let cucumber = Color(red: 0.796, green: 0.886, blue: 0.612)
    static let lemon = Color(red: 0.984, green: 0.859, blue: 0.333)
    static let lime = Color(red: 0.604, green: 0.769, blue: 0.333)
    static let carrot = Color(red: 0.949, green: 0.553, blue: 0.204)
    static let bell = Color(red: 0.937, green: 0.471, blue: 0.220)
    static let corn = Color(red: 0.988, green: 0.835, blue: 0.271)
    static let cabbage = Color(red: 0.553, green: 0.318, blue: 0.561)
    static let mushroom = Color(red: 0.851, green: 0.757, blue: 0.639)
    static let apple = Color(red: 0.957, green: 0.890, blue: 0.561)
    static let berry = Color(red: 0.733, green: 0.192, blue: 0.310)
}

/// The four food colours one drawing may use, besides paper, plate and ink.
///
/// Roles, loosely: `main` is the dish itself, `sauce` what covers or glazes it, `side` the
/// starch or second component, `garnish` the small bright accent.
struct DishPalette: Equatable {
    var main: Color
    var sauce: Color
    var side: Color
    var garnish: Color
}

extension DishPalette {
    init(meal: Meal, form: DishForm) {
        self.init(form: form, name: meal.name, tags: meal.tags, ingredientNames: meal.ingredients.map(\.name))
    }

    /// Colours read from the name and ingredients: tomato sauce is red, cream sauce pale,
    /// salmon pink and cod white.
    init(form: DishForm, name: String, tags: Set<MealTag>, ingredientNames: [String]) {
        let title = DishText([name])
        let all = DishText([name] + ingredientNames)
        self = DishPalette.derive(form, title: title, all: all, tags: tags)
    }

    static func standard(for form: DishForm) -> DishPalette {
        DishPalette(form: form, name: "", tags: [], ingredientNames: [])
    }

    private static let salmonWords = ["laks", "salmon", "orret", "trout", "=roye", "arctic char"]
    private static let tomatoWords = ["tomat", "tomato", "bolognese", "marinara", "arrabbiata",
                                      "pizzasaus", "pizza sauce", "salsa", "ketchup"]
    private static let creamWords = ["flote", "cream", "creme", "rommesaus"]
    private static let starchPotato = ["potet", "potato"]
    private static let starchRice = ["=ris", "=rice", "jasminris", "basmati"]

    private static func starch(_ all: DishText) -> Color {
        if all.has(starchPotato) { return DishColor.potato }
        if all.has(starchRice) { return DishColor.rice }
        return DishColor.potato
    }

    private static func protein(_ all: DishText, tags: Set<MealTag>) -> Color {
        if all.has(salmonWords) { return DishColor.salmon }
        if all.has(["reke", "shrimp", "prawn", "scampi"]) { return DishColor.shrimp }
        if all.has(["falafel"]) { return DishColor.falafel }
        if all.has(["halloumi"]) { return DishColor.halloumi }
        if all.has(["tofu"]) { return DishColor.tofu }
        if all.has(["kylling", "chicken", "kalkun", "turkey"]) || tags.contains(.chicken) { return DishColor.chicken }
        if all.has(["tunfisk", "tuna"]) { return DishColor.tuna }
        if all.has(["torsk", "=cod", "=sei", "hyse", "fisk", "fish"]) || tags.contains(.fish) { return DishColor.whiteFish }
        if all.has(["bacon"]) { return DishColor.bacon }
        if all.has(["svin", "pork", "skinke", "=ham"]) { return DishColor.pork }
        if all.has(["kjottdeig", "mince", "biff", "beef", "storfe", "=lam", "lamme", "lamb", "kjott", "meat"])
            || tags.contains(.meat) { return DishColor.mince }
        return DishColor.chickpea
    }

    // One case per form keeps every drawing's colours in one place.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private static func derive(_ form: DishForm, title: DishText, all: DishText, tags: Set<MealTag>) -> DishPalette {
        let green = DishColor.green
        switch form {
        case .fishFillet:
            let fish = all.has(salmonWords) ? DishColor.salmon : DishColor.whiteFish
            let citrus = all.has(["lime"]) ? DishColor.lime : DishColor.lemon
            return DishPalette(main: fish, sauce: citrus, side: starch(all), garnish: green)
        case .fishCakes:
            let slaw = all.has(["gulrot", "carrot"]) ? DishColor.carrot : green
            return DishPalette(main: DishColor.fishCake, sauce: DishColor.browned, side: starch(all), garnish: slaw)
        case .casserole:
            let mashTop = title.has(["potetmos", "mash", "shepherd", "cottage pie", "deigform"])
            return DishPalette(main: mashTop ? DishColor.mash : DishColor.golden, sauce: DishColor.browned,
                               side: DishColor.dish, garnish: green)
        case .soup:
            return soupPalette(title: title, all: all)
        case .pasta:
            return pastaPalette(title: title, all: all, tags: tags)
        case .lasagne:
            let sauce = all.has(tomatoWords) || !all.has(creamWords) ? DishColor.tomato : DishColor.creamSauce
            return DishPalette(main: DishColor.pasta, sauce: sauce, side: DishColor.golden, garnish: DishColor.basil)
        case .pizza:
            return pizzaPalette(title: title, all: all, tags: tags)
        case .taco:
            let topping = all.has(["rodkal", "red cabbage", "cabbage", "=kal", "kalsalat"]) ? DishColor.cabbage : DishColor.tomato
            return DishPalette(main: DishColor.shell, sauce: protein(all, tags: tags), side: DishColor.leaf, garnish: topping)
        case .wrap:
            let accent: Color
            if all.has(["paprika", "bell pepper", "=pepper", "=peppers"]) {
                accent = DishColor.bell
            } else if all.has(tomatoWords) {
                accent = DishColor.tomato
            } else if all.has(["agurk", "cucumber"]) {
                accent = DishColor.cucumber
            } else {
                accent = DishColor.tomato
            }
            return DishPalette(main: DishColor.tortilla, sauce: protein(all, tags: tags), side: DishColor.leaf, garnish: accent)
        case .noodles:
            let filling = tags.contains(.vegetarian) && !all.has(["kylling", "chicken"]) ? DishColor.tofu : protein(all, tags: tags)
            return DishPalette(main: DishColor.noodle, sauce: filling, side: DishColor.carrot, garnish: green)
        case .curry:
            return curryPalette(title: title, all: all, tags: tags)
        case .stew:
            let base = title.has(["chili"]) || all.has(tomatoWords) ? DishColor.chili : DishColor.gravy
            let pieces = all.has(["bonne", "bean", "kidney", "kikert", "chickpea", "linse", "lentil"]) ? DishColor.bean : DishColor.carrot
            return DishPalette(main: base, sauce: pieces, side: DishColor.sourCream, garnish: green)
        case .meatballs:
            let balls: Color
            if title.has(["falafel", "vegetar", "veggie", "vegan"]) {
                balls = DishColor.falafel
            } else if title.has(["fisk", "fish"]) {
                balls = DishColor.fishCake
            } else {
                balls = DishColor.meatball
            }
            let sauce: Color
            if all.has(tomatoWords) {
                sauce = DishColor.tomato
            } else if all.has(creamWords) {
                sauce = DishColor.creamSauce
            } else {
                sauce = DishColor.gravy
            }
            let side: Color
            if all.has(["spaghetti", "spagetti", "pasta"]) {
                side = DishColor.pasta
            } else if all.has(starchRice) && !all.has(starchPotato) {
                side = DishColor.rice
            } else {
                side = DishColor.mash
            }
            return DishPalette(main: balls, sauce: sauce, side: side, garnish: DishColor.pea)
        case .burger:
            let patty: Color
            if title.has(["veggie", "vegetar", "vegan", "bonne", "bean", "plant"]) || tags.contains(.vegetarian) {
                patty = DishColor.veggiePatty
            } else if all.has(["fisk", "fish", "laks", "salmon"]) {
                patty = DishColor.fishCake
            } else if all.has(["kylling", "chicken"]) {
                patty = DishColor.chicken
            } else {
                patty = DishColor.patty
            }
            let slice = all.has(["=ost", "cheese", "cheddar", "osteskive"]) ? DishColor.cheese : DishColor.tomato
            return DishPalette(main: DishColor.bun, sauce: patty, side: DishColor.leaf, garnish: slice)
        case .sausages:
            return DishPalette(main: DishColor.sausage, sauce: DishColor.sear, side: DishColor.mash, garnish: DishColor.pea)
        case .roastChicken:
            let veg = all.has(["gulrot", "carrot"]) ? DishColor.carrot : green
            return DishPalette(main: DishColor.roast, sauce: green, side: starch(all), garnish: veg)
        case .steak:
            let meat: Color
            if all.has(["svin", "pork", "kotelett", "ribbe", "skinke"]) {
                meat = DishColor.pork
            } else if all.has(["=lam", "lamme", "lamb"]) {
                meat = DishColor.lamb
            } else {
                meat = DishColor.beef
            }
            let accent = all.has(["eple", "apple"]) ? DishColor.apple : green
            return DishPalette(main: meat, sauce: DishColor.sear, side: starch(all), garnish: accent)
        case .salad:
            return saladPalette(title: title, all: all)
        case .grainBowl:
            let grain: Color
            if all.has(["quinoa"]) {
                grain = DishColor.quinoa
            } else if all.has(starchRice) {
                grain = DishColor.rice
            } else {
                grain = DishColor.couscous
            }
            return DishPalette(main: grain, sauce: protein(all, tags: tags), side: DishColor.tomato, garnish: green)
        case .rice:
            let base = title.has(["risotto"]) ? DishColor.risotto : DishColor.friedRice
            let bits = all.has(["=egg", "=eggs", "egg"]) ? DishColor.egg : protein(all, tags: tags)
            return DishPalette(main: base, sauce: bits, side: DishColor.carrot, garnish: DishColor.pea)
        case .omelette:
            let filling: Color
            if all.has(["skinke", "=ham", "bacon"]) {
                filling = DishColor.ham
            } else {
                filling = DishColor.tomato
            }
            return DishPalette(main: DishColor.egg, sauce: DishColor.browned, side: filling, garnish: green)
        case .porridge:
            let base = all.has(["ris", "rice"]) ? DishColor.ricePorridge : DishColor.oat
            let topping = all.has(["baer", "berry", "berries", "syltetoy", "=jam"]) ? DishColor.berry : DishColor.cinnamon
            return DishPalette(main: base, sauce: DishColor.butter, side: DishColor.cinnamon, garnish: topping)
        case .pancakes:
            let sweet = all.has(["sirup", "syrup", "lonn", "maple", "honning", "honey"]) ? DishColor.syrup : DishColor.jam
            let side = all.has(["bacon", "flesk"]) ? DishColor.bacon : DishColor.berry
            return DishPalette(main: DishColor.pancake, sauce: sweet, side: side, garnish: DishColor.butter)
        case .plate:
            return DishPalette(main: protein(all, tags: tags), sauce: DishColor.gravy, side: starch(all), garnish: green)
        }
    }

    private static func soupPalette(title: DishText, all: DishText) -> DishPalette {
        let broth: Color
        if title.has(["tomat", "tomato", "gazpacho", "minestrone"]) {
            broth = DishColor.tomatoSoup
        } else if title.has(["erte", "pea soup", "brokkoli", "broccoli", "spinat", "spinach", "asparges", "asparagus"]) {
            broth = DishColor.greenSoup
        } else if title.has(["gresskar", "pumpkin", "squash", "gulrot", "carrot", "linse", "lentil", "sotpotet", "sweet potato"]) {
            broth = DishColor.orangeSoup
        } else if title.has(["blomkal", "cauliflower", "potet", "potato", "purre", "leek", "sopp", "mushroom",
                             "fiskesuppe", "fish soup", "chowder", "selleri", "celeriac"]) {
            broth = DishColor.cream
        } else if title.has(["kylling", "chicken", "buljong", "broth", "nudl", "noodle", "ramen", "=pho"]) {
            broth = DishColor.broth
        } else if all.has(tomatoWords) {
            broth = DishColor.tomatoSoup
        } else if all.has(creamWords) {
            broth = DishColor.cream
        } else {
            broth = DishColor.broth
        }
        let swirl: Color
        if broth == DishColor.cream {
            swirl = DishColor.oil
        } else if broth == DishColor.broth {
            swirl = broth
        } else {
            swirl = DishColor.sourCream
        }
        let pieces: Color
        if all.has(["nudl", "noodle", "ramen", "udon"]) {
            pieces = DishColor.noodle
        } else if title.has(["=egg", "=eggs", "egget"]) {
            pieces = DishColor.eggWhite
        } else if all.has(["bonne", "bean", "kidney", "kikert", "chickpea"]) {
            pieces = DishColor.bean
        } else if all.has(["brod", "bread", "krutong", "crouton"]) {
            pieces = DishColor.crouton
        } else {
            pieces = DishColor.carrot
        }
        return DishPalette(main: broth, sauce: swirl, side: pieces, garnish: DishColor.green)
    }

    private static func pastaPalette(title: DishText, all: DishText, tags: Set<MealTag>) -> DishPalette {
        let sauce: Color
        if all.has(["pesto"]) {
            sauce = DishColor.pesto
        } else if title.has(["carbonara", "alfredo"]) {
            sauce = DishColor.creamSauce
        } else if all.has(tomatoWords) {
            sauce = all.has(creamWords) ? DishColor.rose : DishColor.tomato
        } else if all.has(creamWords + ["=ost", "cheese", "parmesan"]) {
            sauce = DishColor.creamSauce
        } else {
            sauce = DishColor.pasta
        }
        let topping: Color
        if all.has(["bacon", "pancetta", "guanciale"]) {
            topping = DishColor.bacon
        } else if all.has(["kjottdeig", "mince", "bolognese"]) {
            topping = DishColor.mince
        } else if all.has(["kylling", "chicken"]) {
            topping = DishColor.chicken
        } else if all.has(["tunfisk", "tuna"]) {
            topping = DishColor.tuna
        } else if all.has(salmonWords) {
            topping = DishColor.salmon
        } else if all.has(["reke", "shrimp", "prawn"]) {
            topping = DishColor.shrimp
        } else {
            topping = sauce
        }
        return DishPalette(main: DishColor.pasta, sauce: sauce, side: topping, garnish: DishColor.basil)
    }

    private static func pizzaPalette(title: DishText, all: DishText, tags: Set<MealTag>) -> DishPalette {
        let base = title.has(["bianca", "hvit", "white"]) ? DishColor.creamSauce : DishColor.tomato
        let cheese = title.has(["margherita", "margarita"]) || all.has(["mozzarella"]) ? DishColor.mozzarella : DishColor.cheese
        let topping: Color
        if all.has(["pepperoni", "salami"]) {
            topping = DishColor.pepperoni
        } else if all.has(["sopp", "mushroom", "sjampinjong"]) {
            topping = DishColor.mushroom
        } else if all.has(["skinke", "=ham"]) {
            topping = DishColor.ham
        } else if all.has(["kjottdeig", "mince", "kebab"]) {
            topping = DishColor.mince
        } else if all.has(["basilikum", "basil"]) || tags.contains(.vegetarian) {
            topping = DishColor.basil
        } else {
            topping = DishColor.pepperoni
        }
        return DishPalette(main: DishColor.crust, sauce: base, side: cheese, garnish: topping)
    }

    private static func curryPalette(title: DishText, all: DishText, tags: Set<MealTag>) -> DishPalette {
        let sauce: Color
        if title.has(["green curry", "=gronn", "gronn curry"]) {
            sauce = DishColor.greenCurry
        } else if title.has(["red curry", "=red", "=rod", "rod curry"]) {
            sauce = DishColor.redCurry
        } else if title.has(["sweet and sour", "sursot"]) {
            sauce = DishColor.sweetSour
        } else if title.has(["linse", "lentil", "=dal", "=dhal"]) {
            sauce = DishColor.lentil
        } else {
            sauce = DishColor.curry
        }
        return DishPalette(main: sauce, sauce: protein(all, tags: tags), side: DishColor.rice, garnish: DishColor.green)
    }

    private static func saladPalette(title: DishText, all: DishText) -> DishPalette {
        let base = title.has(["pasta"]) ? DishColor.pasta : DishColor.leaf
        let red: Color
        if all.has(tomatoWords) {
            red = DishColor.tomato
        } else if all.has(["mais", "corn"]) {
            red = DishColor.corn
        } else {
            red = DishColor.tomato
        }
        let topping: Color
        if all.has(["tunfisk", "tuna"]) {
            topping = DishColor.tuna
        } else if all.has(["kylling", "chicken"]) {
            topping = DishColor.chicken
        } else if all.has(salmonWords) {
            topping = DishColor.salmon
        } else if all.has(["halloumi"]) {
            topping = DishColor.halloumi
        } else if all.has(["=egg", "=eggs"]) {
            topping = DishColor.egg
        } else {
            topping = DishColor.feta
        }
        return DishPalette(main: base, sauce: red, side: DishColor.cucumber, garnish: topping)
    }
}

// MARK: - View

/// A flat, top-down drawing of a dish on cream paper. Decorative: hidden from VoiceOver.
///
/// Drawn rather than bundled so it stays sharp from a 32-point row thumbnail to a 220-point
/// hero, and so a new kind of dish costs a few lines instead of a commissioned picture. Fine
/// details (grains, seeds, flakes) are left out below 60 points, where they would be noise.
struct DishIllustration: View {
    let form: DishForm
    var palette: DishPalette?

    init(form: DishForm, palette: DishPalette? = nil) {
        self.form = form
        self.palette = palette
    }

    init(meal: Meal) {
        let inferred = DishForm.form(for: meal)
        form = inferred
        palette = DishPalette(meal: meal, form: inferred)
    }

    var body: some View {
        let form = self.form
        let colors = palette ?? DishPalette.standard(for: form)
        Canvas { context, size in
            DishRenderer.draw(form, palette: colors, context: context, size: size)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Drawing

/// Draws in a unit square centred on the canvas: x and y run from -0.5 to 0.5 of the
/// shortest side, y downwards. Every length below is a fraction of that side.
private struct DishPainter {
    var context: GraphicsContext
    let unit: CGFloat
    let lineWidth: CGFloat
    let detailed: Bool

    func moved(_ x: CGFloat, _ y: CGFloat, degrees: Double = 0) -> DishPainter {
        var copy = self
        copy.context.translateBy(x: x * unit, y: y * unit)
        if degrees != 0 { copy.context.rotate(by: .degrees(degrees)) }
        return copy
    }

    func clipped(to path: Path) -> DishPainter {
        var copy = self
        copy.context.clip(to: path)
        return copy
    }

    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: x * unit, y: y * unit)
    }

    func oval(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path {
        let rect = CGRect(x: (x - rx) * unit, y: (y - ry) * unit, width: rx * 2 * unit, height: ry * 2 * unit)
        return Path(ellipseIn: rect)
    }

    func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
        oval(x, y, r, r)
    }

    /// A rounded rectangle centred on (x, y).
    func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, corner: CGFloat) -> Path {
        let rect = CGRect(x: (x - w / 2) * unit, y: (y - h / 2) * unit, width: w * unit, height: h * unit)
        let radius = min(corner, min(w, h) / 2) * unit
        return Path(roundedRect: rect, cornerRadius: radius)
    }

    func polygon(_ points: [(CGFloat, CGFloat)]) -> Path {
        let corners = points.map { point($0.0, $0.1) }
        return Path { path in
            path.addLines(corners)
            path.closeSubpath()
        }
    }

    /// Points along an elliptical arc. Angles in degrees: 0 is right, 90 is down.
    func arc(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, from start: Double, to end: Double) -> [CGPoint] {
        let steps = max(8, Int(abs(end - start) / 6))
        return (0...steps).map { (index: Int) -> CGPoint in
            let degrees = start + (end - start) * Double(index) / Double(steps)
            let radians = degrees * Double.pi / 180
            return point(cx + rx * CGFloat(cos(radians)), cy + ry * CGFloat(sin(radians)))
        }
    }

    func closed(_ points: [CGPoint]) -> Path {
        Path { path in
            path.addLines(points)
            path.closeSubpath()
        }
    }

    func polyline(_ points: [CGPoint]) -> Path {
        Path { path in
            path.addLines(points)
        }
    }

    func segment(_ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat)) -> Path {
        let start = point(a.0, a.1)
        let end = point(b.0, b.1)
        return Path { path in
            path.move(to: start)
            path.addLine(to: end)
        }
    }

    /// A stroke `width` outline-widths thick.
    func pen(_ path: Path, _ color: Color, width: CGFloat) {
        let style = StrokeStyle(lineWidth: lineWidth * width, lineCap: .round, lineJoin: .round)
        context.stroke(path, with: .color(color), style: style)
    }

    func outline(_ path: Path, weight: CGFloat = 0.8) {
        pen(path, DishColor.ink, width: weight)
    }

    func shape(_ path: Path, _ color: Color, weight: CGFloat = 0.8) {
        context.fill(path, with: .color(color))
        if weight > 0 { outline(path, weight: weight) }
    }

    /// A thick coloured stroke with an ink edge, for chopsticks, bacon and noodles.
    func band(_ path: Path, _ color: Color, width: CGFloat) {
        pen(path, DishColor.ink, width: width + 1.4)
        pen(path, color, width: width)
    }

    /// Overlapping circles filled as one cut-paper shape with a single outer outline.
    func blob(_ circles: [(CGFloat, CGFloat, CGFloat)], _ color: Color, weight: CGFloat = 0.8) {
        for item in circles {
            pen(circle(item.0, item.1, item.2), DishColor.ink, width: weight * 2)
        }
        for item in circles {
            context.fill(circle(item.0, item.1, item.2), with: .color(color))
        }
    }
}

private enum DishRenderer {
    static func draw(_ form: DishForm, palette c: DishPalette, context: GraphicsContext, size: CGSize) {
        let side = min(size.width, size.height)
        guard side > 0 else { return }
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(AppTheme.artworkPaper))
        var centred = context
        centred.translateBy(x: size.width / 2, y: size.height / 2)
        let p = DishPainter(context: centred, unit: side, lineWidth: max(1, side * 0.022), detailed: side >= 60)
        switch form {
        case .fishFillet: fishFillet(p, c)
        case .fishCakes: fishCakes(p, c)
        case .casserole: casserole(p, c)
        case .soup: soup(p, c)
        case .pasta: pasta(p, c)
        case .lasagne: lasagne(p, c)
        case .pizza: pizza(p, c)
        case .taco: taco(p, c)
        case .wrap: wrap(p, c)
        case .noodles: noodles(p, c)
        case .curry: curry(p, c)
        case .stew: stew(p, c)
        case .meatballs: meatballs(p, c)
        case .burger: burger(p, c)
        case .sausages: sausages(p, c)
        case .roastChicken: roastChicken(p, c)
        case .steak: steak(p, c)
        case .salad: salad(p, c)
        case .grainBowl: grainBowl(p, c)
        case .rice: rice(p, c)
        case .omelette: omelette(p, c)
        case .porridge: porridge(p, c)
        case .pancakes: pancakes(p, c)
        case .plate: plainPlate(p, c)
        }
    }

    // MARK: Shared pieces

    static func drawPlate(_ p: DishPainter) {
        p.shape(p.circle(0, 0, 0.42), DishColor.rim, weight: 1)
        p.shape(p.circle(0, 0, 0.335), DishColor.well, weight: 0)
        p.pen(p.circle(0, 0, 0.335), DishColor.rimShade, width: 0.5)
    }

    /// A bowl filled to the brim with `food`; returns the food surface for clipping.
    @discardableResult
    static func drawBowl(_ p: DishPainter, _ food: Color) -> Path {
        p.shape(p.circle(0, 0, 0.42), DishColor.rim, weight: 1)
        let inside = p.circle(0, 0, 0.33)
        p.shape(inside, food, weight: 0.7)
        return inside
    }

    static func leaf(_ p: DishPainter, _ x: CGFloat, _ y: CGFloat, size: CGFloat, degrees: Double, _ color: Color, weight: CGFloat = 0.6) {
        let q = p.moved(x, y, degrees: degrees)
        let tip = q.point(size, 0)
        let base = q.point(-size, 0)
        let upper = q.point(0, -size * 0.9)
        let lower = q.point(0, size * 0.9)
        let outline = Path { path in
            path.move(to: base)
            path.addQuadCurve(to: tip, control: upper)
            path.addQuadCurve(to: base, control: lower)
            path.closeSubpath()
        }
        q.shape(outline, color, weight: weight)
    }

    static func polar(_ degrees: Double, _ radius: CGFloat) -> (CGFloat, CGFloat) {
        let radians = degrees * Double.pi / 180
        return (radius * CGFloat(cos(radians)), radius * CGFloat(sin(radians)))
    }

    /// Deterministic scatter in a unit circle, so a drawing never changes between renders.
    static let scatter: [(CGFloat, CGFloat, Double)] = [
        (-0.55, -0.35, 20), (0.25, -0.62, -30), (0.62, 0.08, 60), (-0.15, 0.30, -10), (0.05, -0.10, 80),
        (-0.72, 0.38, 40), (0.48, 0.58, -50), (-0.38, 0.78, 10), (0.80, -0.30, 0), (-0.82, -0.05, -70),
        (0.10, 0.75, 35), (-0.30, -0.80, -45), (0.55, -0.15, 15), (-0.05, 0.50, 65), (0.35, 0.28, -20),
        (-0.60, 0.05, 50)
    ]

    static func grains(_ p: DishPainter, x: CGFloat, y: CGFloat, spread: CGFloat, _ color: Color, count: Int = 16) {
        for item in scatter.prefix(count) {
            let grain = p.moved(x + item.0 * spread, y + item.1 * spread, degrees: item.2)
            grain.shape(grain.oval(0, 0, 0.02, 0.009), color, weight: 0)
        }
    }

    /// Potatoes, or a mound of rice when the side is rice.
    static func starchSide(_ p: DishPainter, _ color: Color, x: CGFloat, y: CGFloat) {
        if color == DishColor.rice {
            let mound: [(CGFloat, CGFloat, CGFloat)] = [
                (x - 0.06, y + 0.01, 0.065), (x + 0.01, y - 0.03, 0.075), (x + 0.07, y + 0.02, 0.065), (x, y + 0.05, 0.065)
            ]
            p.blob(mound, color)
            if p.detailed { grains(p, x: x, y: y + 0.01, spread: 0.08, DishColor.grain, count: 10) }
        } else {
            p.shape(p.oval(x - 0.08, y + 0.02, 0.068, 0.055), color)
            p.shape(p.oval(x + 0.05, y + 0.045, 0.068, 0.055), color)
            p.shape(p.oval(x + 0.01, y - 0.05, 0.065, 0.05), color)
        }
    }

    static func wedge(_ p: DishPainter, _ color: Color) {
        let peel = p.closed(p.arc(0, 0, 0.075, 0.075, from: 180, to: 360))
        p.shape(peel, color)
        if p.detailed {
            p.pen(p.polyline(p.arc(0, 0, 0.05, 0.05, from: 195, to: 345)), DishColor.well, width: 0.6)
        }
    }

    static func peas(_ p: DishPainter, _ color: Color, around center: (CGFloat, CGFloat)) {
        var spots: [(CGFloat, CGFloat)] = [(0, 0), (0.05, 0.02), (-0.04, 0.03), (0.01, -0.045)]
        if p.detailed { spots += [(-0.06, -0.02), (0.06, -0.03)] }
        for spot in spots {
            p.shape(p.circle(center.0 + spot.0, center.1 + spot.1, 0.026), color, weight: 0.5)
        }
    }

    // MARK: Forms

    static func fishFillet(_ p: DishPainter, _ c: DishPalette) {
        drawPlate(p)
        starchSide(p, c.side, x: 0.10, y: 0.16)
        p.blob([(-0.21, 0.07, 0.06), (-0.14, 0.12, 0.06), (-0.22, 0.15, 0.055)], c.garnish)
        wedge(p.moved(0.20, -0.17, degrees: 30), c.sauce)
        let fillet = p.moved(-0.04, -0.06, degrees: -14)
        fillet.shape(fillet.box(0, 0, 0.40, 0.17, corner: 0.075), c.main)
        let flakeColor = c.main == DishColor.salmon ? DishColor.well : DishColor.flake
        let offsets: [CGFloat] = p.detailed ? [-0.1, -0.02, 0.06, 0.13] : [-0.05, 0.07]
        for x in offsets {
            let top = fillet.point(x - 0.015, -0.055)
            let bottom = fillet.point(x - 0.015, 0.055)
            let bend = fillet.point(x + 0.035, 0)
            let flake = Path { path in
                path.move(to: top)
                path.addQuadCurve(to: bottom, control: bend)
            }
            fillet.pen(flake, flakeColor, width: 0.8)
        }
    }

    static func fishCakes(_ p: DishPainter, _ c: DishPalette) {
        drawPlate(p)
        starchSide(p, c.side, x: 0.12, y: 0.15)
        var slaw: [(CGFloat, CGFloat, Double)] = [(-0.19, 0.13, 30), (-0.14, 0.18, -20), (-0.22, 0.19, 70)]
        if p.detailed { slaw += [(-0.10, 0.14, 50), (-0.17, 0.23, 10)] }
        for strip in slaw {
            let q = p.moved(strip.0, strip.1, degrees: strip.2)
            q.band(q.segment((-0.035, 0), (0.035, 0)), c.garnish, width: 1.1)
        }
        let cakes: [(CGFloat, CGFloat)] = [(-0.13, -0.09), (0.07, -0.14), (-0.01, 0.03)]
        for cake in cakes {
            p.shape(p.circle(cake.0, cake.1, 0.1), c.main)
            if p.detailed {
                p.pen(p.circle(cake.0, cake.1, 0.06), c.sauce, width: 0.9)
            }
        }
    }

    static func casserole(_ p: DishPainter, _ c: DishPalette) {
        p.shape(p.box(-0.40, 0, 0.10, 0.20, corner: 0.04), c.side)
        p.shape(p.box(0.40, 0, 0.10, 0.20, corner: 0.04), c.side)
        p.shape(p.box(0, 0, 0.76, 0.60, corner: 0.12), c.side, weight: 1)
        let top = p.box(0, 0, 0.62, 0.46, corner: 0.08)
        p.shape(top, c.main)
        let crust = p.clipped(to: top)
        var spots: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (-0.17, -0.11, 0.075, 0.05), (0.08, -0.13, 0.07, 0.045), (0.19, 0.06, 0.075, 0.05), (-0.08, 0.08, 0.08, 0.05)
        ]
        if p.detailed { spots += [(0.03, -0.01, 0.05, 0.03), (-0.23, 0.12, 0.05, 0.035), (0.24, -0.15, 0.04, 0.03)] }
        for spot in spots {
            crust.shape(crust.oval(spot.0, spot.1, spot.2, spot.3), c.sauce, weight: 0)
        }
        if p.detailed {
            leaf(p, -0.02, -0.07, size: 0.035, degrees: 30, c.garnish)
            leaf(p, 0.12, 0.13, size: 0.035, degrees: -40, c.garnish)
            leaf(p, -0.20, 0.0, size: 0.03, degrees: 80, c.garnish)
        }
        p.outline(top)
    }

    static func soup(_ p: DishPainter, _ c: DishPalette) {
        let inside = drawBowl(p, c.main)
        let liquid = p.clipped(to: inside)
        if c.sauce != c.main {
            let turns = 40
            let swirl = Path { path in
                for index in 0...turns {
                    let t = Double(index) / Double(turns)
                    let radians = (200 + 520 * t) * Double.pi / 180
                    let radius = 0.15 - 0.11 * CGFloat(t)
                    let spot = p.point(radius * CGFloat(cos(radians)), radius * CGFloat(sin(radians)))
                    if index == 0 { path.move(to: spot) } else { path.addLine(to: spot) }
                }
            }
            liquid.pen(swirl, c.sauce, width: 1.4)
        }
        if c.side == DishColor.noodle {
            let rows: [CGFloat] = p.detailed ? [-0.17, -0.06, 0.06, 0.17] : [-0.1, 0.08]
            for y in rows {
                let start = p.point(-0.30, y)
                let end = p.point(0.30, y + 0.02)
                let first = p.point(-0.10, y - 0.07)
                let second = p.point(0.10, y + 0.09)
                let strand = Path { path in
                    path.move(to: start)
                    path.addCurve(to: end, control1: first, control2: second)
                }
                liquid.band(strand, c.side, width: 1.0)
            }
        } else if c.side != c.main {
            var pieces: [(CGFloat, CGFloat)] = [(0.18, -0.12), (-0.17, 0.13), (0.10, 0.19)]
            if p.detailed { pieces.append((-0.12, -0.19)) }
            for piece in pieces {
                if c.side == DishColor.eggWhite {
                    liquid.shape(liquid.oval(piece.0, piece.1, 0.075, 0.058), c.side)
                    liquid.shape(liquid.circle(piece.0, piece.1, 0.032), DishColor.egg, weight: 0.5)
                } else {
                    let q = liquid.moved(piece.0, piece.1, degrees: 18)
                    q.shape(q.box(0, 0, 0.07, 0.07, corner: 0.015), c.side)
                }
            }
        }
        if p.detailed {
            leaf(liquid, -0.04, -0.21, size: 0.03, degrees: 20, c.garnish)
            leaf(liquid, 0.22, 0.05, size: 0.03, degrees: -60, c.garnish)
            leaf(liquid, -0.21, -0.03, size: 0.028, degrees: 70, c.garnish)
        } else {
            liquid.shape(liquid.circle(-0.04, -0.2, 0.025), c.garnish, weight: 0)
            liquid.shape(liquid.circle(0.2, 0.06, 0.025), c.garnish, weight: 0)
        }
        p.outline(inside, weight: 0.7)
    }

    static func pasta(_ p: DishPainter, _ c: DishPalette) {
        drawPlate(p)
        let nest = p.circle(0, 0.01, 0.25)
        p.shape(nest, c.main)
        let strands = p.clipped(to: nest)
        var rings: [(CGFloat, CGFloat, CGFloat, Double, Double)] = [
            (0.02, 0.03, 0.20, 200, 340), (-0.03, 0.0, 0.15, 20, 170), (0.0, 0.04, 0.10, 230, 400)
        ]
        if p.detailed {
            rings += [(0.04, -0.02, 0.22, 60, 150), (-0.05, 0.03, 0.21, 250, 330), (0.01, 0.0, 0.06, 0, 300)]
        }
        for ring in rings {
            strands.pen(p.polyline(p.arc(ring.0, ring.1, ring.2, ring.2, from: ring.3, to: ring.4)), DishColor.pastaLine, width: 0.8)
        }
        if c.sauce != c.main {
            p.blob([(-0.02, -0.02, 0.11), (0.06, 0.01, 0.09), (-0.06, 0.05, 0.08), (0.02, 0.07, 0.07)], c.sauce)
        }
        if c.side != c.sauce {
            var bits: [(CGFloat, CGFloat, Double)] = [(-0.03, -0.04, 20), (0.06, 0.03, -30), (-0.05, 0.06, 50)]
            if p.detailed { bits.append((0.03, -0.09, 10)) }
            for bit in bits {
                let q = p.moved(bit.0, bit.1, degrees: bit.2)
                q.shape(q.box(0, 0, 0.055, 0.045, corner: 0.012), c.side, weight: 0.6)
            }
        }
        leaf(p, 0.10, -0.12, size: 0.05, degrees: -30, c.garnish)
        if p.detailed { leaf(p, -0.12, -0.08, size: 0.045, degrees: 40, c.garnish) }
    }

    static func lasagne(_ p: DishPainter, _ c: DishPalette) {
        drawPlate(p)
        let left: CGFloat = -0.23
        let right: CGFloat = 0.17
        let top: CGFloat = -0.03
        let bottom: CGFloat = 0.18
        let dx: CGFloat = 0.10
        let dy: CGFloat = -0.14
        let front = p.polygon([(left, top), (right, top), (right, bottom), (left, bottom)])
        let side = p.polygon([(right, top), (right + dx, top + dy), (right + dx, bottom + dy), (right, bottom)])
        let lid = p.polygon([(left, top), (right, top), (right + dx, top + dy), (left + dx, top + dy)])
        p.shape(front, c.main, weight: 0)
        p.shape(side, c.main, weight: 0)
        var bands: [(CGFloat, CGFloat)] = [(0.02, 0.07), (0.12, 0.18)]
        if p.detailed { bands = [(0.0, 0.035), (0.07, 0.105), (0.14, 0.18)] }
        for band in bands {
            let low = band.0
            let high = band.1
            p.shape(p.polygon([(left, low), (right, low), (right, high), (left, high)]), c.sauce, weight: 0)
            p.shape(p.polygon([(right, low), (right + dx, low + dy), (right + dx, high + dy), (right, high)]), c.sauce, weight: 0)
        }
        p.shape(lid, c.side, weight: 0)
        if p.detailed {
            let bubbles: [(CGFloat, CGFloat)] = [(-0.10, -0.10), (0.07, -0.07), (0.15, -0.13)]
            for bubble in bubbles {
                p.shape(p.oval(bubble.0, bubble.1, 0.03, 0.014), c.sauce, weight: 0)
            }
        }
        p.outline(front)
        p.outline(side)
        p.outline(lid)
        leaf(p, -0.02, -0.10, size: 0.045, degrees: -20, c.garnish)
    }

    static func pizza(_ p: DishPainter, _ c: DishPalette) {
        p.shape(p.circle(0, 0, 0.42), c.main, weight: 1)
        p.shape(p.circle(0, 0, 0.35), c.sauce, weight: 0.6)
        var spots: [Double] = [30, 90, 150, 210, 270, 330]
        let melted = c.side == DishColor.mozzarella
        if melted {
            for angle in [10.0, 82, 154, 226, 298] {
                let (x, y) = polar(angle, 0.19)
                p.shape(p.circle(x, y, 0.08), c.side, weight: 0)
            }
            p.shape(p.circle(0, 0, 0.07), c.side, weight: 0)
            spots = [46, 118, 190, 262, 334]
        } else {
            p.shape(p.circle(0, 0, 0.315), c.side, weight: 0)
        }
        var places: [(Double, CGFloat)] = spots.map { ($0, CGFloat(0.22)) }
        if p.detailed && !melted { places += [(30, 0.09), (150, 0.09), (270, 0.09)] }
        for place in places {
            let (x, y) = polar(place.0, place.1)
            if c.garnish == DishColor.basil {
                leaf(p, x, y, size: 0.055, degrees: place.0, c.garnish)
            } else if c.garnish == DishColor.ham {
                let q = p.moved(x, y, degrees: place.0)
                q.shape(q.box(0, 0, 0.085, 0.07, corner: 0.015), c.garnish, weight: 0.6)
            } else if c.garnish == DishColor.mushroom {
                p.shape(p.oval(x, y, 0.055, 0.042), c.garnish, weight: 0.6)
            } else {
                p.shape(p.circle(x, y, 0.055), c.garnish, weight: 0.6)
            }
        }
        for angle in [0.0, 60, 120] {
            let a = polar(angle, 0.40)
            let b = polar(angle + 180, 0.40)
            p.pen(p.segment(a, b), DishColor.ink, width: 0.5)
        }
    }

    static func taco(_ p: DishPainter, _ c: DishPalette) {
        drawPlate(p)
        tacoShell(p.moved(-0.10, 0.0, degrees: -10), c)
        tacoShell(p.moved(0.12, 0.08, degrees: 10), c)
    }

    static func tacoShell(_ p: DishPainter, _ c: DishPalette) {
        p.blob([(-0.10, -0.075, 0.045), (0.0, -0.09, 0.05), (0.10, -0.075, 0.045)], c.side)
        p.blob([(-0.13, -0.02, 0.05), (-0.045, -0.04, 0.055), (0.045, -0.04, 0.055), (0.13, -0.02, 0.05)], c.sauce)
        var dots: [(CGFloat, CGFloat)] = [(-0.06, -0.065), (0.07, -0.075)]
        if p.detailed { dots.append((0.15, -0.05)) }
        for dot in dots {
            p.shape(p.circle(dot.0, dot.1, 0.022), c.garnish, weight: 0.5)
        }
        let shell = p.closed(p.arc(0, 0, 0.19, 0.17, from: 0, to: 180))
        p.shape(shell, c.main)
    }

    static func wrap(_ p: DishPainter, _ c: DishPalette) {
        drawPlate(p)
        wrapHalf(p.moved(-0.07, -0.07, degrees: -30), c)
        wrapHalf(p.moved(0.05, 0.09, degrees: -30), c)
    }

    static func wrapHalf(_ p: DishPainter, _ c: DishPalette) {
        p.shape(p.box(-0.02, 0, 0.36, 0.17, corner: 0.085), c.main)
        if p.detailed {
            let start = p.point(-0.17, -0.02)
            let end = p.point(0.08, -0.06)
            let bend = p.point(-0.05, 0.02)
            let fold = Path { path in
                path.move(to: start)
                path.addQuadCurve(to: end, control: bend)
            }
            p.outline(fold, weight: 0.5)
        }
        p.shape(p.oval(0.16, 0, 0.055, 0.085), c.main)
        p.shape(p.oval(0.16, 0, 0.038, 0.065), c.sauce, weight: 0.5)
        p.shape(p.circle(0.155, -0.03, 0.02), c.side, weight: 0)
        p.shape(p.circle(0.168, 0.026, 0.02), c.garnish, weight: 0)
    }

    static func noodles(_ p: DishPainter, _ c: DishPalette) {
        let inside = drawBowl(p, c.main)
        let food = p.clipped(to: inside)
        let rows: [CGFloat] = p.detailed ? [-0.22, -0.13, -0.04, 0.05, 0.14, 0.23] : [-0.14, 0.0, 0.14]
        for y in rows {
            let start = p.point(-0.36, y)
            let end = p.point(0.36, y + 0.02)
            let first = p.point(-0.12, y - 0.09)
            let second = p.point(0.12, y + 0.11)
            let strand = Path { path in
                path.move(to: start)
                path.addCurve(to: end, control1: first, control2: second)
            }
            food.pen(strand, DishColor.noodleLine, width: 0.8)
        }
        let pieces: [(CGFloat, CGFloat, Double)] = [(-0.12, -0.08, 20), (0.10, -0.02, -15), (-0.03, 0.14, 40)]
        for piece in pieces {
            let q = food.moved(piece.0, piece.1, degrees: piece.2)
            q.shape(q.box(0, 0, 0.11, 0.08, corner: 0.02), c.sauce)
        }
        var veg: [(CGFloat, CGFloat, Double)] = [(0.14, 0.14, 30), (-0.18, 0.06, -40)]
        if p.detailed { veg.append((0.04, -0.18, 70)) }
        for item in veg {
            let q = food.moved(item.0, item.1, degrees: item.2)
            q.shape(q.oval(0, 0, 0.045, 0.024), c.side, weight: 0.6)
        }
        var greens: [(CGFloat, CGFloat)] = [(0.02, 0.02), (-0.20, -0.08)]
        if p.detailed { greens += [(0.20, 0.06), (-0.10, 0.22), (0.12, -0.16)] }
        for item in greens {
            food.shape(food.circle(item.0, item.1, 0.025), c.garnish, weight: 0.5)
        }
        p.outline(inside, weight: 0.7)
        p.band(p.segment((0.02, -0.46), (0.46, -0.02)), DishColor.wood, width: 1.6)
        p.band(p.segment((0.10, -0.47), (0.47, -0.10)), DishColor.wood, width: 1.6)
    }

    static func curry(_ p: DishPainter, _ c: DishPalette) {
        let inside = drawBowl(p, c.main)
        let food = p.clipped(to: inside)
        food.blob([(-0.25, -0.12, 0.14), (-0.18, 0.03, 0.15), (-0.25, 0.17, 0.13)], c.side)
        if p.detailed { grains(food, x: -0.21, y: 0.02, spread: 0.13, DishColor.grain) }
        let chunks: [(CGFloat, CGFloat, Double)] = [(0.10, -0.15, 15), (0.20, 0.03, -20), (0.06, 0.04, 35), (0.12, 0.18, -5)]
        for chunk in chunks {
            let q = food.moved(chunk.0, chunk.1, degrees: chunk.2)
            q.shape(q.box(0, 0, 0.085, 0.075, corner: 0.02), c.sauce)
        }
        leaf(food, 0.0, -0.10, size: 0.035, degrees: 30, c.garnish)
        if p.detailed {
            leaf(food, 0.22, -0.10, size: 0.032, degrees: -50, c.garnish)
            leaf(food, 0.0, 0.21, size: 0.03, degrees: 10, c.garnish)
        }
        p.outline(inside, weight: 0.7)
    }

    static func stew(_ p: DishPainter, _ c: DishPalette) {
        let inside = drawBowl(p, c.main)
        var beans: [(CGFloat, CGFloat, Double)] = [
            (-0.18, -0.10, 30), (-0.05, -0.21, -20), (-0.20, 0.08, 70), (-0.06, 0.17, 10), (0.13, 0.17, -40)
        ]
        if p.detailed { beans += [(0.22, 0.05, 80), (-0.08, -0.02, -60), (0.19, -0.17, 20), (0.03, 0.08, 50)] }
        for bean in beans {
            let q = p.moved(bean.0, bean.1, degrees: bean.2)
            q.shape(q.oval(0, 0, 0.05, 0.03), c.sauce, weight: 0.6)
        }
        p.blob([(0.06, -0.06, 0.07), (0.13, -0.02, 0.06), (0.04, 0.0, 0.06)], c.side)
        leaf(p, 0.07, -0.05, size: 0.03, degrees: 20, c.garnish)
        if p.detailed { leaf(p, 0.12, 0.0, size: 0.028, degrees: -40, c.garnish) }
        p.outline(inside, weight: 0.7)
    }

    static func meatballs(_ p: DishPainter, _ c: DishPalette) {
        drawPlate(p)
        if c.side == DishColor.rice {
            starchSide(p, c.side, x: 0.15, y: 0.13)
        } else {
            p.blob([(0.15, 0.10, 0.09), (0.21, 0.16, 0.07), (0.09, 0.17, 0.07)], c.side)
        }
        peas(p, c.garnish, around: (-0.06, 0.21))
        p.blob([(-0.08, -0.06, 0.15), (0.04, -0.10, 0.11), (-0.15, 0.05, 0.10)], c.sauce)
        let balls: [(CGFloat, CGFloat, CGFloat)] = [
            (-0.13, -0.10, 0.065), (0.01, -0.13, 0.065), (-0.17, 0.04, 0.06), (0.07, -0.03, 0.06), (-0.05, -0.01, 0.065)
        ]
        for ball in balls {
            p.shape(p.circle(ball.0, ball.1, ball.2), c.main)
            if p.detailed {
                p.shape(p.circle(ball.0 - 0.022, ball.1 - 0.022, 0.014), DishColor.well.opacity(0.45), weight: 0)
            }
        }
    }

    static func burger(_ p: DishPainter, _ c: DishPalette) {
        drawPlate(p)
        p.shape(p.box(0, 0.135, 0.42, 0.08, corner: 0.035), c.main)
        p.shape(p.box(0, 0.07, 0.46, 0.075, corner: 0.035), c.sauce)
        p.shape(p.polygon([(-0.22, 0.02), (0.22, 0.02), (0.22, 0.04), (0.09, 0.04), (0.055, 0.08), (0.02, 0.04), (-0.22, 0.04)]), c.garnish, weight: 0.6)
        var lettuce: [(CGFloat, CGFloat, CGFloat)] = []
        for index in 0..<8 {
            let x = -0.21 + CGFloat(index) * 0.06
            lettuce.append((x, -0.01, 0.03))
        }
        p.blob(lettuce, c.side, weight: 0.6)
        let dome = p.closed(p.arc(0, -0.035, 0.235, 0.17, from: 180, to: 360))
        p.shape(dome, c.main)
        if p.detailed {
            let seeds: [(CGFloat, CGFloat, Double)] = [(-0.10, -0.12, -20), (0.0, -0.16, 10), (0.10, -0.11, 30), (-0.04, -0.08, -40), (0.06, -0.07, 0)]
            for seed in seeds {
                let q = p.moved(seed.0, seed.1, degrees: seed.2)
                q.shape(q.oval(0, 0, 0.016, 0.008), DishColor.well, weight: 0)
            }
        }
    }

    static func sausages(_ p: DishPainter, _ c: DishPalette) {
        drawPlate(p)
        p.blob([(0.10, 0.12, 0.09), (0.18, 0.09, 0.075), (0.15, 0.19, 0.07)], c.side)
        peas(p, c.garnish, around: (-0.15, 0.17))
        let links: [(CGFloat, CGFloat)] = [(-0.04, -0.12), (-0.08, 0.01)]
        for link in links {
            let q = p.moved(link.0, link.1, degrees: -18)
            q.shape(q.box(0, 0, 0.44, 0.10, corner: 0.05), c.main)
            let marks: [CGFloat] = p.detailed ? [-0.1, 0.0, 0.1] : [-0.05, 0.07]
            for x in marks {
                q.pen(q.segment((x - 0.02, -0.025), (x + 0.02, 0.025)), c.sauce, width: 0.9)
            }
        }
    }

    static func roastChicken(_ p: DishPainter, _ c: DishPalette) {
        drawPlate(p)
        starchSide(p, c.side, x: -0.13, y: 0.17)
        let carrots: [(CGFloat, CGFloat, Double)] = [(0.23, -0.03, 70), (0.15, -0.05, 100)]
        for carrot in carrots {
            let q = p.moved(carrot.0, carrot.1, degrees: carrot.2)
            q.shape(q.oval(0, 0, 0.06, 0.024), c.garnish, weight: 0.6)
        }
        drumstick(p.moved(-0.06, -0.10, degrees: -25), c.main)
        drumstick(p.moved(0.02, 0.07, degrees: 20), c.main)
        if p.detailed { leaf(p, -0.24, -0.02, size: 0.04, degrees: 60, c.sauce) }
    }

    static func drumstick(_ p: DishPainter, _ color: Color) {
        p.shape(p.circle(0.25, -0.022, 0.027), DishColor.well, weight: 0.6)
        p.shape(p.circle(0.25, 0.022, 0.027), DishColor.well, weight: 0.6)
        p.shape(p.box(0.17, 0, 0.16, 0.045, corner: 0.02), DishColor.well, weight: 0.6)
        let taper = p.polygon([(0.06, -0.075), (0.14, -0.03), (0.14, 0.03), (0.06, 0.075)])
        let meat = p.oval(-0.02, 0, 0.15, 0.105)
        p.outline(taper, weight: 1.6)
        p.outline(meat, weight: 1.6)
        p.shape(taper, color, weight: 0)
        p.shape(meat, color, weight: 0)
    }

    static func steak(_ p: DishPainter, _ c: DishPalette) {
        drawPlate(p)
        starchSide(p, c.side, x: 0.12, y: 0.17)
        let garnish: [(CGFloat, CGFloat, Double)] = [(-0.20, 0.12, 30), (-0.14, 0.17, 50), (-0.22, 0.19, 10)]
        for item in garnish {
            let q = p.moved(item.0, item.1, degrees: item.2)
            if c.garnish == DishColor.apple {
                let slice = q.closed(q.arc(0, 0.02, 0.05, 0.04, from: 180, to: 360))
                q.shape(slice, c.garnish, weight: 0.6)
            } else {
                q.shape(q.box(0, 0, 0.11, 0.028, corner: 0.014), c.garnish, weight: 0.6)
            }
        }
        let chop = p.moved(-0.03, -0.07, degrees: -12)
        chop.shape(chop.box(0, -0.02, 0.42, 0.27, corner: 0.12), DishColor.cream)
        chop.shape(chop.box(0, 0.005, 0.40, 0.235, corner: 0.11), c.main)
        let marks: [CGFloat] = p.detailed ? [-0.10, 0.0, 0.10] : [-0.05, 0.06]
        for x in marks {
            chop.pen(chop.segment((x - 0.05, -0.07), (x + 0.05, 0.08)), c.sauce, width: 1.1)
        }
    }

    static func salad(_ p: DishPainter, _ c: DishPalette) {
        let inside = drawBowl(p, c.main)
        let food = p.clipped(to: inside)
        var leaves: [(CGFloat, CGFloat, Double, CGFloat)] = [
            (-0.15, -0.12, 30, 0.13), (0.12, -0.16, -40, 0.12), (0.18, 0.08, 70, 0.12), (-0.05, 0.18, -10, 0.13)
        ]
        if p.detailed { leaves += [(-0.20, 0.08, 100, 0.11), (0.02, -0.01, 15, 0.12)] }
        for item in leaves {
            leaf(food, item.0, item.1, size: item.3, degrees: item.2, c.main)
            if p.detailed {
                let q = food.moved(item.0, item.1, degrees: item.2)
                q.outline(q.segment((-item.3 * 0.7, 0), (item.3 * 0.7, 0)), weight: 0.4)
            }
        }
        let reds: [(CGFloat, CGFloat)] = [(0.07, -0.07), (-0.12, 0.04)]
        for red in reds {
            food.shape(food.circle(red.0, red.1, 0.05), c.sauce, weight: 0.6)
        }
        let slices: [(CGFloat, CGFloat)] = [(0.10, 0.13), (-0.08, -0.18)]
        for slice in slices {
            food.shape(food.circle(slice.0, slice.1, 0.05), c.side, weight: 0.6)
            if p.detailed { food.pen(food.circle(slice.0, slice.1, 0.03), DishColor.green, width: 0.4) }
        }
        var bits: [(CGFloat, CGFloat, Double)] = [(-0.02, 0.06, 20), (0.18, -0.04, -15)]
        if p.detailed { bits.append((-0.18, -0.03, 40)) }
        for bit in bits {
            let q = food.moved(bit.0, bit.1, degrees: bit.2)
            q.shape(q.box(0, 0, 0.065, 0.045, corner: 0.012), c.garnish, weight: 0.6)
        }
        p.outline(inside, weight: 0.7)
    }

    static func grainBowl(_ p: DishPainter, _ c: DishPalette) {
        let inside = drawBowl(p, c.main)
        let food = p.clipped(to: inside)
        if p.detailed {
            for item in scatter {
                food.shape(food.circle(item.0 * 0.28, item.1 * 0.28, 0.009), DishColor.grain, weight: 0)
            }
        }
        let cubes: [(CGFloat, CGFloat, Double)] = [(-0.18, -0.07, 15), (-0.11, 0.06, -20), (-0.22, 0.07, 40)]
        for cube in cubes {
            let q = food.moved(cube.0, cube.1, degrees: cube.2)
            q.shape(q.box(0, 0, 0.06, 0.06, corner: 0.012), c.side, weight: 0.6)
        }
        leaf(food, -0.03, -0.19, size: 0.04, degrees: 20, c.garnish)
        leaf(food, -0.04, 0.2, size: 0.04, degrees: -30, c.garnish)
        let balls: [(CGFloat, CGFloat)] = [(0.08, -0.09), (0.18, 0.03), (0.06, 0.07)]
        for ball in balls {
            food.shape(food.circle(ball.0, ball.1, 0.075), c.sauce)
            if p.detailed {
                food.shape(food.circle(ball.0 - 0.02, ball.1 - 0.015, 0.01), c.garnish, weight: 0)
                food.shape(food.circle(ball.0 + 0.02, ball.1 + 0.01, 0.01), c.garnish, weight: 0)
            }
        }
        p.outline(inside, weight: 0.7)
    }

    static func rice(_ p: DishPainter, _ c: DishPalette) {
        let inside = drawBowl(p, c.main)
        let food = p.clipped(to: inside)
        if p.detailed {
            grains(food, x: 0, y: 0, spread: 0.27, DishColor.well)
            grains(food.moved(0.04, 0.03, degrees: 90), x: 0, y: 0, spread: 0.2, DishColor.well, count: 12)
        }
        let eggs: [(CGFloat, CGFloat, Double)] = [(-0.12, -0.10, 20), (0.13, 0.02, -30), (-0.04, 0.15, 60)]
        for item in eggs {
            let q = food.moved(item.0, item.1, degrees: item.2)
            q.shape(q.box(0, 0, 0.08, 0.055, corner: 0.02), c.sauce, weight: 0.6)
        }
        var carrots: [(CGFloat, CGFloat)] = [(0.08, -0.15), (-0.18, 0.08)]
        if p.detailed { carrots += [(0.18, 0.15), (-0.02, -0.02)] }
        for item in carrots {
            food.shape(food.box(item.0, item.1, 0.045, 0.045, corner: 0.008), c.side, weight: 0.5)
        }
        var peas: [(CGFloat, CGFloat)] = [(0.02, -0.21), (0.21, -0.08), (-0.20, -0.04)]
        if p.detailed { peas += [(0.06, 0.20), (-0.13, 0.20), (0.04, 0.07)] }
        for item in peas {
            food.shape(food.circle(item.0, item.1, 0.024), c.garnish, weight: 0.5)
        }
        p.outline(inside, weight: 0.7)
    }

    static func omelette(_ p: DishPainter, _ c: DishPalette) {
        drawPlate(p)
        leaf(p, 0.18, 0.18, size: 0.045, degrees: -30, c.garnish)
        if p.detailed { leaf(p, 0.09, 0.23, size: 0.04, degrees: 20, c.garnish) }
        let o = p.moved(-0.03, -0.01, degrees: -12)
        o.blob([(-0.12, 0.075, 0.04), (0.0, 0.085, 0.045), (0.12, 0.075, 0.04)], c.side, weight: 0.6)
        let half = o.closed(o.arc(0, 0.07, 0.27, 0.25, from: 180, to: 360))
        o.shape(half, c.main)
        let crust = o.clipped(to: half)
        var spots: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(-0.08, -0.04, 0.045, 0.025), (0.09, -0.08, 0.04, 0.022)]
        if p.detailed { spots += [(0.12, 0.02, 0.035, 0.02), (-0.15, 0.03, 0.03, 0.018), (0.0, -0.13, 0.03, 0.018)] }
        for spot in spots {
            crust.shape(crust.oval(spot.0, spot.1, spot.2, spot.3), c.sauce, weight: 0)
        }
        o.outline(half)
    }

    static func porridge(_ p: DishPainter, _ c: DishPalette) {
        let inside = drawBowl(p, c.main)
        let food = p.clipped(to: inside)
        if p.detailed {
            for item in scatter {
                let q = food.moved(item.0 * 0.26, item.1 * 0.26, degrees: item.2)
                q.shape(q.oval(0, 0, 0.012, 0.006), c.side, weight: 0)
            }
        }
        food.shape(food.circle(0.02, -0.02, 0.075), c.sauce, weight: 0.6)
        if c.garnish != c.side {
            let berries: [(CGFloat, CGFloat)] = [(-0.15, 0.12), (-0.08, 0.17), (-0.19, 0.04)]
            for berry in berries {
                food.shape(food.circle(berry.0, berry.1, 0.035), c.garnish, weight: 0.6)
            }
        } else if !p.detailed {
            let dashes: [(CGFloat, CGFloat)] = [(-0.15, 0.10), (0.15, 0.12), (0.12, -0.16), (-0.14, -0.12)]
            for dash in dashes {
                food.shape(food.circle(dash.0, dash.1, 0.018), c.side, weight: 0)
            }
        }
        p.outline(inside, weight: 0.7)
    }

    static func pancakes(_ p: DishPainter, _ c: DishPalette) {
        drawPlate(p)
        var layers: [CGFloat] = [0.10, 0.04, -0.02]
        if p.detailed { layers.append(-0.08) }
        for y in layers {
            p.shape(p.oval(-0.02, y, 0.26, 0.085), c.main)
        }
        let topY = layers[layers.count - 1]
        p.blob([(-0.06, topY - 0.005, 0.045), (-0.01, topY + 0.01, 0.04)], c.sauce, weight: 0.6)
        let pat = p.moved(0.08, topY - 0.01, degrees: -10)
        pat.shape(pat.box(0, 0, 0.065, 0.045, corner: 0.01), c.garnish, weight: 0.6)
        let strips: [CGFloat] = [0.21, 0.27]
        for y in strips {
            let start = p.point(-0.12, y)
            let end = p.point(0.17, y - 0.02)
            let first = p.point(-0.02, y - 0.05)
            let second = p.point(0.07, y + 0.04)
            let strip = Path { path in
                path.move(to: start)
                path.addCurve(to: end, control1: first, control2: second)
            }
            p.band(strip, c.side, width: 2.0)
        }
    }

    static func plainPlate(_ p: DishPainter, _ c: DishPalette) {
        drawPlate(p)
        starchSide(p, c.side, x: 0.12, y: 0.15)
        p.blob([(-0.19, 0.10, 0.055), (-0.13, 0.15, 0.055), (-0.21, 0.17, 0.05)], c.garnish)
        let m = p.moved(-0.03, -0.07, degrees: -10)
        m.shape(m.box(0, 0, 0.34, 0.20, corner: 0.08), c.main)
        let start = m.point(-0.11, 0.0)
        let end = m.point(0.11, 0.0)
        let first = m.point(-0.04, -0.06)
        let second = m.point(0.04, 0.06)
        let drizzle = Path { path in
            path.move(to: start)
            path.addCurve(to: end, control1: first, control2: second)
        }
        m.pen(drizzle, c.sauce, width: 1.2)
    }
}

// MARK: - Preview

#Preview("Dish forms") {
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 12)], spacing: 16) {
            ForEach(DishForm.allCases, id: \.self) { form in
                VStack(spacing: 6) {
                    DishIllustration(form: form)
                        .frame(width: 132, height: 132)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    HStack(spacing: 8) {
                        DishIllustration(form: form)
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        DishIllustration(form: form)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    Text(verbatim: form.rawValue)
                        .font(.caption2)
                }
            }
        }
        .padding()
    }
}

#Preview("Built-in meals") {
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 12) {
            ForEach(SampleMeals.all) { meal in
                VStack(spacing: 4) {
                    DishIllustration(meal: meal)
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text(verbatim: meal.name)
                        .font(.caption2)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding()
    }
}
