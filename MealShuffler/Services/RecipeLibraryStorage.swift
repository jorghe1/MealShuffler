import Foundation
import CryptoKit

/// Recipe sources, drafts and revisions have independent files so editing a title does not
/// rewrite the household's entire photo library.
enum RecipeLibraryStorage {
    private static let draftLock = NSRecursiveLock()
    private static var draftRevisions: [UUID: Int] = [:]
    static func beginDraftSave(_ id: UUID) -> Int {
        draftLock.lock(); defer { draftLock.unlock() }
        let revision = draftRevisions[id, default: 0] + 1
        draftRevisions[id] = revision
        return revision
    }
    static var directory: URL {
        let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return root.appendingPathComponent("RecipeLibrary", isDirectory: true)
    }

    private static func write<T: Encodable>(_ value: T, filename: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: directory.appendingPathComponent(filename), options: .atomic)
    }

    static func saveDraft(_ draft: ImportedRecipeDraft, revision: Int? = nil) throws {
        draftLock.lock(); defer { draftLock.unlock() }
        let revision = revision ?? beginDraftSave(draft.id)
        guard draftRevisions[draft.id] == revision else { return }
        var metadata = draft
        if !draft.sourceImages.isEmpty { metadata.sourceImageNames = try saveImages(draft.sourceImages, recipeID: draft.id) }
        metadata.sourceImages = []
        try write(metadata, filename: "draft-\(draft.id).json")
    }

    static func drafts() -> [ImportedRecipeDraft] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix("draft-") }.compactMap {
            guard let data = try? Data(contentsOf: $0) else { return nil }
            guard var draft = try? JSONDecoder().decode(ImportedRecipeDraft.self, from: data) else { return nil }
            if draft.sourceImages.isEmpty { draft.sourceImages = (draft.sourceImageNames ?? []).compactMap { image(named: $0) } }
            return draft
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func removeDraft(_ id: UUID) {
        draftLock.lock(); defer { draftLock.unlock() }
        _ = beginDraftSave(id)
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("draft-\(id).json"))
    }

    static func saveImages(_ images: [Data], recipeID: UUID) throws -> [String] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try images.map { data in
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            let name = "source-\(digest).jpg"
            let url = directory.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: url.path) { try data.write(to: url, options: .atomic) }
            return name
        }
    }

    static func image(named name: String) -> Data? {
        guard isSourceImageName(name) else { return nil }
        return try? Data(contentsOf: directory.appendingPathComponent(name))
    }

    static func revisions(for id: UUID) -> [Meal] {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("revisions-\(id).json")) else { return [] }
        return (try? JSONDecoder().decode([Meal].self, from: data)) ?? []
    }

    static func retainRevision(_ meal: Meal) throws {
        let history = revisions(for: meal.id)
        try write(Array(([meal] + history).prefix(10)), filename: "revisions-\(meal.id).json")
    }

    static func restoreImages(_ images: [String: Data]) throws {
        guard images.keys.allSatisfy({ isSourceImageName($0) }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, data) in images {
            let target = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: target.path) { continue }
            try data.write(to: target, options: .atomic)
        }
    }

    static func isSourceImageName(_ name: String) -> Bool {
        name == URL(fileURLWithPath: name).lastPathComponent && !name.contains("\\")
            && name.hasPrefix("source-") && name.hasSuffix(".jpg")
    }

    /// A grace period protects imports and edits that are still in flight. Deleted recipes
    /// and saved revisions count as references because users can restore them.
    static func pruneUnusedImages(state: AppStateSnapshot, now: Date = .now) throws -> Int {
        let recipes = state.customMeals + state.archivedWeeks.flatMap { $0.recipeSnapshots ?? [] }
            + state.feedbackEvents.compactMap(\.recipeSnapshot) + state.tools.freezer.map(\.recipe)
            + (state.plan.meals + (state.nextWeekPlan?.meals ?? []) + state.archivedWeeks.flatMap { $0.plan.meals }).compactMap { $0.freezerBatch?.recipe }
        var retained = Set(recipes.flatMap { $0.sourceImageNames ?? [] })
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for url in files where url.lastPathComponent.hasPrefix("revisions-") {
            // Unreadable metadata is a reason to keep images, never a reason to delete them.
            let history = try JSONDecoder().decode([Meal].self, from: Data(contentsOf: url))
            retained.formUnion(history.flatMap { $0.sourceImageNames ?? [] })
        }
        for url in files where url.lastPathComponent.hasPrefix("draft-") {
            let draft = try JSONDecoder().decode(ImportedRecipeDraft.self, from: Data(contentsOf: url))
            retained.formUnion(draft.sourceImageNames ?? [])
        }
        var removed = 0
        for url in files where isSourceImageName(url.lastPathComponent) && !retained.contains(url.lastPathComponent) {
            guard let date = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  now.timeIntervalSince(date) > 7 * 86400 else { continue }
            try FileManager.default.removeItem(at: url); removed += 1
        }
        return removed
    }
}
