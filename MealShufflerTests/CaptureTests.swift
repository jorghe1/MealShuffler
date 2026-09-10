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
        // The shared container needs the App Groups entitlement, which an unsigned
        // simulator build does not carry. Skip rather than fail: the entitlement is
        // verified on a real device, not here.
        guard let filename = RecipeInbox.storeImage(bytes) else {
            throw XCTSkip("No App Group container in an unsigned build")
        }
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
        XCTAssertTrue(draft.needsReview, "Every extraction must be reviewable, even at high confidence")
        XCTAssertEqual(draft.parsedIngredients?.last?.quantity, 0, "An unstated amount must not become one")
        XCTAssertEqual(draft.parsedIngredients?.first?.aisle, .meatAndFish)

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

    func testServiceErrorCodesReachTheUserAsLocalizedGuidance() async throws {
        let cases: [(code: String, status: Int, message: String)] = [
            ("rate_limited", 429, "Online imports are busy or have reached the service limit. Try again later."),
            ("too_large", 413, "This source is too large. Try fewer photos or a shorter text."),
            ("unreadable_recipe", 422, "The recipe could not be read reliably. Check the source or use on-device recognition."),
            ("invalid_recipe", 502, "The recipe could not be read reliably. Check the source or use on-device recognition.")
        ]
        for item in cases {
            let body = try JSONSerialization.data(withJSONObject: ["code": item.code, "error": "Server diagnostic"])
            try await assertServiceError(body: body, status: item.status, message: L10n.string(item.message))
        }
    }

    func testUnknownAndLegacyServiceErrorsUseLocalizedFallback() async throws {
        for response in [
            ["error": "That page could not be opened."],
            ["code": "future_error_code", "error": "Server diagnostic"]
        ] {
            let body = try JSONSerialization.data(withJSONObject: response)
            try await assertServiceError(body: body, status: 502, message: L10n.string(
                "Online extraction is unavailable. Try again or use on-device recognition."
            ))
        }
    }

    private func assertServiceError(body: Data, status: Int, message: String,
                                    file: StaticString = #filePath, line: UInt = #line) async throws {
        let session = URLSession.stubbed(returning: body, status: status)
        defer { session.invalidateAndCancel() }
        let extractor = RemoteRecipeExtractor(
            configuration: .init(baseURL: try XCTUnwrap(URL(string: "https://example.invalid"))),
            session: session
        )

        do {
            _ = try await extractor.extract(from: try XCTUnwrap(URL(string: "https://a.no/b")))
            XCTFail("Expected the service error to surface", file: file, line: line)
        } catch {
            XCTAssertEqual(error.localizedDescription, message, file: file, line: line)
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

extension RecipeImportError: @retroactive Equatable {
    public static func == (lhs: RecipeImportError, rhs: RecipeImportError) -> Bool {
        lhs.localizedDescription == rhs.localizedDescription
    }
}
