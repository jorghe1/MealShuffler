import Foundation

/// One place that decides how recipes get extracted.
///
/// The local parsers stay first in the chain even once the service is deployed: structured
/// markup is instant and costs nothing, and an outage should degrade import rather than
/// break it. The remote extractor is what handles everything the local one cannot -- the
/// pages without schema.org markup, and photographs.
enum RecipeCapture {
    static var remoteConfiguration: RemoteRecipeExtractor.Configuration? {
        RemoteRecipeExtractor.Configuration.fromBundle()
    }

    static var isRemoteAvailable: Bool { remoteConfiguration != nil }

    /// Links: try the on-device schema.org parser, then the service.
    static var urlExtractor: any RecipeExtractor {
        guard let configuration = remoteConfiguration else { return RecipeImportService() }
        return ChainedRecipeExtractor(extractors: [
            RecipeImportService(),
            RemoteRecipeExtractor(configuration: configuration)
        ])
    }

    /// Photos: the service reads a page far better than OCR plus heuristics can, so it goes
    /// first here. On-device recognition remains the offline fallback.
    static var imageExtractor: any RecipeExtractor {
        guard let configuration = remoteConfiguration else { return RecipeOCRService() }
        return ChainedRecipeExtractor(extractors: [
            RemoteRecipeExtractor(configuration: configuration),
            RecipeOCRService()
        ])
    }

    /// Text shared from another app. There is no local equivalent, so this is the one path
    /// that genuinely requires the service.
    static func extractText(_ text: String) async throws -> ImportedRecipeDraft {
        guard let configuration = remoteConfiguration else {
            throw RecipeImportError.service(
                L10n.string("Reading pasted text needs the import service, which is not set up yet.")
            )
        }
        return try await RemoteRecipeExtractor(configuration: configuration).extract(fromText: text)
    }

    static func extract(_ capture: CapturedRecipe) async throws -> ImportedRecipeDraft {
        if let url = capture.url { return try await urlExtractor.extract(from: url) }
        if let data = capture.imageData { return try await imageExtractor.extract(fromImage: data) }
        if let text = capture.text { return try await extractText(text) }
        throw RecipeImportError.recipeNotFound
    }
}
