import XCTest
@testable import MealShuffler

/// Covers the Phase 7 capture path: what the share extension leaves behind, and how the
/// extraction service's response becomes a reviewable draft.
final class CaptureTests: XCTestCase {

    // MARK: - Inbox

    override func tearDown() {
        RecipeInbox.removeAll()
        super.tearDown()
    }

    func testInboxRoundTripsALink() throws {
        RecipeInbox.removeAll()
        let url = try XCTUnwrap(URL(string: "https://example.com/fiskegrateng"))
        RecipeInbox.add(CapturedRecipe(url: url))

        let pending = RecipeInbox.all()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.url, url)
        XCTAssertEqual(pending.first?.summary, "example.com")
    }

    func testInboxKeepsCapturesInTheOrderTheyArrived() {
        RecipeInbox.removeAll()
        let first = CapturedRecipe(capturedAt: .now.addingTimeInterval(-60), text: "older")
        let second = CapturedRecipe(capturedAt: .now, text: "newer")
        RecipeInbox.add(second)
        RecipeInbox.add(first)

        XCTAssertEqual(RecipeInbox.all().map(\.id), [first.id, second.id])
    }

    func testRemovingACaptureLeavesTheOthers() {
        RecipeInbox.removeAll()
        let keep = CapturedRecipe(text: "keep")
        let drop = CapturedRecipe(text: "drop")
        RecipeInbox.add(keep)
        RecipeInbox.add(drop)

        RecipeInbox.remove(drop.id)
        XCTAssertEqual(RecipeInbox.all().map(\.id), [keep.id])
    }

    func testStoredImageIsReadableBackThroughTheCapture() throws {
        RecipeInbox.removeAll()
        let bytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02, 0x03])
        let filename = try XCTUnwrap(RecipeInbox.storeImage(bytes),
                                     "Needs the App Group container; skipped without the entitlement")
        RecipeInbox.add(CapturedRecipe(imageFilename: filename))

        let capture = try XCTUnwrap(RecipeInbox.all().first)
        XCTAssertEqual(capture.imageData, bytes)
    }

    // MARK: - Service response

    /// A response shaped exactly as `server/src/index.ts` returns it.
    private let serviceResponse = Data("""
    {
      "name": "Fiskegrateng",
      "subtitle": "Med gulrotsalat",
      "emoji": "🐟",
      "prepMinutes": 40,
      "servings": 4,
      "ingredients": [
        { "name": "Torskefilet", "quantity": 600, "unit": "g", "aisle": "meatAndFish" },
        { "name": "Melk", "quantity": 4, "unit": "dl", "aisle": "dairy" },
        { "name": "Salt og pepper", "quantity": null, "unit": "", "aisle": "pantry" }
      ],
      "instructions": ["Sett stekeovnen på 200 grader.", "Stek i 25 minutter."],
      "tags": ["fish"],
      "confidence": "high",
      "heroImageURL": "https://example.com/hero.jpg"
    }
    """.utf8)

    func testServiceResponseBecomesADraft() async throws {
        let session = URLSession.stubbed(returning: serviceResponse, status: 200)
        let extractor = RemoteRecipeExtractor(
            configuration: .init(baseURL: try XCTUnwrap(URL(string: "https://example.invalid"))),
            session: session
        )

        let url = try XCTUnwrap(URL(string: "https://matsted.no/fiskegrateng"))
        let draft = try await extractor.extract(from: url)

        XCTAssertEqual(draft.name, "Fiskegrateng")
        XCTAssertEqual(draft.prepMinutes, 40)
        XCTAssertEqual(draft.servings, 4)
        XCTAssertEqual(draft.instructions.count, 2)
        XCTAssertEqual(draft.heroImageURL?.absoluteString, "https://example.com/hero.jpg")
        XCTAssertFalse(draft.needsReview, "High confidence should not demand review")

        // Tags come through, so an imported recipe is immediately visible to rules like
        // "fish on Tuesday" -- which local imports could never satisfy.
        XCTAssertEqual(draft.tags, [.fish])

        // Ingredient lines are rendered for the editor, and an amount-less item stays bare.
        XCTAssertEqual(draft.ingredientLines, ["600 g Torskefilet", "4 dl Melk", "Salt og pepper"])
    }

    func testLowConfidenceAsksForReview() async throws {
        let lowered = String(data: serviceResponse, encoding: .utf8)!
            .replacingOccurrences(of: "\"confidence\": \"high\"", with: "\"confidence\": \"low\"")
        let session = URLSession.stubbed(returning: Data(lowered.utf8), status: 200)
        let extractor = RemoteRecipeExtractor(
            configuration: .init(baseURL: try XCTUnwrap(URL(string: "https://example.invalid"))),
            session: session
        )
        let draft = try await extractor.extract(from: try XCTUnwrap(URL(string: "https://a.no/b")))
        XCTAssertTrue(draft.needsReview)
    }

    func testServiceErrorMessageReachesTheUser() async throws {
        let body = Data(#"{"error":"That page could not be opened."}"#.utf8)
        let session = URLSession.stubbed(returning: body, status: 502)
        let extractor = RemoteRecipeExtractor(
            configuration: .init(baseURL: try XCTUnwrap(URL(string: "https://example.invalid"))),
            session: session
        )

        do {
            _ = try await extractor.extract(from: try XCTUnwrap(URL(string: "https://a.no/b")))
            XCTFail("Expected the service error to surface")
        } catch {
            // The service explains itself; a status code would not.
            XCTAssertEqual(error.localizedDescription, "That page could not be opened.")
        }
    }

    func testNonHTTPSLinksAreRejectedBeforeAnyRequest() async throws {
        let extractor = RemoteRecipeExtractor(
            configuration: .init(baseURL: try XCTUnwrap(URL(string: "https://example.invalid"))),
            session: .stubbed(returning: Data(), status: 200)
        )
        do {
            _ = try await extractor.extract(from: try XCTUnwrap(URL(string: "http://insecure.no/x")))
            XCTFail("Expected an invalid URL error")
        } catch {
            XCTAssertEqual(error as? RecipeImportError, .invalidURL)
        }
    }

    func testRemoteIsOffWhenNoServiceURLIsConfigured() {
        // The shipped Info.plist deliberately carries an empty string, so the app stays on
        // its on-device parser until the service is actually deployed.
        let bundle = Bundle(for: type(of: self))
        let configuration = RemoteRecipeExtractor.Configuration.fromBundle(bundle)
        XCTAssertNil(configuration)
    }
}

// MARK: - URLSession stub

private final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var status = 200

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: Self.status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension URLSession {
    static func stubbed(returning body: Data, status: Int) -> URLSession {
        StubProtocol.body = body
        StubProtocol.status = status
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: configuration)
    }
}

extension RecipeImportError: Equatable {
    public static func == (lhs: RecipeImportError, rhs: RecipeImportError) -> Bool {
        lhs.localizedDescription == rhs.localizedDescription
    }
}
