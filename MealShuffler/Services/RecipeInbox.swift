import Foundation

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

    static func add(_ capture: CapturedRecipe) {
        var pending = all()
        pending.append(capture)
        write(pending)
    }

    static func all() -> [CapturedRecipe] {
        guard let data = AppGroup.defaults.data(forKey: key),
              let items = try? JSONDecoder().decode([CapturedRecipe].self, from: data) else {
            return []
        }
        return items.sorted { $0.capturedAt < $1.capturedAt }
    }

    static func remove(_ id: UUID) {
        let remaining = all().filter { item in
            guard item.id == id else { return true }
            // Take the image with it, or the container grows forever.
            if let filename = item.imageFilename { deleteImage(named: filename) }
            return false
        }
        write(remaining)
    }

    static func removeAll() {
        for item in all() {
            if let filename = item.imageFilename { deleteImage(named: filename) }
        }
        write([])
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
        imagesURL().flatMap { try? Data(contentsOf: $0.appendingPathComponent(filename)) }
    }

    private static func deleteImage(named filename: String) {
        guard let directory = imagesURL() else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(filename))
    }

    private static func imagesURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)?
            .appendingPathComponent(imagesDirectory, isDirectory: true)
    }

    private static func write(_ items: [CapturedRecipe]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        AppGroup.defaults.set(data, forKey: key)
    }
}
