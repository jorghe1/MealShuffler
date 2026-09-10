import SwiftUI
import UniformTypeIdentifiers

struct RecipeLibraryArchive: Codable {
    var version = 1
    let meals: [Meal]
    let images: [String: Data]

    func validate() throws {
        guard version == 1, meals.count <= 2000, Set(meals.map(\.id)).count == meals.count,
              images.count <= 10_000, images.values.allSatisfy({ $0.count <= 2_000_000 }),
              images.keys.allSatisfy({ RecipeLibraryStorage.isSourceImageName($0) }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        for meal in meals {
            guard !meal.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  (1...1000).contains(meal.defaultServings), (0...10080).contains(meal.prepMinutes),
                  meal.ingredients.count <= 200, meal.instructions.count <= 200,
                  Set(meal.ingredients.map(\.id)).count == meal.ingredients.count,
                  (meal.sourceImageNames ?? []).allSatisfy({ RecipeLibraryStorage.isSourceImageName($0) && (images[$0] != nil || RecipeLibraryStorage.image(named: $0) != nil) }),
                  meal.ingredients.allSatisfy({ item in
                      !item.name.isEmpty && item.quantity.isFinite && (0...1_000_000).contains(item.quantity)
                          && (item.upperQuantity.map { $0.isFinite && $0 >= item.quantity && $0 <= 1_000_000 } ?? true)
                          && (item.packageQuantity.map { $0.isFinite && $0 > 0 && $0 <= 1_000_000 } ?? true)
                  }) else { throw CocoaError(.fileReadCorruptFile) }
        }
    }
}

extension UTType { static let mealShufflerRecipes = UTType(exportedAs: "no.mealshuffler.recipes", conformingTo: .package) }

struct RecipeLibraryDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.mealShufflerRecipes, .json] }
    let archive: RecipeLibraryArchive

    init(archive: RecipeLibraryArchive) { self.archive = archive }
    init(configuration: ReadConfiguration) throws { try self.init(wrapper: configuration.file) }
    init(wrapper: FileWrapper) throws {
        if let data = wrapper.regularFileContents {
            guard data.count <= 100_000_000 else { throw CocoaError(.fileReadTooLarge) }
            archive = try JSONDecoder().decode(RecipeLibraryArchive.self, from: data)
        } else {
            guard let files = wrapper.fileWrappers, files.count == 2,
                  let metadata = files["recipes.json"]?.regularFileContents, metadata.count <= 50_000_000,
                  let images = files["images"]?.fileWrappers, images.count <= 10_000 else { throw CocoaError(.fileReadCorruptFile) }
            let manifest = try JSONDecoder().decode(RecipeLibraryArchive.self, from: metadata)
            var restored: [String: Data] = [:]
            var total = metadata.count
            for (name, image) in images {
                guard RecipeLibraryStorage.isSourceImageName(name), let data = image.regularFileContents, data.count <= 2_000_000 else { throw CocoaError(.fileReadCorruptFile) }
                total += data.count
                guard total <= DeviceBackupDocument.maximumBytes else { throw CocoaError(.fileReadTooLarge) }
                restored[name] = data
            }
            archive = RecipeLibraryArchive(version: manifest.version, meals: manifest.meals, images: restored)
        }
        try archive.validate()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { try wrapper() }
    func wrapper() throws -> FileWrapper {
        try archive.validate()
        let metadata = try JSONEncoder().encode(RecipeLibraryArchive(meals: archive.meals, images: [:]))
        guard metadata.count <= 50_000_000, archive.images.values.reduce(metadata.count, { $0 + $1.count }) <= DeviceBackupDocument.maximumBytes else { throw CocoaError(.fileWriteOutOfSpace) }
        return FileWrapper(directoryWithFileWrappers: ["recipes.json": FileWrapper(regularFileWithContents: metadata),
            "images": FileWrapper(directoryWithFileWrappers: archive.images.mapValues { FileWrapper(regularFileWithContents: $0) })])
    }
}

struct LibraryTransferView: View {
    @EnvironmentObject private var store: AppStore
    @State private var exporting = false
    @State private var importing = false
    @State private var document: RecipeLibraryDocument?
    @State private var pendingArchive: RecipeLibraryArchive?
    @State private var message: String?

    var body: some View {
        List {
            Section {
                Button("Export recipe library") {
                    let meals = store.activeCustomMeals
                    let names = Set(meals.flatMap { $0.sourceImageNames ?? [] })
                    let images = Dictionary(uniqueKeysWithValues: names.compactMap { name -> (String, Data)? in
                        RecipeLibraryStorage.image(named: name).map { (name, $0) }
                    })
                    document = RecipeLibraryDocument(archive: RecipeLibraryArchive(meals: meals, images: images))
                    exporting = true
                }
                Button("Import recipe library") { importing = true }
                Button("Remove unused source photos") {
                    let state = store.makeSnapshot()
                    Task {
                        do {
                            let count = try await Task.detached { try RecipeLibraryStorage.pruneUnusedImages(state: state) }.value
                            message = L10n.string("Removed %ld unused photos. Photos used by drafts, history and revisions were kept.", count)
                        } catch { message = error.localizedDescription }
                    }
                }
                Text("Includes your recipes, customizations and source photos. Keep the file somewhere safe.")
            }
            Section("Recently deleted") {
                ForEach(store.deletedRecipes) { meal in
                    Button(meal.name) {
                        var restored = meal; restored.deletedAt = nil
                        _ = store.saveMeal(restored)
                    }
                }
            }
            if let message { Text(message) }
        }
        .navigationTitle("Recipe backups")
        .fileExporter(isPresented: $exporting, document: document, contentType: .mealShufflerRecipes, defaultFilename: "Meal-Shuffler.mealrecipes") { result in
            if case .failure(let error) = result { message = error.localizedDescription }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.mealShufflerRecipes, .json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                try DeviceBackupDocument.preflight(url)
                let archive = try RecipeLibraryDocument(wrapper: FileWrapper(url: url, options: [])).archive
                pendingArchive = archive
            } catch { message = error.localizedDescription }
        }
        .confirmationDialog("Merge imported recipes?", isPresented: Binding(
            get: { pendingArchive != nil }, set: { if !$0 { pendingArchive = nil } }
        )) {
            Button("Merge recipes") {
                guard let archive = pendingArchive else { return }
                do {
                    try RecipeLibraryStorage.restoreImages(archive.images)
                    if store.mergeRecipes(archive.meals) { message = L10n.string("Recipes restored.") }
                } catch { message = error.localizedDescription }
                pendingArchive = nil
            }
            Button("Cancel", role: .cancel) { pendingArchive = nil }
        } message: {
            Text("Matching recipe IDs will be updated. Other recipes stay in your library. Previous versions remain available.")
        }
    }
}
