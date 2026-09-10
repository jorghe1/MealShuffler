import XCTest
@testable import MealShuffler

/// The four ways a recipe gets into the library, and the shapes real pages come in.
///
/// Import used to arrive with a title and an empty shopping list. Each test here is one of
/// the reasons why.
final class RecipeParsingTests: XCTestCase {

    private func page(_ jsonLD: String) -> String {
        "<html><head><script type=\"application/ld+json\">\(jsonLD)</script></head><body></body></html>"
    }

    // MARK: - JSON-LD shapes

    /// Instructions grouped into sections are what most modern recipe sites emit. Reading
    /// `text` off each element found nothing at all in them.
    func testInstructionsAreReadOutOfSections() {
        let value: Any = [
            ["@type": "HowToSection", "name": "Sauce", "itemListElement": [
                ["@type": "HowToStep", "text": "Fry the onion."],
                ["@type": "HowToStep", "text": "Add the tomatoes."]
            ]],
            ["@type": "HowToSection", "name": "Pasta", "itemListElement": [
                ["@type": "HowToStep", "text": "Boil the pasta."]
            ]]
        ]
        let steps = RecipeImportService.parseInstructions(value)
        XCTAssertEqual(steps, ["Fry the onion.", "Add the tomatoes.", "Boil the pasta."])
    }

    func testInstructionsStillWorkAsPlainStringsAndSteps() {
        XCTAssertEqual(RecipeImportService.parseInstructions("Just do it."), ["Just do it."])
        XCTAssertEqual(RecipeImportService.parseInstructions(["One.", "Two."]), ["One.", "Two."])
        XCTAssertEqual(
            RecipeImportService.parseInstructions([["@type": "HowToStep", "text": "One."]]),
            ["One."]
        )
    }

    /// Ingredients were only ever read as `[String]`. Every other shape produced an empty
    /// list, which is exactly "only the name was extracted".
    func testIngredientsAreReadInEveryShapeSitesUse() {
        XCTAssertEqual(
            RecipeImportService.parseIngredients(["200 g rice", "1 onion"]),
            ["200 g rice", "1 onion"]
        )
        XCTAssertEqual(
            RecipeImportService.parseIngredients([["name": "200 g rice"], ["text": "1 onion"]]),
            ["200 g rice", "1 onion"]
        )
        XCTAssertEqual(
            RecipeImportService.parseIngredients("200 g rice\n1 onion"),
            ["200 g rice", "1 onion"]
        )
        XCTAssertTrue(RecipeImportService.parseIngredients(nil).isEmpty)
    }

    /// The traversal walked `dictionary.values`, whose order Swift does not define, so a page
    /// with related-recipe cards imported a different recipe on different runs.
    func testTheRichestRecipeOnThePageWinsAndIsStable() throws {
        let html = page("""
        {"@context":"https://schema.org","@graph":[
          {"@type":"Recipe","name":"Related teaser","recipeIngredient":["1 thing"]},
          {"@type":"WebPage","name":"Some page"},
          {"@type":"Recipe","name":"The real one",
           "recipeIngredient":["200 g rice","1 onion","2 carrots"],
           "recipeInstructions":[{"@type":"HowToStep","text":"Cook."}]}
        ]}
        """)
        let names = (0..<12).map { _ in
            RecipeImportService.extractRecipeObject(from: html)?["name"] as? String
        }
        XCTAssertEqual(Set(names.compactMap { $0 }), ["The real one"], "Selection must be stable")
    }

    // MARK: - Microdata

    /// Only JSON-LD was ever read, so a page carrying its recipe as attributes reported that
    /// no structured recipe was found.
    func testMicrodataIsReadWhenThereIsNoJSONLD() throws {
        let html = """
        <html><body><h2 itemprop="name">Publisher name</h2><article itemscope itemtype="https://schema.org/Recipe">
          <h1 itemprop="name">Fiskegrateng</h1>
          <li itemprop="recipeIngredient">600 g torskefilet</li>
          <li itemprop="recipeIngredient">4 dl melk</li>
          <div itemprop="recipeInstructions">Sett ovnen på 200 grader.</div>
        </article></body></html>
        """
        let url = try XCTUnwrap(URL(string: "https://example.com/oppskrift"))
        let draft = try RecipeImportService.microdataDraft(html: html, url: url, heroImage: nil)

        XCTAssertEqual(draft.name, "Fiskegrateng")
        XCTAssertEqual(draft.ingredientLines.count, 2)
        XCTAssertFalse(draft.instructions.isEmpty)
    }

    func testMicrodataWithoutIngredientsIsNotARecipe() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/x"))
        XCTAssertThrowsError(
            try RecipeImportService.microdataDraft(html: "<html><body>nothing</body></html>", url: url, heroImage: nil)
        )
    }

    // MARK: - What an import is worth once it lands

    /// An untagged import is invisible to every rule the household has written.
    func testAnImportedRecipeArrivesTaggedAndWithAFace() {
        let tags = RecipeClassifier.tags(name: "Ovnsbakt laks", ingredients: ["Laksefilet", "Poteter"])
        XCTAssertTrue(tags.contains(.fish))
        XCTAssertEqual(RecipeClassifier.emoji(for: tags), "🐟")

        let pasta = RecipeClassifier.tags(name: "Spaghetti bolognese", ingredients: ["Kjøttdeig", "Spaghetti"])
        XCTAssertTrue(pasta.contains(.pasta))
        XCTAssertTrue(pasta.contains(.meat))
        XCTAssertFalse(pasta.contains(.vegetarian), "Mince is not vegetarian")

        XCTAssertEqual(RecipeClassifier.emoji(for: []), "🍽️")
    }

    func testQuickIsClaimedOnlyWhenTheTimeSaysSo() {
        XCTAssertTrue(RecipeClassifier.tags(name: "Suppe", ingredients: [], prepMinutes: 20).contains(.quick))
        XCTAssertFalse(RecipeClassifier.tags(name: "Suppe", ingredients: [], prepMinutes: 60).contains(.quick))
    }

    func testASubtitleIsOneLineNotAMarketingParagraph() {
        let long = String(repeating: "Very long blurb about this dish. ", count: 12)
        let subtitle = RecipeImportService.shortSubtitle(long, fallback: "example.com")
        XCTAssertLessThanOrEqual(subtitle.count, 95)
        XCTAssertEqual(RecipeImportService.shortSubtitle(nil, fallback: "example.com"), "example.com")
        XCTAssertEqual(RecipeImportService.shortSubtitle("   ", fallback: "example.com"), "example.com")
    }

    // MARK: - Pasted text

    /// This was the one path that genuinely required the service, so with none deployed it
    /// answered with an error rather than a recipe.
    func testPastedTextBecomesADraftWithNoServiceAtAll() throws {
        let pasted = """
        Tomatsuppe med egg

        Ingredienser
        3 boks hermetiske tomater
        4 stk egg
        2 dl matfløte

        Slik gjør du
        1. Kok opp tomatene.
        2. Rør inn fløten.
        """
        let draft = try RecipeTextStructurer.draft(fromPastedText: pasted)
        XCTAssertEqual(draft.name, "Tomatsuppe med egg")
        XCTAssertEqual(draft.ingredientLines.count, 3)
        XCTAssertEqual(draft.instructions.count, 2)
        XCTAssertTrue(draft.needsReview, "A guess should always be reviewed")
        XCTAssertFalse(draft.tags.isEmpty, "An import with no tags cannot satisfy a rule")
    }

    func testPastedRubbishIsRefusedRatherThanSavedEmpty() {
        XCTAssertThrowsError(try RecipeTextStructurer.draft(fromPastedText: "hello"))
    }

    // MARK: - Scanned pages

    /// Vision returns observations in no guaranteed order, and the structurer reads its input
    /// as a document. Without position, a two-column page interleaves and every assumption
    /// about headings and ordering breaks.
    func testScannedLinesAreReadInPageOrderNotVisionOrder() throws {
        typealias Line = RecipeOCRService.RecognisedLine
        // Deliberately shuffled, and with the title in the middle of the array.
        let lines = [
            Line(text: "2. Rør inn fløten.", top: 0.72, left: 0.1, height: 0.02),
            Line(text: "Ingredienser", top: 0.30, left: 0.1, height: 0.03),
            Line(text: "Tomatsuppe med egg", top: 0.08, left: 0.1, height: 0.09),
            Line(text: "4 stk egg", top: 0.42, left: 0.1, height: 0.02),
            Line(text: "Slik gjør du", top: 0.58, left: 0.1, height: 0.03),
            Line(text: "3 boks hermetiske tomater", top: 0.36, left: 0.1, height: 0.02),
            Line(text: "1. Kok opp tomatene.", top: 0.66, left: 0.1, height: 0.02)
        ]
        let draft = try RecipeOCRService.draft(from: lines)

        XCTAssertEqual(draft.name, "Tomatsuppe med egg", "The largest text at the top is the title")
        XCTAssertEqual(draft.ingredientLines.count, 2)
        XCTAssertEqual(draft.instructions.count, 2)
    }

    /// On a screenshot the topmost line is the status bar or the site's navigation, so the
    /// first line is the worst possible guess at the title.
    func testAScreenshotsChromeIsNotMistakenForTheTitle() throws {
        typealias Line = RecipeOCRService.RecognisedLine
        let lines = [
            Line(text: "09:41", top: 0.01, left: 0.05, height: 0.012),
            Line(text: "matprat.no", top: 0.04, left: 0.30, height: 0.014),
            Line(text: "Fiskegrateng", top: 0.15, left: 0.08, height: 0.08),
            Line(text: "Ingredienser", top: 0.30, left: 0.08, height: 0.03),
            Line(text: "600 g torskefilet", top: 0.36, left: 0.08, height: 0.02),
            Line(text: "4 dl melk", top: 0.40, left: 0.08, height: 0.02)
        ]
        let draft = try RecipeOCRService.draft(from: lines)
        XCTAssertEqual(draft.name, "Fiskegrateng")
    }

    /// A recipe spread over two pages keeps its order across them.
    func testPagesKeepTheirOrderWhenStitched() {
        typealias Line = RecipeOCRService.RecognisedLine
        let first = Line(text: "later on page one", top: 0.9, left: 0, height: 0.02)
        let second = Line(text: "early on page two", top: 0.1, left: 0, height: 0.02).onPage(1)
        XCTAssertLessThan(first.top, second.top)
    }
}
