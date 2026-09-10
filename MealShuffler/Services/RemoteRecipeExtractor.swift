import Foundation

/// Extraction through the service in `server/`.
///
/// Configured by `RecipeServiceBaseURL` in Info.plist. With no URL set the app stays entirely
/// on the on-device parser, which is the correct behaviour before the service is deployed --
/// and the reason `ChainedRecipeExtractor` puts the local parser first: structured markup is
/// instant and free, and a service outage should degrade import rather than break it.
struct RemoteRecipeExtractor: RecipeExtractor {
    struct Configuration {
        let baseURL: URL
        var timeout: TimeInterval = 30

        /// Reads the deployed URL from the bundle. Returns nil when unset or a placeholder.
        static func fromBundle(_ bundle: Bundle = .main) -> Configuration? {
            guard let raw = bundle.object(forInfoDictionaryKey: "RecipeServiceBaseURL") as? String else {
                return nil
            }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("$("),
                  let url = URL(string: trimmed), url.scheme?.lowercased() == "https" else {
                return nil
            }
            return Configuration(baseURL: url)
        }
    }

    let configuration: Configuration
    private let session: URLSession

    init(configuration: Configuration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func extract(from url: URL) async throws -> ImportedRecipeDraft {
        guard url.scheme?.lowercased() == "https" else { throw RecipeImportError.invalidURL }
        return try await send(Payload(url: url.absoluteString), source: .web(url))
    }

    func extract(fromImage data: Data) async throws -> ImportedRecipeDraft {
        try await extract(fromImages: [data])
    }

    func extract(fromImages data: [Data], note: String = "") async throws -> ImportedRecipeDraft {
        let images = try data.map(RecipeImagePreparation.prepare)
        guard !images.isEmpty, images.count <= 5 else { throw RecipeImportError.unreadableImage }
        var draft = try await send(Payload(text: note.isEmpty ? nil : note, images: images.map {
            Payload.Image(data: $0.base64EncodedString(), mediaType: "image/jpeg")
        }), source: .photo)
        draft.sourceImages = images
        draft.sourceText = note.isEmpty ? nil : note
        return draft
    }

    func extract(fromText text: String) async throws -> ImportedRecipeDraft {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RecipeImportError.recipeNotFound }
        var draft = try await send(Payload(text: trimmed), source: .manual)
        draft.sourceText = trimmed
        return draft
    }

    // MARK: - Transport

    private func send(_ payload: Payload, source: MealSource) async throws -> ImportedRecipeDraft {
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent("v1/recipes/extract"))
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Not a credential. An abuse key, so one client can be capped without affecting others.
        request.setValue(DeviceIdentity.current.uuidString, forHTTPHeaderField: "X-Install-Id")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RecipeImportError.recipeNotFound }

        guard (200...299).contains(http.statusCode) else {
            // The service explains itself in plain language; prefer that to a status code.
            if let failure = try? JSONDecoder().decode(ServiceError.self, from: data) {
                let key: String
                switch failure.code {
                case "rate_limited": key = "Online imports are busy or have reached the service limit. Try again later."
                case "too_large": key = "This source is too large. Try fewer photos or a shorter text."
                case "unreadable_recipe", "invalid_recipe": key = "The recipe could not be read reliably. Check the source or use on-device recognition."
                default: key = "Online extraction is unavailable. Try again or use on-device recognition."
                }
                throw RecipeImportError.service(L10n.string(key))
            }
            throw RecipeImportError.recipeNotFound
        }

        let extracted = try JSONDecoder().decode(ExtractedRecipe.self, from: data)
        return extracted.draft(source: source)
    }

    // MARK: - Wire types

    private struct Payload: Encodable {
        struct Image: Encodable {
            let data: String
            let mediaType: String
        }
        var url: String?
        var text: String?
        var images: [Image]?
    }

    private struct ServiceError: Decodable {
        var code: String?
        let error: String
    }

    private struct ExtractedRecipe: Decodable {
        struct RemoteIngredient: Decodable {
            let name: String
            let quantity: Double?
            let unit: String
            let aisle: String
            let originalText: String?
            let upperQuantity: Double?
            let section: String?
            let packageQuantity: Double?
            let packageUnit: String?

            var ingredient: Ingredient {
                Ingredient(name: name, quantity: quantity ?? 0, unit: unit,
                           aisle: GroceryAisle(rawValue: aisle) ?? .pantry,
                           originalText: originalText, upperQuantity: upperQuantity, section: section,
                           packageQuantity: packageQuantity, packageUnit: packageUnit)
            }


        }

        let name: String
        let subtitle: String
        let emoji: String
        let prepMinutes: Int?
        let activeMinutes: Int?
        let servings: Int?
        let ingredients: [RemoteIngredient]
        let instructions: [String]
        let tags: [String]
        let confidence: String
        let heroImageURL: String?

        func draft(source: MealSource) -> ImportedRecipeDraft {
            ImportedRecipeDraft(
                name: name,
                subtitle: subtitle,
                emoji: emoji.isEmpty ? "🍽️" : emoji,
                prepMinutes: max(prepMinutes ?? 30, 5),
                servings: max(servings ?? 4, 1),
                // The editor takes ingredients as text so the user can correct them before
                // saving, which is what makes an occasionally-wrong extraction acceptable.
                ingredientLines: ingredients.map { $0.ingredient.editableLine },
                instructions: instructions,
                tags: Set(tags.compactMap(MealTag.init(rawValue:))),
                parsedIngredients: ingredients.map(\.ingredient),
                heroImageURL: heroImageURL.flatMap(URL.init(string:)),
                needsReview: true,
                source: source,
                servingsConfirmed: servings.map { $0 > 0 } ?? false,
                activeMinutes: activeMinutes,
                timingNeedsReview: prepMinutes == nil
            )
        }
    }
}
