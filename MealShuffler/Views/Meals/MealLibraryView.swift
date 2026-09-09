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
        case paste

        var id: String {
            switch self {
            case .editor(let existing, _): "editor-\(existing?.id.uuidString ?? "new")"
            case .linkImport: "link"
            case .paste: "paste"
            }
        }
    }

    @EnvironmentObject private var store: AppStore

    @State private var searchText = ""
    @State private var filter: MealFilter = .all
    @State private var sheet: LibrarySheet?
    @State private var importing: CapturedRecipe?
    @State private var photoItem: PhotosPickerItem?
    @State private var importError: String?
    @State private var isImportingPhoto = false
    @State private var isScanning = false

    private var filteredMeals: [Meal] {
        store.meals
            .filter { filter.matches($0, favorites: store.favoriteMealIDs) }
            .filter { $0.matches(searchText: searchText) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                actionCard
                if !store.pendingCaptures.isEmpty { sharedCard }
                filterRow
                if filteredMeals.isEmpty { emptyState }
                ForEach(filteredMeals) { meal in
                    MealRow(
                        meal: meal,
                        isFavorite: store.favoriteMealIDs.contains(meal.id),
                        toggleFavorite: { store.toggleFavorite(meal) }
                    )
                    .mealCard()
                    .contentShape(Rectangle())
                    .onTapGesture { sheet = .editor(existing: meal, draft: ImportedRecipeDraft()) }
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
                        if !meal.isBuiltIn {
                            Button("Delete", role: .destructive) { store.deleteMeal(meal) }
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
        .sheet(item: $importing) { capture in
            CapturedRecipeImportView(capture: capture) { draft in
                store.discardCapture(capture)
                importing = nil
                sheet = .editor(existing: nil, draft: draft)
            } cancel: {
                importing = nil
            }
        }
        .sheet(item: $sheet) { presented in
            switch presented {
            case .editor(let existing, let draft):
                RecipeEditorView(existingMeal: existing, draft: draft)
                    .environmentObject(store)
            case .linkImport:
                RecipeLinkImportView { imported in
                    sheet = .editor(existing: nil, draft: imported)
                }
            case .paste:
                PasteRecipeView { imported in
                    sheet = .editor(existing: nil, draft: imported)
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
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { @MainActor in await importPhoto(item) }
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
                    Button("Add") { importing = capture }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.bordered)
                    Button { store.discardCapture(capture) } label: {
                        Image(systemName: "xmark")
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
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Build your family's menu")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                    Text("A meal can be complete or simply a name with ingredients.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer()
                if isImportingPhoto { ProgressView() }
            }

            // Five ways in, because a recipe arrives in five ways: typed, a link, a photo
            // already on the phone, a page on the counter, and text copied from a message.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    ActionChip(title: L10n.string("New"), symbol: "plus") {
                        sheet = .editor(existing: nil, draft: ImportedRecipeDraft())
                    }
                    ActionChip(title: L10n.string("Link"), symbol: "link") { sheet = .linkImport }
                    if DocumentScannerView.isAvailable {
                        ActionChip(title: L10n.string("Scan"), symbol: "doc.viewfinder") { isScanning = true }
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Photo", systemImage: "text.viewfinder").actionChip()
                    }
                    ActionChip(title: L10n.string("Paste"), symbol: "doc.on.clipboard") { sheet = .paste }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
        .padding(18)
        .mealCard()
    }

    /// A scan can be several pages of one recipe, which is why it is not the photo path.
    private func importScan(_ pages: [Data]) async {
        isImportingPhoto = true
        defer { isImportingPhoto = false }
        do {
            sheet = .editor(existing: nil, draft: try await RecipeCapture.extract(fromImages: pages))
        } catch {
            importError = error.localizedDescription
        }
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        isImportingPhoto = true
        defer { isImportingPhoto = false; photoItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw RecipeImportError.unreadableImage
            }
            sheet = .editor(existing: nil, draft: try await RecipeCapture.imageExtractor.extract(fromImage: data))
        } catch {
            importError = error.localizedDescription
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
                        Task { await importURL() }
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
        do { imported(try await RecipeCapture.urlExtractor.extract(from: url)) }
        catch { errorMessage = error.localizedDescription }
    }
}
