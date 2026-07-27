import PhotosUI
import SwiftUI

struct MealLibraryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var searchText = ""
    @State private var showingEditor = false
    @State private var showingLinkImporter = false
    @State private var editingMeal: Meal?
    @State private var draft = ImportedRecipeDraft()
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
                ForEach(filteredMeals) { meal in
                    MealLibraryRow(meal: meal, isFavorite: store.favoriteMealIDs.contains(meal.id)) {
                        store.toggleFavorite(meal)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editingMeal = meal
                        draft = ImportedRecipeDraft()
                        showingEditor = true
                    }
                    .contextMenu {
                        Button(store.favoriteMealIDs.contains(meal.id) ? "Fjern familiefavoritt" : "Merk som familiefavoritt") {
                            store.toggleFavorite(meal)
                        }
                        if !meal.isBuiltIn {
                            Button("Slett", role: .destructive) { store.deleteMeal(meal) }
                        }
                    }
                }
                Color.clear.frame(height: 20)
            }
            .padding(16)
        }
        .appBackground()
        .navigationTitle("Mine retter")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Søk i retter")
        .sheet(isPresented: $showingEditor) {
            RecipeEditorView(existingMeal: editingMeal, draft: draft)
                .environmentObject(store)
        }
        .sheet(isPresented: $showingLinkImporter) {
            RecipeLinkImportView { imported in
                showingLinkImporter = false
                editingMeal = nil
                draft = imported
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { showingEditor = true }
            }
        }
        .alert("Importen stoppet", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(importError ?? "Ukjent feil") }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await importPhoto(item) }
        }
    }

    private var actionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bygg familiens meny")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("En rett kan være komplett eller bare et navn med ingredienser.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer()
                if isImportingPhoto { ProgressView() }
            }

            HStack(spacing: 9) {
                ActionChip(title: "Ny", symbol: "plus") {
                    editingMeal = nil
                    draft = ImportedRecipeDraft()
                    showingEditor = true
                }
                ActionChip(title: "Lenke", symbol: "link") { showingLinkImporter = true }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Bilde", systemImage: "text.viewfinder")
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
            guard let data = try await item.loadTransferable(type: Data.self) else { throw RecipeImportError.unreadableImage }
            draft = try await RecipeOCRService().recognizeRecipe(from: data)
            editingMeal = nil
            showingEditor = true
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
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(meal.name).font(.headline).lineLimit(1)
                    if !meal.isBuiltIn {
                        Text("MIN").font(.caption2.bold()).foregroundStyle(AppTheme.accent)
                    }
                }
                Text("\(meal.prepMinutes) min · \(meal.defaultServings) porsjoner")
                    .font(.caption).foregroundStyle(AppTheme.muted)
            }
            Spacer()
            Button(action: toggleFavorite) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .foregroundStyle(isFavorite ? .red : AppTheme.muted)
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
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
                Section("Oppskriftslenke") {
                    TextField("https://…", text: $urlText)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    Text("Vi leser standardformatet som de fleste oppskriftssider bruker. Du får alltid kontrollere innholdet før lagring.")
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
                            Text("Hent oppskrift")
                            Spacer()
                            if isLoading { ProgressView() }
                        }
                    }
                    .disabled(isLoading || urlText.isEmpty)
                }
            }
            .navigationTitle("Importer fra lenke")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Avbryt") { dismiss() } } }
        }
    }

    private func importURL() async {
        guard let url = URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errorMessage = RecipeImportError.invalidURL.localizedDescription
            return
        }
        isLoading = true
        defer { isLoading = false }
        do { imported(try await RecipeImportService().importRecipe(from: url)) }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct RecipeEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let existingMeal: Meal?
    let originalSource: MealSource

    @State private var name: String
    @State private var subtitle: String
    @State private var emoji: String
    @State private var prepMinutes: Int
    @State private var servings: Int
    @State private var estimatedCost: Int
    @State private var ingredientText: String
    @State private var instructionText: String
    @State private var tags: Set<MealTag>

    init(existingMeal: Meal?, draft: ImportedRecipeDraft) {
        self.existingMeal = existingMeal
        originalSource = existingMeal?.source ?? draft.source
        _name = State(initialValue: existingMeal?.name ?? draft.name)
        _subtitle = State(initialValue: existingMeal?.subtitle ?? draft.subtitle)
        _emoji = State(initialValue: existingMeal?.emoji ?? draft.emoji)
        _prepMinutes = State(initialValue: existingMeal?.prepMinutes ?? draft.prepMinutes)
        _servings = State(initialValue: existingMeal?.defaultServings ?? draft.servings)
        _estimatedCost = State(initialValue: existingMeal?.estimatedCostNOK ?? 0)
        let ingredients = existingMeal?.ingredients.map {
            "\($0.quantity.formatted(.number.precision(.fractionLength(0...2)))) \($0.unit) \($0.name)"
        } ?? draft.ingredientLines
        _ingredientText = State(initialValue: ingredients.joined(separator: "\n"))
        _instructionText = State(initialValue: (existingMeal?.instructions ?? draft.instructions).joined(separator: "\n"))
        _tags = State(initialValue: existingMeal?.tags ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Retten") {
                    HStack {
                        TextField("🍽️", text: $emoji).frame(width: 44)
                        TextField("Navn på retten", text: $name)
                    }
                    TextField("Kort beskrivelse (valgfritt)", text: $subtitle)
                    Stepper("Ca. \(prepMinutes) minutter", value: $prepMinutes, in: 5...240, step: 5)
                    Stepper("\(servings) porsjoner", value: $servings, in: 1...20)
                    Stepper(estimatedCost == 0 ? "Pris ikke satt" : "Ca. \(estimatedCost) kr totalt", value: $estimatedCost, in: 0...2_000, step: 25)
                }

                Section("Kategorier") {
                    TagCloud(selected: $tags)
                }

                Section("Ingredienser – én per linje") {
                    TextEditor(text: $ingredientText).frame(minHeight: 150)
                    Text("Eksempel: 500 g kyllingfilet").font(.caption).foregroundStyle(.secondary)
                }

                Section("Fremgangsmåte – ett steg per linje") {
                    TextEditor(text: $instructionText).frame(minHeight: 120)
                }
            }
            .navigationTitle(existingMeal == nil ? "Ny rett" : (isEditingBuiltIn ? "Tilpass rett" : "Rediger rett"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Avbryt") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lagre") { save() }.fontWeight(.semibold).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let lines = ingredientText.components(separatedBy: .newlines)
        let meal = Meal(
            id: isEditingBuiltIn ? UUID() : (existingMeal?.id ?? UUID()),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            subtitle: subtitle,
            emoji: emoji.isEmpty ? "🍽️" : emoji,
            prepMinutes: prepMinutes,
            tags: tags,
            ingredients: IngredientParser.parse(lines: lines),
            defaultServings: servings,
            estimatedCostNOK: estimatedCost == 0 ? nil : estimatedCost,
            instructions: instructionText.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty },
            source: isEditingBuiltIn ? .manual : originalSource
        )
        store.saveMeal(meal)
        dismiss()
    }

    private var isEditingBuiltIn: Bool {
        if case .builtIn = originalSource { return existingMeal != nil }
        return false
    }
}

private struct TagCloud: View {
    @Binding var selected: Set<MealTag>
    let columns = [GridItem(.adaptive(minimum: 95), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(MealTag.allCases) { tag in
                Button {
                    if selected.contains(tag) { selected.remove(tag) } else { selected.insert(tag) }
                } label: {
                    Label(tag.name, systemImage: tag.symbol)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(selected.contains(tag) ? AppTheme.accent : Color.secondary.opacity(0.1))
                        .foregroundStyle(selected.contains(tag) ? .white : AppTheme.ink)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
