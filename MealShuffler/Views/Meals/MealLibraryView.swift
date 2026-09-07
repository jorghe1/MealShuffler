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

        var id: String {
            switch self {
            case .editor(let existing, _): "editor-\(existing?.id.uuidString ?? "new")"
            case .linkImport: "link"
            }
        }
    }

    @EnvironmentObject private var store: AppStore
    @State private var searchText = ""
    @State private var sheet: LibrarySheet?
    @State private var importing: CapturedRecipe?
    @State private var photoItem: PhotosPickerItem?
    @State private var importError: String?
    @State private var isImportingPhoto = false

    private var filteredMeals: [Meal] {
        guard !searchText.isEmpty else { return store.meals }
        return store.meals.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.tags.contains(where: { $0.name.localizedCaseInsensitiveContains(searchText) })
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                actionCard
                if !store.pendingCaptures.isEmpty { sharedCard }
                if filteredMeals.isEmpty && !searchText.isEmpty { emptyState }
                ForEach(filteredMeals) { meal in
                    MealLibraryRow(meal: meal, isFavorite: store.favoriteMealIDs.contains(meal.id)) {
                        store.toggleFavorite(meal)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { sheet = .editor(existing: meal, draft: ImportedRecipeDraft()) }
                    .contextMenu {
                        Button(store.favoriteMealIDs.contains(meal.id)
                            ? L10n.string("Remove family favorite")
                            : L10n.string("Mark as family favorite")) {
                            store.toggleFavorite(meal)
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
        .navigationTitle("My meals")
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
            }
        }
        .alert("Import stopped", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(importError ?? L10n.string("Unknown error")) }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await importPhoto(item) }
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
            Image(systemName: "magnifyingglass").font(.system(.largeTitle)).foregroundStyle(AppTheme.accent)
            Text(L10n.string("No meals match “%@”", searchText))
                .font(.headline).foregroundStyle(AppTheme.ink).multilineTextAlignment(.center)
            Text("Try another word, or add it as a new meal.")
                .font(.subheadline).foregroundStyle(AppTheme.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(30)
        .mealCard()
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

            HStack(spacing: 9) {
                ActionChip(title: L10n.string("New"), symbol: "plus") {
                    sheet = .editor(existing: nil, draft: ImportedRecipeDraft())
                }
                ActionChip(title: L10n.string("Link"), symbol: "link") { sheet = .linkImport }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Photo", systemImage: "text.viewfinder")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(AppTheme.accentSoft)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(18)
        .mealCard()
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
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(AppTheme.accentSoft)
                .clipShape(Capsule())
        }
    }
}

private struct MealLibraryRow: View {
    let meal: Meal
    let isFavorite: Bool
    let toggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: 13) {
            Text(meal.emoji)
                .font(.system(size: 34))
                .frame(width: 58, height: 58)
                .background(AppTheme.accentSoft.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(meal.name).font(.headline).lineLimit(1)
                    if !meal.isBuiltIn {
                        Text("MINE").font(.caption2.bold()).foregroundStyle(AppTheme.accent)
                    }
                }
                Text(L10n.string("%ld min · %ld servings", meal.prepMinutes, meal.defaultServings))
                    .font(.caption).foregroundStyle(AppTheme.muted)
            }
            Spacer()
            Button(action: toggleFavorite) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .foregroundStyle(isFavorite ? AppTheme.destructive : AppTheme.muted)
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                isFavorite ? L10n.string("Remove family favorite") : L10n.string("Mark as family favorite")
            )
        }
        .padding(12)
        .mealCard()
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
