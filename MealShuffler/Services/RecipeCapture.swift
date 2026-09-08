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

    /// Text pasted in or shared from another app.
    ///
    /// The service reads prose far better than heuristics, so it goes first -- but it is no
    /// longer required. This was the one path with no local equivalent, which meant that with
    /// no service deployed, pasting a recipe answered with an error.
    static func extractText(_ text: String) async throws -> ImportedRecipeDraft {
        if let configuration = remoteConfiguration,
           let draft = try? await RemoteRecipeExtractor(configuration: configuration).extract(fromText: text) {
            return draft
        }
        return try RecipeTextStructurer.draft(fromPastedText: text)
    }

    /// A scan of one or more pages.
    ///
    /// The service reads a single image best, so one page still goes to it first. A recipe
    /// spread across two pages has no single image to send, so those are read on device and
    /// stitched in page order.
    static func extract(fromImages images: [Data]) async throws -> ImportedRecipeDraft {
        guard let first = images.first else { throw RecipeImportError.unreadableImage }
        guard images.count > 1 else { return try await imageExtractor.extract(fromImage: first) }
        return try await RecipeOCRService().recognizeRecipe(fromPages: images)
    }

    static func extract(_ capture: CapturedRecipe) async throws -> ImportedRecipeDraft {
        if let url = capture.url { return try await urlExtractor.extract(from: url) }
        if let data = capture.imageData { return try await imageExtractor.extract(fromImage: data) }
        if let text = capture.text { return try await extractText(text) }
        throw RecipeImportError.recipeNotFound
    }
}
