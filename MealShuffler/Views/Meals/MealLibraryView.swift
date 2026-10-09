import PhotosUI
import SwiftUI

/// The household's cookbook: browsed by picture, narrowed by category, added to from wherever
/// a recipe happens to be.
///
/// It was a one-column list of 40 rows under a full-width "Add recipe" button, with filtering
/// in three places -- chips, a "Filter and sort" link and a "Manage collections" link, the last
/// two as plain blue text -- and a five-item menu whose longest label wrapped mid-word
/// ("oppskriftste-kst"). Picking dinner is a visual decision, so the dishes are a grid; the
/// rare filters sit behind one icon; and adding is a sheet of five short, parallel sources.
struct MealLibraryView: View {
    /// One value drives what is presented.
    ///
    /// Four booleans and two payload properties used to coordinate two sheets, and handing
    /// off from the link importer to the editor needed a 250ms timer to let the first sheet
    /// finish dismissing -- timing-dependent, and wrong on a slow device or with reduced
    /// motion. Changing the item swaps the sheet directly.
    private enum LibrarySheet: Identifiable {
        case addSource
        case editor(existing: Meal?, draft: ImportedRecipeDraft)
        case linkImport
        case paste(ImportedRecipeDraft)
        case detail(Meal)
        case photos(ImportedRecipeDraft)
        case capture(CapturedRecipe)

        var id: String {
            switch self {
            case .addSource: "add"
            case .editor(_, let draft): "editor-\(draft.id)"
            case .linkImport: "link"
            case .paste: "paste"
            case .detail(let meal): "detail-\(meal.id)"
            case .photos: "photos"
            case .capture(let capture): "capture-\(capture.id)"
            }
        }
    }

    /// Something full-screen to open once the add sheet has gone: the camera and the photo
    /// picker cannot be presented over a sheet that is still dismissing.
    private enum AfterDismiss { case scan, photos }

    @Environment(AppStore.self) private var store

    @State private var searchText = ""
    @State private var filter: MealFilter = .all
    @State private var category: MealTag?
    @State private var collection: String?
    @State private var reviewOnly = false
    @State private var sortOrder = 0
    @State private var customLabel: String?
    @State private var quickOnly = false
    @State private var sheet: LibrarySheet?
    @State private var afterDismiss: AfterDismiss?
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var drafts: [ImportedRecipeDraft] = []
    @State private var importError: String?
    @State private var isImportingPhoto = false
    @State private var isScanning = false
    @State private var isPickingPhotos = false
    @State private var showingCollections = false
    @State private var showingFreezer = false

    private let columns = [GridItem(.flexible(), spacing: AppTheme.Space.m), GridItem(.flexible(), spacing: AppTheme.Space.m)]

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

    /// Shelves are for browsing; while searching or filtering they only get in the way.
    private var isBrowsing: Bool {
        searchText.isEmpty && filter == .all && category == nil && collection == nil
            && customLabel == nil && !quickOnly && !reviewOnly
    }

    private var hasExtraFilters: Bool {
        collection != nil || customLabel != nil || reviewOnly || sortOrder != 0
    }

    var body: some View {
        libraryContent
            .appBackground()
            .navigationTitle("Meals")
            .searchable(text: $searchText, prompt: "Search meals")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { sheet = .addSource } label: {
                        if isImportingPhoto { ProgressView() } else { Image(systemName: "plus") }
                    }
                    .disabled(isImportingPhoto)
                    .accessibilityLabel("Add recipe")
                    .accessibilityIdentifier("meals.add")
                }
            }
            .sheet(item: $sheet, onDismiss: {
                reloadDrafts()
                switch afterDismiss {
                case .scan: isScanning = true
                case .photos: isPickingPhotos = true
                case nil: break
                }
                afterDismiss = nil
            }) { presented in
                sheetContent(presented)
            }
            .fullScreenCover(isPresented: $isScanning) { scanner }
            .photosPicker(isPresented: $isPickingPhotos, selection: $photoItems, maxSelectionCount: 5, matching: .images)
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
            LazyVStack(alignment: .leading, spacing: AppTheme.Space.l) {
                ForEach(drafts) { draft in draftRow(draft) }
                if !store.pendingCaptures.isEmpty { sharedCard }

                Picker("Show", selection: $filter) {
                    ForEach(MealFilter.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)

                chipRow

                if isBrowsing {
                    shelves
                }

                HStack(alignment: .firstTextBaseline) {
                    Text(isBrowsing ? L10n.string("All meals") : L10n.string("%ld meals", filteredMeals.count))
                        .font(AppTheme.Typography.section).foregroundStyle(AppTheme.ink)
                    Spacer()
                    sortMenu
                }

                let meals = filteredMeals
                if meals.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, spacing: AppTheme.Space.m) {
                        ForEach(meals) { meal in mealCard(meal) }
                    }
                }
                Color.clear.frame(height: AppTheme.Space.xl)
            }
            .padding(.horizontal, AppTheme.Space.screen)
            .padding(.top, AppTheme.Space.s)
        }
        .navigationDestination(isPresented: $showingCollections) { RecipeCollectionsView() }
        .navigationDestination(isPresented: $showingFreezer) { FreezerView() }
    }

    // MARK: - Filters

    /// Categories as chips, with the rare filters behind one icon at the start.
    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Space.s) {
                filterMenu
                Button {
                    withAnimation(.snappy) { quickOnly.toggle() }
                } label: {
                    Label("30 min or less", systemImage: "bolt")
                        .chipStyle(selected: quickOnly)
                }
                .buttonStyle(.plain)
                ForEach(MealTag.allCases.filter { $0 != .quick }) { tag in
                    Button {
                        withAnimation(.snappy) { category = category == tag ? nil : tag }
                    } label: {
                        Text(tag.name).chipStyle(selected: category == tag)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(category == tag ? [.isButton, .isSelected] : [.isButton])
                }
            }
            .padding(.vertical, AppTheme.Space.xxs)
        }
        .scrollClipDisabled()
    }

    private var filterMenu: some View {
        Menu {
            Picker("Collection", selection: $collection) {
                Text("All").tag(nil as String?)
                ForEach(store.householdTools.collections.keys.sorted(), id: \.self) { name in
                    Text(name).tag(name as String?)
                }
            }
            Picker("Label", selection: $customLabel) {
                Text("All").tag(nil as String?)
                ForEach(store.customTagsInUse, id: \.self) { name in Text(name).tag(name as String?) }
            }
            Toggle("Needs review", isOn: $reviewOnly)
            Button { showingCollections = true } label: {
                Label("Collections", systemImage: "folder")
            }
            // Always reachable, because the freezer screen is also where a batch is added.
            Button { showingFreezer = true } label: {
                Label("Freezer", systemImage: "snowflake")
            }
        } label: {
            Image(systemName: hasExtraFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                .chipStyle(selected: hasExtraFilters)
        }
        .accessibilityLabel("More filters")
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $sortOrder) {
                Text("Name").tag(0)
                Text("Quickest first").tag(1)
                Text("Recently updated").tag(2)
                Text("Longest since cooked").tag(3)
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
        }
    }

    // MARK: - Shelves

    /// "What have we not had in a while" -- the question History used to answer from a link
    /// below the week -- and what is waiting in the freezer.
    @ViewBuilder private var shelves: some View {
        let lastCooked = store.lastCookedByMeal
        let rotation = store.meals
            .filter { lastCooked[$0.id] != nil }
            .sorted { (lastCooked[$0.id] ?? .distantPast) < (lastCooked[$1.id] ?? .distantPast) }
            .prefix(8)
        if !rotation.isEmpty {
            VStack(alignment: .leading, spacing: AppTheme.Space.s) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Longest since cooked").font(AppTheme.Typography.section).foregroundStyle(AppTheme.ink)
                    Spacer()
                    NavigationLink { MealHistoryView() } label: {
                        Text("History").font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.accent)
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Space.m) {
                        ForEach(Array(rotation)) { meal in
                            mealCard(meal, note: lastCooked[meal.id].map {
                                L10n.string("Cooked %@", $0.formatted(.relative(presentation: .named)))
                            })
                            .frame(width: 150)
                        }
                    }
                    .padding(.vertical, AppTheme.Space.xxs)
                }
                .scrollClipDisabled()
            }
        }
        if !store.householdTools.freezer.isEmpty {
            NavigationLink { FreezerView() } label: {
                HStack(spacing: AppTheme.Space.m) {
                    Image(systemName: "snowflake")
                        .font(.title3).foregroundStyle(AppTheme.categoryFish)
                        .frame(width: AppTheme.tapTarget, height: AppTheme.tapTarget)
                        .background(AppTheme.categoryFish.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("In the freezer").font(.headline).foregroundStyle(AppTheme.ink)
                        Text(store.householdTools.freezer.map(\.recipe.name).joined(separator: ", "))
                            .font(.caption).foregroundStyle(AppTheme.muted).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(AppTheme.muted)
                }
                .padding(AppTheme.Space.m)
                .mealCard()
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Cards

    private func mealCard(_ meal: Meal, note: String? = nil) -> some View {
        let isFavorite = store.favoriteMealIDs.contains(meal.id)
        return ZStack(alignment: .topTrailing) {
            Button { sheet = .detail(meal) } label: {
                VStack(alignment: .leading, spacing: 0) {
                    MealArtwork(meal: meal)
                        .frame(height: 112)
                        .clipped()
                    VStack(alignment: .leading, spacing: 3) {
                        Text(meal.name)
                            .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.ink)
                            .lineLimit(2, reservesSpace: true)
                            .multilineTextAlignment(.leading)
                        Text(note ?? cardMetadata(meal))
                            .font(.caption).foregroundStyle(AppTheme.muted).lineLimit(1)
                    }
                    .padding(AppTheme.Space.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .mealCard()
            }
            .buttonStyle(.plain)
            .contextMenu { mealActions(meal) }
            .accessibilityLabel(L10n.string("View recipe: %@", meal.name))

            // Beside the card rather than inside it: a button inside a button's label does
            // not reliably get its own taps.
            Button { store.toggleFavorite(meal) } label: {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isFavorite ? AppTheme.destructive : AppTheme.ink)
                    .frame(width: 32, height: 32)
                    .background(AppTheme.surface.opacity(0.92))
                    .clipShape(Circle())
                    .frame(width: AppTheme.tapTarget, height: AppTheme.tapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFavorite ? L10n.string("Remove family favorite") : L10n.string("Mark as family favorite"))
        }
    }

    private func cardMetadata(_ meal: Meal) -> String {
        var parts: [String] = []
        if meal.prepMinutes > 0 { parts.append(L10n.string("%ld min", meal.prepMinutes)) }
        if !meal.isBuiltIn { parts.append(L10n.string("Your own")) }
        return parts.isEmpty ? L10n.string("Time not specified") : parts.joined(separator: " · ")
    }

    private func reloadDrafts() {
        drafts = RecipeLibraryStorage.drafts()
    }

    private func draftRow(_ draft: ImportedRecipeDraft) -> some View {
        HStack(spacing: AppTheme.Space.s) {
            Label(draft.name.isEmpty ? L10n.string("Unfinished recipe") : draft.name, systemImage: "doc.badge.clock")
                .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.ink).lineLimit(1)
            Spacer()
            Button("Resume") { resumeDraft(draft) }
                .buttonStyle(.secondary)
            Button {
                RecipeLibraryStorage.removeDraft(draft.id)
                reloadDrafts()
            } label: {
                Image(systemName: "xmark").foregroundStyle(AppTheme.muted).iconButtonFrame()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Discard")
        }
        .padding(.leading, AppTheme.Space.l)
        .padding(.vertical, AppTheme.Space.xs)
        .mealCard()
    }

    private func resumeDraft(_ draft: ImportedRecipeDraft) {
        if draft.name.isEmpty, !draft.sourceImages.isEmpty { sheet = .photos(draft) }
        else if draft.name.isEmpty, draft.sourceText != nil { sheet = .paste(draft) }
        else { sheet = .editor(existing: nil, draft: draft) }
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
        // A recipe travels to a friend inside the link: no account, nothing uploaded.
        if let link = RecipeShare.link(meals: [meal], household: store.household.name) {
            ShareLink(item: link, subject: Text(meal.name), message: Text(RecipeShare.message(meals: [meal], household: store.household.name))) {
                Label("Send to a friend", systemImage: "paperplane")
            }
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
        case .addSource:
            AddRecipeSheet(canScan: DocumentScannerView.isAvailable) { source in
                switch source {
                case .link: sheet = .linkImport
                case .paste: sheet = .paste(ImportedRecipeDraft())
                case .write: sheet = .editor(existing: nil, draft: ImportedRecipeDraft())
                case .scan: afterDismiss = .scan; sheet = nil
                case .photos: afterDismiss = .photos; sheet = nil
                }
            }
            .presentationDetents([.medium])
        case .capture(let capture):
            CapturedRecipeImportView(capture: capture) { draft in
                sheet = .editor(existing: nil, draft: draft)
            } cancel: { sheet = nil }
        case .editor(let existing, let draft):
            RecipeEditorView(existingMeal: existing, draft: draft).environment(store)
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

    /// One main action -- put it in the week -- and the rest behind "More".
    private func detailActions(_ meal: Meal) -> some View {
        HStack(spacing: AppTheme.Space.s) {
            Menu {
                ForEach(Weekday.ordered()) { day in
                    Button(day.name) { store.setMeal(meal, on: day); sheet = nil }
                }
            } label: {
                Label("Add to the week", systemImage: "calendar.badge.plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: AppTheme.tapTarget + 6)
                    .background(AppTheme.accent)
                    .foregroundStyle(AppTheme.onAccent)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
            }
            Button { sheet = .editor(existing: meal, draft: ImportedRecipeDraft()) } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.icon)
            .accessibilityLabel("Edit")
            moreActions(meal)
        }
        .padding(.horizontal, AppTheme.Space.l)
        .padding(.vertical, AppTheme.Space.s)
        .background(AppTheme.background)
    }

    private func moreActions(_ meal: Meal) -> some View {
        Menu {
            if let link = RecipeShare.link(meals: [meal], household: store.household.name) {
                ShareLink(item: link, subject: Text(meal.name), message: Text(RecipeShare.message(meals: [meal], household: store.household.name))) {
                    Label("Send to a friend", systemImage: "paperplane")
                }
            }
            Button("Save as a variant") { createVariant(of: meal) }
            if case .web(let url) = meal.source {
                Button("Update from source") { Task { await updateFromSource(meal, url: url) } }
            }
            revisionActions(meal)
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .frame(width: AppTheme.tapTarget, height: AppTheme.tapTarget)
                .background(AppTheme.raised)
                .foregroundStyle(AppTheme.ink)
                .clipShape(Circle())
        }
        .accessibilityLabel("More")
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

    /// What the share extension left behind, waiting to be turned into meals.
    private var sharedCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Space.m) {
            Label(
                store.pendingCaptures.count == 1
                    ? L10n.string("1 recipe shared to Meal Shuffler")
                    : L10n.string("%ld recipes shared to Meal Shuffler", store.pendingCaptures.count),
                systemImage: "tray.and.arrow.down"
            )
            .font(.headline).foregroundStyle(AppTheme.ink)

            ForEach(store.pendingCaptures) { capture in
                HStack(spacing: AppTheme.Space.s) {
                    Text(capture.summary)
                        .font(.subheadline).foregroundStyle(AppTheme.muted).lineLimit(1)
                    Spacer(minLength: AppTheme.Space.s)
                    Button("Add") { sheet = .capture(capture) }
                        .buttonStyle(.secondary)
                    Button { store.discardCapture(capture) } label: {
                        Image(systemName: "xmark").iconButtonFrame()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.muted)
                    .accessibilityLabel(L10n.string("Discard"))
                }
            }
        }
        .padding(AppTheme.Space.l)
        .mealCard()
    }

    private var emptyState: some View {
        VStack(spacing: AppTheme.Space.s) {
            Image(systemName: searchText.isEmpty ? "tray" : "magnifyingglass")
                .font(.largeTitle).foregroundStyle(AppTheme.accent)
            Text(emptyTitle)
                .font(.headline).foregroundStyle(AppTheme.ink).multilineTextAlignment(.center)
            Text(emptyDetail)
                .font(.subheadline).foregroundStyle(AppTheme.muted).multilineTextAlignment(.center)
            Button("Add recipe") { sheet = .addSource }
                .buttonStyle(.secondary)
                .padding(.top, AppTheme.Space.xs)
        }
        .frame(maxWidth: .infinity)
        .padding(AppTheme.Space.xl)
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

/// Where a recipe can come from, as five short, parallel choices.
///
/// The menu this replaces had uneven verb phrases, and its longest label -- "Lim inn
/// oppskriftstekst", one Norwegian compound -- hyphenated mid-word in a narrow menu.
struct AddRecipeSheet: View {
    enum Source { case link, paste, scan, photos, write }

    @Environment(\.dismiss) private var dismiss
    let canScan: Bool
    let choose: (Source) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Space.m) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: AppTheme.Space.s), GridItem(.flexible(), spacing: AppTheme.Space.s)],
                              spacing: AppTheme.Space.s) {
                        tile(.link, title: L10n.string("From a link"), detail: L10n.string("Recipe sites and blogs"), symbol: "link")
                        tile(.paste, title: L10n.string("Paste text"), detail: L10n.string("From a message or a note"), symbol: "doc.on.clipboard")
                        if canScan {
                            tile(.scan, title: L10n.string("Scan pages"), detail: L10n.string("A cookbook, up to five pages"), symbol: "doc.viewfinder")
                        }
                        tile(.photos, title: L10n.string("From photos"), detail: L10n.string("Screenshots and pictures"), symbol: "photo")
                    }
                    Button { choose(.write) } label: {
                        Label("Write it yourself", systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.secondaryFullWidth)
                    Text("Tip: in Safari, tap Share and choose Meal Shuffler.")
                        .font(.caption).foregroundStyle(AppTheme.muted)
                        .frame(maxWidth: .infinity)
                }
                .padding(AppTheme.Space.l)
            }
            .navigationTitle("Add recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("addRecipe.cancel") }
            }
        }
    }

    private func tile(_ source: Source, title: String, detail: String, symbol: String) -> some View {
        Button { choose(source) } label: {
            VStack(alignment: .leading, spacing: AppTheme.Space.xs) {
                Image(systemName: symbol).font(.title3).foregroundStyle(AppTheme.accent)
                Text(title).font(.headline).foregroundStyle(AppTheme.ink)
                Text(detail).font(.caption).foregroundStyle(AppTheme.muted)
                    .lineLimit(2, reservesSpace: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppTheme.Space.m)
            .background(AppTheme.background)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
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
