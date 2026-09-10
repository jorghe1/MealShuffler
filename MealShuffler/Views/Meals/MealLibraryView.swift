import PhotosUI
import SwiftUI

struct MealLibraryView: View {
    /// One value drives what is presented.
    ///
    /// Four booleans and two payload properties used to coordinate two sheets, and handing
    /// off from the link importer to the editor needed a 250ms timer to let the first sheet
    /// finish dismissing -- timing-dependent, and wrong on a slow device or with reduced
    /// motion. Changing the item swaps the sheet directly.
    private enum LibrarySheet: Identifiable {
        case editor(existing: Meal?, draft: ImportedRecipeDraft)
        case linkImport
        case paste(ImportedRecipeDraft)
        case detail(Meal)
        case photos(ImportedRecipeDraft)
        case capture(CapturedRecipe)

        var id: String {
            switch self {
            case .editor(_, let draft): "editor-\(draft.id)"
            case .linkImport: "link"
            case .paste: "paste"
            case .detail(let meal): "detail-\(meal.id)"
            case .photos: "photos"
            case .capture(let capture): "capture-\(capture.id)"
            }
        }
    }

    @EnvironmentObject private var store: AppStore

    @State private var searchText = ""
    @State private var filter: MealFilter = .all
    @State private var category: MealTag?
    @State private var collection: String?
    @State private var reviewOnly = false
    @State private var sortOrder = 0
    @State private var customLabel: String?
    @State private var quickOnly = false
    @State private var sheet: LibrarySheet?
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var drafts: [ImportedRecipeDraft] = []
    @State private var importError: String?
    @State private var isImportingPhoto = false
    @State private var isScanning = false
    @State private var isPickingPhotos = false

    private var filteredMeals: [Meal] {
        store.meals
            .filter { filter.matches($0, favorites: store.favoriteMealIDs) }
            .filter { $0.matches(searchText: searchText) }
            .filter { category == nil || $0.tags.contains(category!) }
            .filter { collection == nil || store.householdTools.collections[collection!]?.contains($0.id) == true }
            .filter { !reviewOnly || $0.servingsConfirmed == false || $0.prepMinutes <= 0 || $0.ingredients.contains(where: { $0.needsAmountReview }) }
            .filter { customLabel == nil || $0.customTags.contains(customLabel!) }
            .filter { !quickOnly || ($0.prepMinutes > 0 && $0.prepMinutes <= 30) }
            .sorted { left, right in
                if sortOrder == 2 { return left.updatedAt > right.updatedAt }
                if sortOrder == 3 { return (store.lastCookedByMeal[left.id] ?? .distantPast) < (store.lastCookedByMeal[right.id] ?? .distantPast) }
                return sortOrder == 1 ? (left.prepMinutes > 0 ? left.prepMinutes : Int.max) < (right.prepMinutes > 0 ? right.prepMinutes : Int.max) : left.name.localizedStandardCompare(right.name) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                actionCard
                ForEach(drafts) { draft in
                    HStack {
                        Label(draft.name.isEmpty ? L10n.string("Unfinished recipe") : draft.name, systemImage: "doc.badge.clock")
                        Spacer()
                        Button("Resume") {
                            if draft.name.isEmpty, !draft.sourceImages.isEmpty { sheet = .photos(draft) }
                            else if draft.name.isEmpty, draft.sourceText != nil { sheet = .paste(draft) }
                            else { sheet = .editor(existing: nil, draft: draft) }
                        }
                        Button("Discard", role: .destructive) { RecipeLibraryStorage.removeDraft(draft.id); drafts = RecipeLibraryStorage.drafts() }
                    }.padding().mealCard()
                }
                if !store.pendingCaptures.isEmpty { sharedCard }
                filterRow
                Menu("Filter and sort") {
                    Picker("Category", selection: $category) { Text("All").tag(nil as MealTag?); ForEach(MealTag.allCases) { Text($0.name).tag($0 as MealTag?) } }
                    Picker("Collection", selection: $collection) { Text("All").tag(nil as String?); ForEach(store.householdTools.collections.keys.sorted(), id: \.self) { Text($0).tag($0 as String?) } }
                    Toggle("Needs review", isOn: $reviewOnly)
                    Toggle("30 minutes or less", isOn: $quickOnly)
                    Picker("Label", selection: $customLabel) { Text("All").tag(nil as String?); ForEach(store.customTagsInUse, id: \.self) { Text($0).tag($0 as String?) } }
                    Picker("Sort", selection: $sortOrder) { Text("Name").tag(0); Text("Quickest first").tag(1); Text("Recently updated").tag(2); Text("Longest since cooked").tag(3) }
                }
                NavigationLink("Manage collections") { RecipeCollectionsView() }
                if filteredMeals.isEmpty { emptyState }
                ForEach(filteredMeals) { meal in
                    MealRow(
                        meal: meal,
                        isFavorite: store.favoriteMealIDs.contains(meal.id),
                        toggleFavorite: { store.toggleFavorite(meal) }
                    )
                    .mealCard()
                    .contentShape(Rectangle())
                    .onTapGesture { sheet = .detail(meal) }
                    .contextMenu {
                        // The other half of choosing a dinner: from a meal you are looking
                        // at, rather than from the day you are filling.
                        Menu {
                            ForEach(Weekday.ordered()) { day in
                                Button(day.name) { store.setMeal(meal, on: day) }
                            }
                        } label: {
                            Label("Plan for a day", systemImage: "calendar.badge.plus")
                        }
                        Button(store.favoriteMealIDs.contains(meal.id)
                            ? L10n.string("Remove family favorite")
                            : L10n.string("Mark as family favorite")) {
                            store.toggleFavorite(meal)
                        }
                        if let link = BringExport.deeplink(for: meal, servings: store.householdSize) {
                            Link(destination: link) {
                                Label("Add to Bring!", systemImage: "cart.badge.plus")
                            }
                        }
                        Button(meal.isBuiltIn ? L10n.string("Hide recipe") : L10n.string("Delete"), role: .destructive) { store.deleteMeal(meal) }
                        if SampleMeals.all.contains(where: { $0.id == meal.id }), !meal.isBuiltIn {
                            Button("Reset to original") { store.resetRecipeToOriginal(meal) }
                        }
                    }
                }
                Color.clear.frame(height: 20)
            }
            .padding(16)
        }
        .appBackground()
        .navigationTitle("Meals")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search meals")
        .sheet(item: $sheet, onDismiss: { drafts = RecipeLibraryStorage.drafts() }) { presented in
            switch presented {
            case .capture(let capture):
                CapturedRecipeImportView(capture: capture) { draft in
                    sheet = .editor(existing: nil, draft: draft)
                } cancel: { sheet = nil }
            case .editor(let existing, let draft):
                RecipeEditorView(existingMeal: existing, draft: draft)
                    .environmentObject(store)
            case .linkImport:
                RecipeLinkImportView { imported in
                    sheet = .editor(existing: nil, draft: imported)
                }
            case .paste(let draft):
                PasteRecipeView(draft: draft) { imported in
                    sheet = .editor(existing: nil, draft: imported)
                }
            case .photos(let source):
                PhotoRecipeImportView(draft: source) { draft in sheet = .editor(existing: nil, draft: draft) }
            case .detail(let meal):
                MealDetailView(meal: meal)
                    .safeAreaInset(edge: .bottom) {
                        HStack {
                            Button("Edit") { sheet = .editor(existing: meal, draft: ImportedRecipeDraft()) }
                            Menu("Plan") {
                                ForEach(Weekday.ordered()) { day in Button(day.name) { store.setMeal(meal, on: day); sheet = nil } }
                            }
                            Menu("More") {
                                Button("Save as a variant") {
                                    var draft = ImportedRecipeDraft(name: meal.name, subtitle: meal.subtitle, emoji: meal.emoji,
                                        prepMinutes: meal.prepMinutes, servings: meal.defaultServings,
                                        ingredientLines: meal.ingredients.map(\.editableLine), instructions: meal.instructions,
                                        tags: meal.tags, customTags: meal.customTags, parsedIngredients: meal.ingredients,
                                        needsReview: true, source: meal.source, servingsConfirmed: true)
                                    draft.sourceText = meal.sourceText
                                    draft.sourceImages = (meal.sourceImageNames ?? []).compactMap { RecipeLibraryStorage.image(named: $0) }
                                    draft.heroImageURL = meal.heroImageURL
                                    draft.activeMinutes = meal.activeMinutes
                                    draft.parentRecipeID = meal.id
                                    sheet = .editor(existing: nil, draft: draft)
                                }
                                if case .web(let url) = meal.source {
                                    Button("Update from source") {
                                        Task {
                                            do {
                                                var draft = try await RecipeCapture.urlExtractor.extract(from: url)
                                                draft.updatingMealID = meal.id
                                                draft.customTags = meal.customTags
                                                sheet = .editor(existing: nil, draft: draft)
                                            } catch { importError = error.localizedDescription }
                                        }
                                    }
                                }
                                ForEach(Array(RecipeLibraryStorage.revisions(for: meal.id).enumerated()), id: \.offset) { _, previous in
                                    Button(L10n.string("Restore version from %@", previous.updatedAt.formatted())) {
                                        if store.saveMeal(previous) { sheet = .detail(previous) }
                                    }
                                }
                            }
                        }.buttonStyle(.bordered).padding().frame(maxWidth: .infinity).background(AppTheme.background)
                    }
            }
        }
        .fullScreenCover(isPresented: $isScanning) {
            DocumentScannerView(
                scanned: { pages in
                    isScanning = false
                    guard !pages.isEmpty else { return }
                    Task { @MainActor in await importScan(pages) }
                },
                cancelled: { isScanning = false }
            )
            .ignoresSafeArea()
        }
        .alert("Import stopped", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(importError ?? L10n.string("Unknown error")) }
        .onAppear { drafts = RecipeLibraryStorage.drafts() }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { @MainActor in await importPhotos(items) }
        }
    }

    private var filterRow: some View {
        HStack(spacing: 8) {
            ForEach(MealFilter.allCases) { option in
                Button {
                    withAnimation(.snappy) { filter = option }
                } label: {
                    Text(option.name).chipStyle(selected: filter == option)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(filter == option ? [.isButton, .isSelected] : [.isButton])
            }
            Spacer(minLength: 0)
            Text(L10n.string("%ld meals", filteredMeals.count))
                .font(.caption).foregroundStyle(AppTheme.muted)
        }
    }

    /// What the share extension left behind, waiting to be turned into meals.
    private var sharedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                store.pendingCaptures.count == 1
                    ? L10n.string("1 recipe shared to Meal Shuffler")
                    : L10n.string("%ld recipes shared to Meal Shuffler", store.pendingCaptures.count),
                systemImage: "tray.and.arrow.down"
            )
            .font(.headline).foregroundStyle(AppTheme.ink)

            ForEach(store.pendingCaptures) { capture in
                HStack(spacing: 10) {
                    Text(capture.summary)
                        .font(.subheadline).foregroundStyle(AppTheme.muted).lineLimit(1)
                    Spacer(minLength: 8)
                    Button("Add") { sheet = .capture(capture) }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.bordered)
                    Button { store.discardCapture(capture) } label: {
                        Image(systemName: "xmark").iconButtonFrame()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.muted)
                    .accessibilityLabel(L10n.string("Discard"))
                }
            }
        }
        .padding(18)
        .mealCard()
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: searchText.isEmpty ? "tray" : "magnifyingglass")
                .font(.system(.largeTitle)).foregroundStyle(AppTheme.accent)
            Text(emptyTitle)
                .font(.headline).foregroundStyle(AppTheme.ink).multilineTextAlignment(.center)
            Text(emptyDetail)
                .font(.subheadline).foregroundStyle(AppTheme.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(30)
        .mealCard()
    }

    private var emptyTitle: String {
        if !searchText.isEmpty { return L10n.string("No meals match “%@”", searchText) }
        return switch filter {
        case .favourites: L10n.string("No favourites yet")
        case .mine: L10n.string("No meals of your own yet")
        case .all: L10n.string("No meals yet")
        }
    }

    private var emptyDetail: String {
        if !searchText.isEmpty { return L10n.string("Try another word, or add it as a new meal.") }
        return switch filter {
        case .favourites: L10n.string("Tap the heart on a meal to keep it close.")
        case .mine: L10n.string("Add one, or share a recipe into the app from Safari.")
        case .all: L10n.string("Add one, or share a recipe into the app from Safari.")
        }
    }

    private var actionCard: some View {
        Menu {
            Button("Write a recipe", systemImage: "square.and.pencil") { sheet = .editor(existing: nil, draft: ImportedRecipeDraft()) }
            Button("Import from a link", systemImage: "link") { sheet = .linkImport }
            Button("Paste recipe text", systemImage: "doc.on.clipboard") { sheet = .paste(ImportedRecipeDraft()) }
            Button("Choose recipe photos", systemImage: "photo") { isPickingPhotos = true }
            if DocumentScannerView.isAvailable { Button("Scan recipe pages", systemImage: "doc.viewfinder") { isScanning = true } }
        } label: {
            Label("Add recipe", systemImage: "plus").font(.headline).frame(maxWidth: .infinity, minHeight: 48)
        }.buttonStyle(.borderedProminent)
        .disabled(isImportingPhoto)
        .overlay { if isImportingPhoto { ProgressView() } }
        .photosPicker(isPresented: $isPickingPhotos, selection: $photoItems, maxSelectionCount: 5, matching: .images)
    }

    /// A scan can be several pages of one recipe, which is why it is not the photo path.
    private func importScan(_ pages: [Data]) async {
        guard pages.count <= 5 else { importError = L10n.string("Choose up to five pages for one recipe."); return }
        sheet = .photos(ImportedRecipeDraft(source: .photo, sourceImages: pages))
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        isImportingPhoto = true
        defer { isImportingPhoto = false; photoItems = [] }
        do {
            var images: [Data] = []
            for item in items {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw RecipeImportError.unreadableImage }
                images.append(try RecipeImagePreparation.prepare(data))
            }
            sheet = .photos(ImportedRecipeDraft(source: .photo, sourceImages: images))
        } catch {
            importError = error.localizedDescription
        }
    }
}

private struct PhotoRecipeImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var images: [Data]
    private let sourceDraft: ImportedRecipeDraft
    @State private var handedOff = false
    let imported: (ImportedRecipeDraft) -> Void
    @State private var note = ""
    @State private var isReading = false
    @State private var errorMessage: String?
    @State private var readingTask: Task<Void, Never>?

    init(draft: ImportedRecipeDraft, imported: @escaping (ImportedRecipeDraft) -> Void) {
        sourceDraft = draft
        _images = State(initialValue: draft.sourceImages)
        _note = State(initialValue: draft.sourceText ?? "")
        self.imported = imported
    }

    private var pendingDraft: ImportedRecipeDraft {
        var draft = sourceDraft
        draft.sourceImages = images
        draft.sourceText = note
        return draft
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Recipe pages") {
                    ForEach(Array(images.enumerated()), id: \.offset) { _, data in
                        if let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit() }
                    }
                    .onMove { images.move(fromOffsets: $0, toOffset: $1) }
                    Text("Drag pages into reading order.").font(.caption)
                }
                .environment(\.editMode, .constant(.active))
                Section("Additional context") {
                    TextField("For example: these pages make one recipe for six", text: $note, axis: .vertical)
                    Text("Photograph the written recipe. A finished dish does not reveal exact ingredients or quantities.").font(.caption)
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(AppTheme.warning) }
                Button("Read recipe") {
                    isReading = true
                    readingTask = Task {
                        defer { isReading = false }
                        do {
                            try RecipeLibraryStorage.saveDraft(pendingDraft)
                            var draft = try await RecipeCapture.extract(fromImages: images, note: note)
                            try Task.checkCancellation()
                            draft.id = sourceDraft.id
                            try RecipeLibraryStorage.saveDraft(draft)
                            handedOff = true
                            imported(draft)
                        } catch is CancellationError { }
                        catch { errorMessage = error.localizedDescription }
                    }
                }.disabled(isReading)
                if isReading { ProgressView() }
            }
            .navigationTitle("Read recipe photos")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { readingTask?.cancel(); dismiss() } } }
        }
        .task(id: pendingDraft) {
            do {
                try await Task.sleep(for: .milliseconds(500))
                if !handedOff { try RecipeLibraryStorage.saveDraft(pendingDraft) }
            } catch is CancellationError { }
            catch { errorMessage = error.localizedDescription }
        }
        .onDisappear {
            readingTask?.cancel()
            if !handedOff { do { try RecipeLibraryStorage.saveDraft(pendingDraft) } catch { errorMessage = error.localizedDescription } }
        }
    }
}

private struct ActionChip: View {
    let title: String
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol).actionChip()
        }
    }
}

private extension View {
    /// A tinted pill that performs an action, as opposed to `chipStyle` which shows a
    /// selection. Shared so the picker and the buttons beside it cannot drift.
    func actionChip() -> some View {
        font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AppTheme.accentSoft)
            .foregroundStyle(AppTheme.accent)
            .clipShape(Capsule())
    }
}

private struct RecipeLinkImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""
    @State private var isLoading = false
    @State private var importTask: Task<Void, Never>?
    @State private var errorMessage: String?
    let imported: (ImportedRecipeDraft) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Recipe link") {
                    TextField("https://…", text: $urlText)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    Text("We read the standard format used by most recipe sites. You can always review the content before saving.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(AppTheme.warning) }
                }
                Section {
                    Button {
                        importTask = Task { await importURL() }
                    } label: {
                        HStack {
                            Text("Fetch recipe")
                            Spacer()
                            if isLoading { ProgressView() }
                        }
                    }
                    .disabled(isLoading || urlText.isEmpty)
                }
            }
            .onDisappear { importTask?.cancel() }
            .navigationTitle("Import from link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func importURL() async {
        guard let url = URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errorMessage = RecipeImportError.invalidURL.localizedDescription
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let draft = try await RecipeCapture.urlExtractor.extract(from: url)
            try Task.checkCancellation()
            imported(draft)
        } catch is CancellationError { }
        catch { errorMessage = error.localizedDescription }
    }
}
