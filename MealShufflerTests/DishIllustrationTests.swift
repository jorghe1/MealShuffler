import XCTest
@testable import MealShuffler

/// Which drawing a dish gets when it has no photo.
///
/// The category photographs these replaced were "realistic and wrong": chili con carne showed
/// meatballs, a veggie burger a quinoa bowl. These tests pin the dish *form* for the built-in
/// library, in both languages, so a new keyword cannot quietly turn a soup into noodles.
final class DishIllustrationTests: XCTestCase {
    private func meal(_ englishName: String) -> Meal? {
        SampleMeals.all.first { $0.name == L10n.string(englishName) }
    }

    func testEveryBuiltInMealHasARealDishForm() {
        for meal in SampleMeals.all {
            XCTAssertNotEqual(DishForm.form(for: meal), .plate, "\(meal.name) fell back to a plain plate")
        }
    }

    func testBuiltInSpotChecks() {
        let expected: [(String, DishForm)] = [
            ("Chili con carne", .stew),
            ("Vegetarian chili", .stew),
            ("Fish gratin", .casserole),
            ("Shepherd's pie", .casserole),
            ("Butter chicken", .curry),
            ("Lentil curry", .curry),
            ("Thai red curry with chicken", .curry),
            ("Veggie burger", .burger),
            ("Beef burgers", .burger),
            ("Lasagne", .lasagne),
            ("Fish tacos", .taco),
            ("Taco", .taco),
            ("Tomato soup with egg", .soup),
            ("Cauliflower soup", .soup),
            ("Chicken noodle soup", .soup),
            ("Chicken stir-fry", .noodles),
            ("Fried rice with egg", .rice),
            ("Meatballs in tomato sauce", .meatballs),
            ("Fish cakes with potatoes", .fishCakes),
            ("Baked salmon with roasted vegetables", .fishFillet),
            ("Teriyaki salmon with rice", .fishFillet),
            ("Pan-fried cod with potatoes", .fishFillet),
            ("Chicken fajitas", .wrap),
            ("Chicken pita", .wrap),
            ("Halloumi wraps", .wrap),
            ("Tuna pasta salad", .salad),
            ("Carbonara", .pasta),
            ("Margherita pizza", .pizza),
            ("Sausages with mashed potatoes", .sausages),
            ("Pork chops with apple", .steak),
            ("Roast chicken thighs with potatoes", .roastChicken),
            ("Falafel with couscous", .grainBowl),
            ("Pancakes with bacon", .pancakes)
        ]
        for (name, form) in expected {
            guard let meal = meal(name) else {
                XCTFail("Built-in meal \(name) is missing")
                continue
            }
            XCTAssertEqual(DishForm.form(for: meal), form, name)
        }
    }

    func testNorwegianNamesPickTheSameDish() {
        XCTAssertEqual(DishForm.form(name: "Kyllingsuppe med nudler", tags: []), .soup)
        XCTAssertEqual(DishForm.form(name: "Kjøttboller i tomatsaus", tags: []), .meatballs)
        XCTAssertEqual(DishForm.form(name: "Kjøttkaker i brun saus", tags: []), .meatballs)
        XCTAssertEqual(DishForm.form(name: "Fiskegrateng", tags: []), .casserole)
        XCTAssertEqual(DishForm.form(name: "Kyllingwok", tags: []), .noodles)
        XCTAssertEqual(DishForm.form(name: "Risgrøt", tags: []), .porridge)
        XCTAssertEqual(DishForm.form(name: "Fårikål", tags: []), .stew)
        XCTAssertEqual(DishForm.form(name: "Stekt ris med egg", tags: []), .rice)
        XCTAssertEqual(DishForm.form(name: "Pølser med potetmos", tags: []), .sausages)
    }

    /// The built-in names as the Norwegian strings file translates them.
    func testEveryBuiltInNorwegianNameMatchesItsEnglishForm() {
        let names: [(String, String)] = [
            ("Baked salmon with roasted vegetables", "Ovnsbakt laks med grønnsaker"),
            ("Fish tacos", "Fisketaco"),
            ("Chicken stir-fry", "Kyllingwok"),
            ("Creamy chicken pasta", "Kremet kyllingpasta"),
            ("Margherita pizza", "Pizza Margherita"),
            ("Taco", "Taco"),
            ("Lentil curry", "Linsecurry"),
            ("Tomato soup with egg", "Tomatsuppe med egg"),
            ("Spaghetti bolognese", "Spagetti bolognese"),
            ("Cauliflower soup", "Blomkålsuppe"),
            ("Chicken pita", "Kylling i pita"),
            ("Veggie burger", "Vegetarburger"),
            ("Fish gratin", "Fiskegrateng"),
            ("Meatballs in tomato sauce", "Kjøttboller i tomatsaus"),
            ("Carbonara", "Carbonara"),
            ("Lasagne", "Lasagne"),
            ("Pasta with tomato and basil", "Pasta med tomat og basilikum"),
            ("Chicken fajitas", "Kyllingfajitas"),
            ("Chili con carne", "Chili con carne"),
            ("Butter chicken", "Butter chicken"),
            ("Thai red curry with chicken", "Rød thaicurry med kylling"),
            ("Fried rice with egg", "Stekt ris med egg"),
            ("Teriyaki salmon with rice", "Teriyakilaks med ris"),
            ("Beef burgers", "Hamburgere"),
            ("Pepperoni pizza", "Pepperonipizza"),
            ("Roast chicken thighs with potatoes", "Kyllinglår med poteter"),
            ("Pan-fried cod with potatoes", "Stekt torsk med poteter"),
            ("Fish cakes with potatoes", "Fiskekaker med poteter"),
            ("Sausages with mashed potatoes", "Pølser med potetmos"),
            ("Pork chops with apple", "Svinekoteletter med eple"),
            ("Chicken noodle soup", "Kyllingsuppe med nudler"),
            ("Minestrone", "Minestrone"),
            ("Halloumi wraps", "Halloumiwraps"),
            ("Falafel with couscous", "Falafel med couscous"),
            ("Pizza with ham and mushroom", "Pizza med skinke og sjampinjong"),
            ("Shepherd's pie", "Kjøttdeigform med potetmos"),
            ("Sweet and sour chicken", "Sursøt kylling"),
            ("Tuna pasta salad", "Pastasalat med tunfisk"),
            ("Vegetarian chili", "Vegetarchili"),
            ("Pancakes with bacon", "Pannekaker med bacon")
        ]
        XCTAssertEqual(names.count, SampleMeals.all.count)
        for (english, norwegian) in names {
            // Names alone, so the language really decides; tags would mask a missing keyword.
            let fromEnglish = DishForm.form(name: english, tags: [])
            XCTAssertNotEqual(fromEnglish, .plate, english)
            XCTAssertEqual(DishForm.form(name: norwegian, tags: []), fromEnglish, norwegian)
        }
    }

    func testShortKeywordsOnlyMatchWholeWords() {
        // "ris" is rice, but not inside "gris" or "pris"; "stek" is a roast, "stekt" is fried.
        XCTAssertNotEqual(DishForm.form(name: "Grillet gris", tags: []), .rice)
        XCTAssertEqual(DishForm.form(name: "Kylling med ris", tags: []), .rice)
        XCTAssertEqual(DishForm.form(name: "Stekt torsk", tags: []), .fishFillet)
    }

    func testFallsBackToTagsThenPlate() {
        XCTAssertEqual(DishForm.form(name: "Mormors søndagsmiddag", tags: [.pizza, .meat]), .pizza)
        XCTAssertEqual(DishForm.form(name: "Mormors søndagsmiddag", tags: [.fish]), .fishFillet)
        XCTAssertEqual(
            DishForm.form(name: "Mormors søndagsmiddag", tags: [], ingredientNames: ["Lasagneplater", "Kjøttdeig"]),
            .lasagne
        )
        XCTAssertEqual(DishForm.form(name: "Mormors søndagsmiddag", tags: [.quick]), .plate)
    }

    func testColoursFollowTheIngredients() {
        guard let salmon = meal("Baked salmon with roasted vegetables"),
              let cod = meal("Pan-fried cod with potatoes"),
              let tomatoSoup = meal("Tomato soup with egg"),
              let cauliflowerSoup = meal("Cauliflower soup"),
              let bolognese = meal("Spaghetti bolognese"),
              let creamy = meal("Creamy chicken pasta") else {
            return XCTFail("Built-in meals are missing")
        }
        XCTAssertEqual(DishPalette(meal: salmon, form: .fishFillet).main, DishColor.salmon)
        XCTAssertEqual(DishPalette(meal: cod, form: .fishFillet).main, DishColor.whiteFish)
        XCTAssertEqual(DishPalette(meal: tomatoSoup, form: .soup).main, DishColor.tomatoSoup)
        XCTAssertEqual(DishPalette(meal: cauliflowerSoup, form: .soup).main, DishColor.cream)
        XCTAssertEqual(DishPalette(meal: bolognese, form: .pasta).sauce, DishColor.tomato)
        XCTAssertEqual(DishPalette(meal: creamy, form: .pasta).sauce, DishColor.creamSauce)
    }
}
