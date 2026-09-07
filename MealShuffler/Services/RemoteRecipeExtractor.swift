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
        try await send(
            Payload(imageBase64: data.base64EncodedString(), imageMediaType: Self.mediaType(of: data)),
            source: .photo
        )
    }

    func extract(fromText text: String) async throws -> ImportedRecipeDraft {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RecipeImportError.recipeNotFound }
        return try await send(Payload(text: trimmed), source: .manual)
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
                throw RecipeImportError.service(failure.error)
            }
            throw RecipeImportError.recipeNotFound
        }

        let extracted = try JSONDecoder().decode(ExtractedRecipe.self, from: data)
        return extracted.draft(source: source)
    }

    /// Sniffs the container from its magic bytes. The picker hands over raw data with no
    /// type attached, and sending the wrong one is rejected by the service.
    private static func mediaType(of data: Data) -> String {
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if bytes.starts(with: [0x47, 0x49, 0x46]) { return "image/gif" }
        if bytes.count >= 12, bytes[8...11] == [0x57, 0x45, 0x42, 0x50] { return "image/webp" }
        return "image/jpeg"
    }

    // MARK: - Wire types

    private struct Payload: Encodable {
        var url: String?
        var text: String?
        var imageBase64: String?
        var imageMediaType: String?
    }

    private struct ServiceError: Decodable {
        let error: String
    }

    private struct ExtractedRecipe: Decodable {
        struct RemoteIngredient: Decodable {
            let name: String
            let quantity: Double?
            let unit: String
            let aisle: String

            /// Rendered back into a line so it flows through the same parser and editor as
            /// every other import, rather than becoming a second, privileged path into the
            /// library.
            var line: String {
                let amount = quantity.map { value -> String in
                    value == value.rounded()
                        ? String(Int(value))
                        : String(format: "%.2f", value)
                            .replacingOccurrences(of: "0$", with: "", options: .regularExpression)
                }
                return [amount, unit.isEmpty ? nil : unit, name]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }
        }

        let name: String
        let subtitle: String
        let emoji: String
        let prepMinutes: Int
        let servings: Int
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
                prepMinutes: max(prepMinutes, 5),
                servings: max(servings, 1),
                // The editor takes ingredients as text so the user can correct them before
                // saving, which is what makes an occasionally-wrong extraction acceptable.
                ingredientLines: ingredients.map(\.line),
                instructions: instructions,
                tags: Set(tags.compactMap(MealTag.init(rawValue:))),
                heroImageURL: heroImageURL.flatMap(URL.init(string:)),
                needsReview: confidence != "high",
                source: source
            )
        }
    }
}
