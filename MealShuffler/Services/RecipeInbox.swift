import Foundation
import Darwin

/// Something shared into the app from elsewhere, waiting to be turned into a meal.
struct CapturedRecipe: Codable, Identifiable, Hashable {
    let id: UUID
    let capturedAt: Date
    let url: URL?
    let text: String?
    /// File name inside the shared container. Image bytes are too large for user defaults.
    let imageFilename: String?

    init(
        id: UUID = UUID(),
        capturedAt: Date = .now,
        url: URL? = nil,
        text: String? = nil,
        imageFilename: String? = nil
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.url = url
        self.text = text
        self.imageFilename = imageFilename
    }

    var imageData: Data? {
        imageFilename.flatMap { RecipeInbox.imageData(named: $0) }
    }

    var summary: String {
        if let url { return url.host ?? url.absoluteString }
        if imageFilename != nil { return L10n.string("Photo") }
        return text?.prefix(60).trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

/// A handoff queue between the share extension and the app.
///
/// The extension deliberately does not extract or save anything itself: it has a tight time
/// and memory budget, and two processes writing the same state blob is how state gets lost.
/// It captures what was shared and gets out of the way; the app does the work when opened.
enum RecipeInbox {
    private static let key = "meal-shuffler-recipe-inbox-v1"
    private static let imagesDirectory = "SharedRecipeImages"

    private static var directory: URL {
        let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return root.appendingPathComponent("RecipeInbox", isDirectory: true)
    }

    @discardableResult
    static func add(_ capture: CapturedRecipe) -> Bool {
        do {
            try migrate()
            try JSONEncoder().encode(capture).write(to: directory.appendingPathComponent("capture-\(capture.id).json"), options: .atomic)
            return true
        } catch { return false }
    }

    static func all() -> [CapturedRecipe] {
        do { try migrate() } catch { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix("capture-") }.compactMap { url -> CapturedRecipe? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(CapturedRecipe.self, from: data)
        }.sorted { $0.capturedAt < $1.capturedAt }
    }

    static func remove(_ id: UUID) {
        let item = all().first { $0.id == id }
        do {
            try FileManager.default.removeItem(at: directory.appendingPathComponent("capture-\(id).json"))
            if let filename = item?.imageFilename { deleteImage(named: filename) }
        } catch { /* Retain the source if removal could not finish. */ }
    }

    static func removeAll() {
        for item in all() { remove(item.id) }
    }

    // MARK: - Images

    static func storeImage(_ data: Data) -> String? {
        guard let directory = imagesURL() else { return nil }
        let filename = UUID().uuidString + ".img"
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent(filename), options: .atomic)
            return filename
        } catch {
            return nil
        }
    }

    static func imageData(named filename: String) -> Data? {
        guard validImageName(filename) else { return nil }
        return imagesURL().flatMap { try? Data(contentsOf: $0.appendingPathComponent(filename)) }
    }

    private static func deleteImage(named filename: String) {
        guard validImageName(filename) else { return }
        guard let directory = imagesURL() else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(filename))
    }

    private static func validImageName(_ name: String) -> Bool {
        name == URL(fileURLWithPath: name).lastPathComponent && !name.contains("\\")
            && UUID(uuidString: URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent) != nil
            && ["img", "jpg"].contains(URL(fileURLWithPath: name).pathExtension)
    }

    private static func imagesURL() -> URL? {
        (FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
            .appendingPathComponent(imagesDirectory, isDirectory: true)
    }

    private static func migrate() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let descriptor = open(directory.appendingPathComponent("migration.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { flock(descriptor, LOCK_UN); close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw CocoaError(.fileWriteUnknown) }
        let marker = directory.appendingPathComponent("migrated")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        if let data = AppGroup.defaults.data(forKey: key) {
            let items = try JSONDecoder().decode([CapturedRecipe].self, from: data)
            for item in items {
                try JSONEncoder().encode(item).write(to: directory.appendingPathComponent("capture-\(item.id).json"), options: .atomic)
            }
        }
        try Data().write(to: marker, options: .atomic)
        AppGroup.defaults.removeObject(forKey: key)
    }
}
