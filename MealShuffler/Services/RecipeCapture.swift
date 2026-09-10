import Foundation

/// One place that decides how recipes get extracted.
///
/// The local parsers stay first in the chain even once the service is deployed: structured
/// markup is instant and costs nothing, and an outage should degrade import rather than
/// break it. The remote extractor is what handles everything the local one cannot -- the
/// pages without schema.org markup, and photographs.
enum RecipeCapture {
    static var remoteConfiguration: RemoteRecipeExtractor.Configuration? {
        guard UserDefaults.standard.bool(forKey: "online-extraction-enabled") else { return nil }
        return RemoteRecipeExtractor.Configuration.fromBundle()
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
        if let configuration = remoteConfiguration {
            do { return try await RemoteRecipeExtractor(configuration: configuration).extract(fromText: text) }
            catch is CancellationError { throw CancellationError() }
            catch { /* Preserve an offline path. */ }
        }
        try Task.checkCancellation()
        var draft = try RecipeTextStructurer.draft(fromPastedText: text)
        draft.extractionNote = L10n.string("Read on this device. Check the extracted amounts and steps against the original source.")
        return draft
    }

    /// A scan of one or more pages.
    ///
    /// The service receives all pages together; local OCR remains available offline.
    static func extract(fromImages images: [Data], note: String = "") async throws -> ImportedRecipeDraft {
        guard !images.isEmpty, images.count <= 5 else { throw RecipeImportError.unreadableImage }
        let prepared = try images.map(RecipeImagePreparation.prepare)
        if let configuration = remoteConfiguration {
            do { return try await RemoteRecipeExtractor(configuration: configuration).extract(fromImages: prepared, note: note) }
            catch is CancellationError { throw CancellationError() }
            catch { /* Keep the source available when the service cannot answer. */ }
        }
        try Task.checkCancellation()
        var draft = try await RecipeOCRService().recognizeRecipe(fromPages: prepared)
        draft.sourceImages = prepared
        if !note.isEmpty { draft.sourceText = (draft.sourceText ?? "") + "\n\n" + note }
        draft.extractionNote = L10n.string("Read on this device. Check the extracted amounts and steps against the original source.")
        return draft
    }

    static func extract(_ capture: CapturedRecipe) async throws -> ImportedRecipeDraft {
        var draft: ImportedRecipeDraft
        if let url = capture.url { draft = try await urlExtractor.extract(from: url) }
        else if let data = capture.imageData { draft = try await extract(fromImages: [data]) }
        else if let text = capture.text { draft = try await extractText(text) }
        else { throw RecipeImportError.recipeNotFound }
        draft.captureID = capture.id
        return draft
    }
}
