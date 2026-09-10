import SwiftUI

struct RecipeEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let existingMeal: Meal?
    let originalSource: MealSource
    private let importedIngredients: [Ingredient]?
    private let importedIngredientText: String
    private let heroImageURL: URL?
    private let needsReview: Bool
    private let initialDraft: ImportedRecipeDraft
    private let sourceImages: [Data]
    @State private var ingredientEdits: [String: Ingredient] = [:]
    @State private var editingIngredient: Ingredient?
    @State private var photoIndex: Int?
    @State private var activeMinutes: Int
    @State private var knownActiveTime: Bool
    @State private var replacement: Meal?
    @State private var servingsConfirmed: Bool
    @State private var timingConfirmed: Bool
    @State private var didSave = false
    @State private var saveError: String?

    @State private var name: String
    @State private var subtitle: String
    @State private var emoji: String
    @State private var prepMinutes: Int
    @State private var servings: Int
    @State private var ingredientText: String
    @State private var instructionText: String
    @State private var tags: Set<MealTag>
    @State private var customTags: Set<String>
    @State private var newCustomTag = ""
    /// Aisle corrections, keyed by the parsed ingredient's own id.
    @State private var aisleOverrides: [String: GroceryAisle] = [:]

    init(existingMeal: Meal?, draft: ImportedRecipeDraft) {
        self.existingMeal = existingMeal
        initialDraft = draft
        sourceImages = draft.sourceImages.isEmpty ? (existingMeal?.sourceImageNames ?? []).compactMap { RecipeLibraryStorage.image(named: $0) } : draft.sourceImages
        _activeMinutes = State(initialValue: existingMeal?.activeMinutes ?? draft.activeMinutes ?? 15)
        _knownActiveTime = State(initialValue: (existingMeal?.activeMinutes ?? draft.activeMinutes) != nil)
        _replacement = State(initialValue: existingMeal)
        _timingConfirmed = State(initialValue: existingMeal != nil || draft.timingNeedsReview != true)
        _servingsConfirmed = State(initialValue: existingMeal?.servingsConfirmed ?? (existingMeal != nil || draft.servingsConfirmed))
        originalSource = existingMeal?.source ?? draft.source
        importedIngredients = existingMeal?.ingredients ?? draft.parsedIngredients
        heroImageURL = existingMeal?.heroImageURL ?? draft.heroImageURL
        needsReview = existingMeal == nil && draft.needsReview
        _name = State(initialValue: existingMeal?.name ?? draft.name)
        _subtitle = State(initialValue: existingMeal?.subtitle ?? draft.subtitle)
        _emoji = State(initialValue: existingMeal?.emoji ?? draft.emoji)
        _prepMinutes = State(initialValue: existingMeal?.prepMinutes ?? draft.prepMinutes)
        _servings = State(initialValue: existingMeal?.defaultServings ?? draft.servings)
        let ingredients = existingMeal?.ingredients.map(\.editableLine) ?? draft.ingredientLines
        let joinedIngredients = ingredients.joined(separator: "\n")
        importedIngredientText = joinedIngredients
        _ingredientText = State(initialValue: joinedIngredients)
        _instructionText = State(initialValue: (existingMeal?.instructions ?? draft.instructions).joined(separator: "\n"))
        _tags = State(initialValue: existingMeal?.tags ?? draft.tags)
        _customTags = State(initialValue: existingMeal?.customTags ?? draft.customTags)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let note = initialDraft.extractionNote { Section { Text(note).font(.caption) } }
                if needsReview {
                    Section {
                        Label("Read automatically — check the details before saving.",
                              systemImage: "exclamationmark.circle")
                            .font(.subheadline).foregroundStyle(AppTheme.warning)
                    }
                }
                if let duplicate {
                    Section {
                        Label(
                            L10n.string("You already have a meal called “%@”.", duplicate.name),
                            systemImage: "doc.on.doc"
                        )
                        .font(.subheadline).foregroundStyle(AppTheme.warning)
                        Button("Update this recipe") {
                            replacement = duplicate
                            customTags.formUnion(duplicate.customTags)
                        }
                        Button("Save as a variant") { replacement = nil }
                        if replacement?.id == duplicate.id {
                            Text("The existing recipe will be updated. Its previous version can be restored.")
                            DisclosureGroup("Compare with existing recipe") {
                                ForEach(duplicate.ingredients) { ingredient in Text(ingredient.editableLine) }
                                Text(duplicate.instructions.joined(separator: "\n"))
                            }
                            Button("Keep existing ingredients") { ingredientText = duplicate.ingredients.map(\.editableLine).joined(separator: "\n") }
                            Button("Keep existing instructions") { instructionText = duplicate.instructions.joined(separator: "\n") }
                        }
                    }
                }
                if !servingsConfirmed || !timingConfirmed { Section { Text("Check the original servings and total time to save this recipe. You can save a draft and finish later.") } }
                if let saveError { Section { Text(saveError).foregroundStyle(AppTheme.warning) } }
                sourceSection
                if let heroImageURL {
                    Section {
                        AsyncImage(url: heroImageURL) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            default:
                                // No placeholder chrome: a missing image should not look broken.
                                Color.clear
                            }
                        }
                        .frame(height: 160)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .listRowInsets(EdgeInsets())
                        .accessibilityHidden(true)
                    }
                }
                Section("Meal") {
                    HStack {
                        TextField("🍽️", text: $emoji).frame(width: 44)
                        TextField("Meal name", text: $name)
                    }
                    TextField("Short description (optional)", text: $subtitle)
                    LabeledContent("Total elapsed time") { TextField("Minutes", value: $prepMinutes, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                    Toggle("Active time known", isOn: $knownActiveTime)
                    if knownActiveTime { LabeledContent("Hands-on minutes") { TextField("Minutes", value: $activeMinutes, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing) } }
                    if needsReview || !timingConfirmed {
                        Toggle("Total time checked", isOn: $timingConfirmed)
                        if !timingConfirmed { Text("Total time was not supplied. Enter and check the time before using this recipe in time-limited plans.").font(.caption) }
                    }
                    LabeledContent("Original servings") { TextField("Servings", value: $servings, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                    Toggle("Original serving count checked", isOn: $servingsConfirmed)
                    if !servingsConfirmed { Text("Check the original yield before using scaled shopping quantities.").font(.caption) }
                }

                Section("Categories") {
                    TagCloud(selected: $tags)
                }

                labelSection

                Section("Ingredients – one per line") {
                    TextEditor(text: $ingredientText).frame(minHeight: 150)
                    Text("Example: 500 g chicken breast").font(.caption).foregroundStyle(.secondary)
                }

                ingredientPreview

                Section("Instructions – one step per line") {
                    TextEditor(text: $instructionText).frame(minHeight: 120)
                }
            }
            .navigationTitle(
                existingMeal == nil
                    ? L10n.string("New meal")
                    : (isEditingBuiltIn ? L10n.string("Customize meal") : L10n.string("Edit meal"))
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Save draft") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save recipe") { save() }.fontWeight(.semibold).disabled(resolvedIngredients.contains(where: { $0.requiresReview == true }) || name.trimmingCharacters(in: .whitespaces).isEmpty || !servingsConfirmed || !timingConfirmed || !(1...1000).contains(servings) || !(1...10080).contains(prepMinutes) || (knownActiveTime && !(1...prepMinutes).contains(activeMinutes)))
                }
            }
        }
        .task(id: draftIdentity) {
            do {
                try await Task.sleep(for: .milliseconds(500))
                guard !didSave else { return }
                let snapshot = currentDraft
                let revision = RecipeLibraryStorage.beginDraftSave(snapshot.id)
                try await Task.detached { try RecipeLibraryStorage.saveDraft(snapshot, revision: revision) }.value
            } catch is CancellationError { }
            catch { saveError = error.localizedDescription }
        }
        .sheet(item: $editingIngredient) { ingredient in
            IngredientEditorView(ingredient: ingredient) { ingredientEdits[ingredient.id] = $0 }
        }
        .sheet(isPresented: Binding(get: { photoIndex != nil }, set: { if !$0 { photoIndex = nil } })) {
            if let index = photoIndex, sourceImages.indices.contains(index) { SourcePhotoView(data: sourceImages[index]) }
        }
        .onAppear {
            if replacement == nil, let id = initialDraft.updatingMealID { replacement = store.meal(id: id) }
        }
        .onDisappear {
            if !didSave { do { try RecipeLibraryStorage.saveDraft(currentDraft) } catch { store.persistenceError = error.localizedDescription } }
        }
    }

    private var sourceSection: some View {
        Section {
            DisclosureGroup("Original source") {
                if case .web(let url) = originalSource { Link("Open recipe website", destination: url) }
                if let text = initialDraft.sourceText ?? existingMeal?.sourceText { Text(text).font(.caption).textSelection(.enabled) }
                ForEach(Array(sourceImages.enumerated()), id: \.offset) { index, data in
                    if let image = UIImage(data: data) { Button { photoIndex = index } label: { Image(uiImage: image).resizable().scaledToFit() }.accessibilityLabel("Enlarge source photo") }
                }
            }
        }
    }

    private var draftIdentity: ImportedRecipeDraft {
        var draft = currentDraft; draft.sourceImages = []; return draft
    }

    private var currentDraft: ImportedRecipeDraft {
        var draft = initialDraft
        draft.name = name; draft.subtitle = subtitle; draft.emoji = emoji
        draft.prepMinutes = prepMinutes; draft.servings = servings
        draft.ingredientLines = ingredientText.components(separatedBy: .newlines)
        draft.parsedIngredients = resolvedIngredients
        draft.instructions = instructionText.components(separatedBy: .newlines)
        draft.tags = tags; draft.customTags = customTags
        draft.servingsConfirmed = servingsConfirmed
        draft.updatingMealID = replacement?.id
        draft.source = originalSource
        draft.heroImageURL = heroImageURL
        draft.sourceText = initialDraft.sourceText ?? existingMeal?.sourceText
        draft.sourceImages = sourceImages
        draft.activeMinutes = knownActiveTime ? activeMinutes : nil
        draft.timingNeedsReview = !timingConfirmed
        return draft
    }

    /// Labels beyond the fixed ten, so a rule can be written about them.
    private var labelSection: some View {
        Section {
            if !customTags.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(customTags.sorted(), id: \.self) { label in
                        Button {
                            customTags.remove(label)
                        } label: {
                            HStack(spacing: 5) {
                                Text(label).lineLimit(1)
                                Image(systemName: "xmark.circle.fill").font(.caption2)
                            }
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(AppTheme.accentSoft)
                            .foregroundStyle(AppTheme.accent)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.string("Remove the label %@", label))
                    }
                }
            }
            HStack {
                TextField("Add a label", text: $newCustomTag)
                    .textInputAutocapitalization(.never)
                    .onSubmit(addCustomTag)
                Button("Add", action: addCustomTag)
                    .disabled(newCustomTag.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if !suggestedLabels.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestedLabels, id: \.self) { label in
                            Button { customTags.insert(label) } label: {
                                Text(label).font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(AppTheme.raised)
                                    .foregroundStyle(AppTheme.ink)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        } header: {
            Text("Your own labels")
        } footer: {
            Text("“Kid-friendly”, “cheap”, “freezer”. Rules can be written about any label you add here.")
        }
    }

    /// What the ingredient lines actually became.
    ///
    /// The lines are free text because that is the fastest thing to paste and correct, but
    /// nothing showed what the parser made of them -- so a mis-read amount or an ingredient
    /// filed in the wrong aisle only surfaced later, in the shop.
    private var ingredientPreview: some View {
        Section {
            if resolvedIngredients.contains(where: { $0.requiresReview == true }) {
                Text("Check the highlighted ingredient amounts before saving the recipe.").foregroundStyle(AppTheme.warning)
            }
            if resolvedIngredients.isEmpty {
                Text("Nothing recognised yet.").font(.subheadline).foregroundStyle(AppTheme.muted)
            }
            ForEach(resolvedIngredients) { ingredient in
                HStack(spacing: 10) {
                    Text(ingredient.amountText())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ingredient.needsAmountReview ? AppTheme.warning : AppTheme.accent)
                        .frame(minWidth: 62, alignment: .leading)
                    Button(ingredient.name) { editingIngredient = ingredient }.fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Picker("", selection: Binding(
                        get: { aisleOverrides[ingredient.id] ?? ingredient.aisle },
                        set: { aisleOverrides[ingredient.id] = $0 }
                    )) {
                        ForEach(GroceryAisle.allCases) { Text($0.name).tag($0) }
                    }
                    .labelsHidden()
                    .accessibilityLabel(L10n.string("Aisle for %@", ingredient.name))
                }
            }
        } header: {
            Text("How that reads")
        } footer: {
            Text("Amounts and aisles are what the shopping list is built from. Change an aisle here if something is filed in the wrong place.")
        }
    }

    private var suggestedLabels: [String] {
        store.customTagsInUse.filter { !customTags.contains($0) }
    }

    private func addCustomTag() {
        let cleaned = newCustomTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        customTags.insert(cleaned)
        newCustomTag = ""
    }

    /// A meal already in the library under this name. Only interesting for a new one.
    private var duplicate: Meal? {
        guard existingMeal == nil else { return nil }
        if let id = initialDraft.updatingMealID, let meal = store.meal(id: id) { return meal }
        if case .web(let url) = originalSource,
           let meal = store.meals.first(where: { if case .web(let other) = $0.source { return RecipeURLIdentity.normalized(url) == RecipeURLIdentity.normalized(other) }; return false }) { return meal }
        return store.mealNamed(name)
    }

    private var resolvedIngredients: [Ingredient] {
        let base: [Ingredient]
        if let importedIngredients, ingredientText == importedIngredientText {
            base = importedIngredients
        } else {
            let lines = ingredientText.components(separatedBy: .newlines)
            let retained = (importedIngredients ?? []) + (replacement?.ingredients ?? [])
            base = IngredientParser.reconcile(lines: lines, originalLines: retained.map(\.editableLine), ingredients: retained)
        }
        return base.map { original in
            let ingredient = ingredientEdits[original.id] ?? original
            guard let aisle = aisleOverrides[ingredient.id], aisle != ingredient.aisle else { return ingredient }
            var corrected = ingredient
            corrected.aisle = aisle
            return corrected
        }
    }

    private func save() {
        var meal = Meal(
            // Keeps the id when customising a built-in, so the edit overrides the original
            // instead of adding a second copy of it to the library.
            id: replacement?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            subtitle: subtitle,
            emoji: emoji.isEmpty ? "🍽️" : emoji,
            prepMinutes: prepMinutes,
            tags: tags,
            customTags: customTags,
            ingredients: resolvedIngredients,
            defaultServings: servings,
            estimatedCost: replacement?.estimatedCost ?? existingMeal?.estimatedCost,
            instructions: instructionText.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty },
            source: originalSource == .builtIn ? .manual : originalSource,
            heroImageURL: heroImageURL
        )
        meal.sourceText = initialDraft.sourceText ?? existingMeal?.sourceText
        meal.servingsConfirmed = servingsConfirmed
        meal.activeMinutes = knownActiveTime ? activeMinutes : nil
        meal.parentRecipeID = replacement == nil ? (initialDraft.parentRecipeID ?? duplicate?.id) : replacement?.parentRecipeID
        do {
            meal.sourceImageNames = sourceImages.isEmpty ? (replacement?.sourceImageNames ?? existingMeal?.sourceImageNames)
                : try RecipeLibraryStorage.saveImages(sourceImages, recipeID: meal.id)
        } catch { saveError = error.localizedDescription; return }
        guard store.saveMeal(meal) else { saveError = store.persistenceError; return }
        didSave = true
        RecipeLibraryStorage.removeDraft(initialDraft.id)
        if let id = initialDraft.captureID, let capture = store.pendingCaptures.first(where: { $0.id == id }) { store.discardCapture(capture) }
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
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(selected.contains(tag) ? AppTheme.accent : AppTheme.raised)
                        .foregroundStyle(selected.contains(tag) ? AppTheme.onAccent : AppTheme.ink)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected.contains(tag) ? [.isSelected] : [])
            }
        }
    }
}
