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
        let collectionIDs = collection.flatMap { store.householdTools.collections[$0] }
        let matches: [Meal] = store.meals.filter { meal in
            matchesFilters(meal, collectionIDs: collectionIDs)
        }
        let lastCooked: [UUID: Date] = sortOrder == 3 ? store.lastCookedByMeal : [:]
        return matches.sorted { left, right in
            comesBefore(left, right, lastCooked: lastCooked)
        }
    }

    private func matchesFilters(_ meal: Meal, collectionIDs: Set<UUID>?) -> Bool {
        guard filter.matches(meal, favorites: store.favoriteMealIDs),
              meal.matches(searchText: searchText) else { return false }
        if let category, !meal.tags.contains(category) { return false }
        if collection != nil, collectionIDs?.contains(meal.id) != true { return false }
        if let customLabel, !meal.customTags.contains(customLabel) { return false }
        if quickOnly, meal.prepMinutes <= 0 || meal.prepMinutes > 30 { return false }
        if reviewOnly {
            let needsReview = meal.servingsConfirmed == false || meal.prepMinutes <= 0
                || meal.ingredients.contains(where: { $0.needsAmountReview })
            if !needsReview { return false }
        }
        return true
    }

    private func comesBefore(_ left: Meal, _ right: Meal, lastCooked: [UUID: Date]) -> Bool {
        switch sortOrder {
        case 1:
            let leftMinutes = left.prepMinutes > 0 ? left.prepMinutes : Int.max
            let rightMinutes = right.prepMinutes > 0 ? right.prepMinutes : Int.max
            return leftMinutes < rightMinutes
        case 2:
            return left.updatedAt > right.updatedAt
        case 3:
            let leftDate = lastCooked[left.id] ?? Date.distantPast
            let rightDate = lastCooked[right.id] ?? Date.distantPast
            return leftDate < rightDate
        default:
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
    }

    var body: some View {
        libraryContent
            .appBackground()
            .navigationTitle("Meals")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search meals")
            .sheet(item: $sheet, onDismiss: reloadDrafts) { presented in
                sheetContent(presented)
            }
            .fullScreenCover(isPresented: $isScanning) { scanner }
            .alert("Import stopped", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? L10n.string("Unknown error"))
            }
            .onAppear(perform: reloadDrafts)
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task { @MainActor in await importPhotos(items) }
            }
    }

    private var libraryContent: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                actionCard
                ForEach(drafts) { draft in draftRow(draft) }
                if !store.pendingCaptures.isEmpty { sharedCard }
                filterRow
                filterMenu
                NavigationLink("Manage collections") { RecipeCollectionsView() }
                mealList
                Color.clear.frame(height: 20)
            }
            .padding(16)
        }
    }

    private func reloadDrafts() {
        drafts = RecipeLibraryStorage.drafts()
    }

    private func draftRow(_ draft: ImportedRecipeDraft) -> some View {
        HStack {
            Label(draft.name.isEmpty ? L10n.string("Unfinished recipe") : draft.name, systemImage: "doc.badge.clock")
            Spacer()
            Button("Resume") { resumeDraft(draft) }
            Button("Discard", role: .destructive) {
                RecipeLibraryStorage.removeDraft(draft.id)
                reloadDrafts()
            }
        }.padding().mealCard()
    }

    private func resumeDraft(_ draft: ImportedRecipeDraft) {
        if draft.name.isEmpty, !draft.sourceImages.isEmpty { sheet = .photos(draft) }
        else if draft.name.isEmpty, draft.sourceText != nil { sheet = .paste(draft) }
        else { sheet = .editor(existing: nil, draft: draft) }
    }

    private var filterMenu: some View {
        Menu("Filter and sort") {
            categoryPicker
            collectionPicker
            Toggle("Needs review", isOn: $reviewOnly)
            Toggle("30 minutes or less", isOn: $quickOnly)
            labelPicker
            sortPicker
        }
    }

    private var categoryPicker: some View {
        Picker("Category", selection: $category) {
            Text("All").tag(nil as MealTag?)
            ForEach(MealTag.allCases) { tag in Text(tag.name).tag(tag as MealTag?) }
        }
    }

    private var collectionPicker: some View {
        Picker("Collection", selection: $collection) {
            Text("All").tag(nil as String?)
            ForEach(store.householdTools.collections.keys.sorted(), id: \.self) { name in
                Text(name).tag(name as String?)
            }
        }
    }

    private var labelPicker: some View {
        Picker("Label", selection: $customLabel) {
            Text("All").tag(nil as String?)
            ForEach(store.customTagsInUse, id: \.self) { name in Text(name).tag(name as String?) }
        }
    }

    private var sortPicker: some View {
        Picker("Sort", selection: $sortOrder) {
            Text("Name").tag(0)
            Text("Quickest first").tag(1)
            Text("Recently updated").tag(2)
            Text("Longest since cooked").tag(3)
        }
    }

    @ViewBuilder private var mealList: some View {
        let meals = filteredMeals
        if meals.isEmpty { emptyState }
        ForEach(meals) { meal in libraryRow(meal) }
    }

    private func libraryRow(_ meal: Meal) -> some View {
        MealRow(
            meal: meal,
            isFavorite: store.favoriteMealIDs.contains(meal.id),
            toggleFavorite: { store.toggleFavorite(meal) }
        )
        .mealCard()
        .contentShape(Rectangle())
        .onTapGesture { sheet = .detail(meal) }
        .contextMenu { mealActions(meal) }
    }

    @ViewBuilder private func mealActions(_ meal: Meal) -> some View {
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
            Link(destination: link) { Label("Add to Bring!", systemImage: "cart.badge.plus") }
        }
        Button(meal.isBuiltIn ? L10n.string("Hide recipe") : L10n.string("Delete"), role: .destructive) {
            store.deleteMeal(meal)
        }
        if SampleMeals.all.contains(where: { $0.id == meal.id }), !meal.isBuiltIn {
            Button("Reset to original") { store.resetRecipeToOriginal(meal) }
        }
    }

    @ViewBuilder private func sheetContent(_ presented: LibrarySheet) -> some View {
        switch presented {
        case .capture(let capture):
            CapturedRecipeImportView(capture: capture) { draft in
                sheet = .editor(existing: nil, draft: draft)
            } cancel: { sheet = nil }
        case .editor(let existing, let draft):
            RecipeEditorView(existingMeal: existing, draft: draft).environmentObject(store)
        case .linkImport:
            RecipeLinkImportView { draft in sheet = .editor(existing: nil, draft: draft) }
        case .paste(let draft):
            PasteRecipeView(draft: draft) { imported in sheet = .editor(existing: nil, draft: imported) }
        case .photos(let draft):
            PhotoRecipeImportView(draft: draft) { imported in sheet = .editor(existing: nil, draft: imported) }
        case .detail(let meal):
            MealDetailView(meal: meal).safeAreaInset(edge: .bottom) { detailActions(meal) }
        }
    }

    private func detailActions(_ meal: Meal) -> some View {
        HStack {
            Button("Edit") { sheet = .editor(existing: meal, draft: ImportedRecipeDraft()) }
            Menu("Plan") {
                ForEach(Weekday.ordered()) { day in
                    Button(day.name) { store.setMeal(meal, on: day); sheet = nil }
                }
            }
            moreActions(meal)
        }
        .buttonStyle(.bordered).padding().frame(maxWidth: .infinity).background(AppTheme.background)
    }

    private func moreActions(_ meal: Meal) -> some View {
        Menu("More") {
            Button("Save as a variant") { createVariant(of: meal) }
            if case .web(let url) = meal.source {
                Button("Update from source") { Task { await updateFromSource(meal, url: url) } }
            }
            revisionActions(meal)
        }
    }

    private func revisionActions(_ meal: Meal) -> some View {
        let revisions = Array(RecipeLibraryStorage.revisions(for: meal.id).enumerated())
        return ForEach(revisions, id: \.offset) { revision in
            let previous = revision.element
            Button(L10n.string("Restore version from %@", previous.updatedAt.formatted())) {
                if store.saveMeal(previous) { sheet = .detail(previous) }
            }
        }
    }

    private func createVariant(of meal: Meal) {
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

    private func updateFromSource(_ meal: Meal, url: URL) async {
        do {
            var draft = try await RecipeCapture.urlExtractor.extract(from: url)
            draft.updatingMealID = meal.id
            draft.customTags = meal.customTags
            sheet = .editor(existing: nil, draft: draft)
        } catch { importError = error.localizedDescription }
    }

    private var scanner: some View {
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
