import XCTest
@testable import MealShuffler

/// Covers the two import paths that this review found writing rubbish into people's
/// libraries, plus the parsing they feed.
final class RecipeImportTests: XCTestCase {

    // MARK: - Photo import

    /// The exact page shape that previously produced 5 real ingredients and 12 junk rows,
    /// including instruction steps whose step numbers were read as quantities.
    private let cookbookPage = [
        "Creamy Chicken Pasta",
        "Serves 4",
        "Prep 15 min · Cook 15 min",
        "INGREDIENTS",
        "500 g chicken breast",
        "400 g pasta",
        "3 dl cooking cream",
        "200 g spinach",
        "100 g parmesan, grated",
        "2 cloves garlic",
        "salt and pepper",
        "METHOD",
        "1. Bring a large pot of salted water to a boil.",
        "2. Season the chicken and fry over medium-high heat for 6 minutes.",
        "3. Add the cream and simmer until slightly thickened.",
        "4. Toss with the drained pasta and serve immediately.",
        "Tip: swap the spinach for kale in winter.",
        "Photography by Anna Berg",
        "78"
    ]

    func testScannedPageSeparatesIngredientsFromEverythingElse() {
        let result = RecipeTextStructurer.structure(lines: cookbookPage)

        XCTAssertEqual(result.title, "Creamy Chicken Pasta")
        XCTAssertEqual(result.ingredientLines, [
            "500 g chicken breast",
            "400 g pasta",
            "3 dl cooking cream",
            "200 g spinach",
            "100 g parmesan, grated",
            "2 cloves garlic",
            "salt and pepper"
        ])
        XCTAssertEqual(result.instructions.count, 4)
        XCTAssertEqual(result.instructions.first, "Bring a large pot of salted water to a boil.")

        // None of the page furniture may reach the shopping list.
        let joined = result.ingredientLines.joined(separator: " | ")
        for leak in ["Serves", "Prep", "INGREDIENTS", "METHOD", "Photography", "78", "Tip:"] {
            XCTAssertFalse(joined.contains(leak), "\(leak) leaked into the ingredients")
        }
    }

    func testInstructionStepNumbersAreNotParsedAsQuantities() {
        let result = RecipeTextStructurer.structure(lines: cookbookPage)
        let parsed = IngredientParser.parse(lines: result.ingredientLines)
        XCTAssertFalse(parsed.contains { $0.name.lowercased().contains("season the chicken") })
        XCTAssertFalse(parsed.contains { $0.name.lowercased().contains("simmer") })
    }

    func testNorwegianScannedPageIsStructured() {
        let result = RecipeTextStructurer.structure(lines: [
            "Fiskegrateng", "4 porsjoner", "INGREDIENSER",
            "600 g torskefilet", "4 dl melk", "2 ss smør", "salt og pepper",
            "SLIK GJØR DU",
            "1. Sett stekeovnen på 200 grader.",
            "2. Hell over fisken og stek i 25 minutter til den er gyllen.",
            "Foto: Kari Nordli"
        ])
        XCTAssertEqual(result.title, "Fiskegrateng")
        XCTAssertEqual(result.ingredientLines.count, 4)
        XCTAssertEqual(result.instructions.count, 2)
        XCTAssertFalse(result.ingredientLines.contains { $0.contains("porsjoner") })
    }

    func testUnlabelledPhotoKeepsIngredientsOnly() {
        let result = RecipeTextStructurer.structure(lines: [
            "Tomatsuppe", "3 boks hakkede tomater", "4 stk egg", "2 dl matfløte", "1 stk gul løk"
        ])
        XCTAssertEqual(result.title, "Tomatsuppe")
        XCTAssertEqual(result.ingredientLines.count, 4)
        XCTAssertTrue(result.instructions.isEmpty)
    }

    // MARK: - Aisle inference

    func testAisleInferenceHandlesWordsThatContainOtherWords() {
        let cases: [(String, GroceryAisle)] = [
            ("Coconut milk", .pantry),          // not dairy
            ("Egg noodles", .pantry),           // not dairy
            ("Butternut squash", .produce),     // not butter
            ("Peanut butter", .pantry),
            ("Chicken stock", .pantry),         // not the meat counter
            ("Parmesan, grated", .dairy),       // previously fell through to pantry
            ("Chicken breast", .meatAndFish),
            ("Whole milk", .dairy),
            ("Yellow onion", .produce),
            ("Frozen peas", .frozen)
        ]
        for (name, expected) in cases {
            let parsed = IngredientParser.parse("500 g \(name)")
            XCTAssertEqual(parsed?.aisle, expected, "\(name) should be filed under \(expected.rawValue)")
        }
    }

    // MARK: - Link import

    func testHTMLDecodingFallsBackFromUTF8ToLatin1() throws {
        // "Fiskegrateng med løk" in ISO-8859-1 is not valid UTF-8.
        let latin1 = try XCTUnwrap("Fiskegrateng med løk".data(using: .isoLatin1))
        XCTAssertNil(String(data: latin1, encoding: .utf8), "precondition: not valid UTF-8")

        let decoded = RecipeImportService.decodeHTML(latin1, response: nil)
        XCTAssertEqual(decoded, "Fiskegrateng med løk")
    }

    func testEntityDecodingDoesNotDoubleUnescape() {
        XCTAssertEqual(RecipeImportService.decodingEntities("a &quot;b&quot; c"), "a \"b\" c")
        XCTAssertEqual(RecipeImportService.decodingEntities("Salt &amp; pepper"), "Salt & pepper")
        // &amp;quot; is a literal "&quot;", not a quote character.
        XCTAssertEqual(RecipeImportService.decodingEntities("&amp;quot;"), "&quot;")
    }
}
