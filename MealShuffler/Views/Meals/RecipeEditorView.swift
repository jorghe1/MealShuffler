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
        originalSource = existingMeal?.source ?? draft.source
        importedIngredients = existingMeal == nil ? draft.parsedIngredients : nil
        heroImageURL = existingMeal?.heroImageURL ?? draft.heroImageURL
        needsReview = existingMeal == nil && draft.needsReview
        _name = State(initialValue: existingMeal?.name ?? draft.name)
        _subtitle = State(initialValue: existingMeal?.subtitle ?? draft.subtitle)
        _emoji = State(initialValue: existingMeal?.emoji ?? draft.emoji)
        _prepMinutes = State(initialValue: existingMeal?.prepMinutes ?? draft.prepMinutes)
        _servings = State(initialValue: existingMeal?.defaultServings ?? draft.servings)
        let ingredients = existingMeal?.ingredients.map {
            "\($0.quantity.formatted(.number.precision(.fractionLength(0...2)))) \($0.unit) \($0.name)"
        } ?? draft.ingredientLines
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
                        Text("Saving adds a second one. Cancel and edit the original instead if that is what you meant.")
                            .font(.caption).foregroundStyle(AppTheme.muted)
                    }
                }
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
                    Stepper(L10n.string("About %ld minutes", prepMinutes), value: $prepMinutes, in: 5...240, step: 5)
                    Stepper(L10n.string("%ld servings", servings), value: $servings, in: 1...20)
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
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.fontWeight(.semibold).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
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
            if resolvedIngredients.isEmpty {
                Text("Nothing recognised yet.").font(.subheadline).foregroundStyle(AppTheme.muted)
            }
            ForEach(resolvedIngredients) { ingredient in
                HStack(spacing: 10) {
                    Text(IngredientUnits.display(quantity: ingredient.quantity, unit: ingredient.unit))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(minWidth: 62, alignment: .leading)
                    Text(ingredient.name).lineLimit(1)
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
        return store.mealNamed(name)
    }

    private var resolvedIngredients: [Ingredient] {
        let base: [Ingredient]
        if let importedIngredients, ingredientText == importedIngredientText {
            base = importedIngredients
        } else {
            base = IngredientParser.parse(lines: ingredientText.components(separatedBy: .newlines))
        }
        return base.map { ingredient in
            guard let aisle = aisleOverrides[ingredient.id], aisle != ingredient.aisle else { return ingredient }
            return Ingredient(name: ingredient.name, quantity: ingredient.quantity, unit: ingredient.unit, aisle: aisle)
        }
    }

    private func save() {
        let meal = Meal(
            // Keeps the id when customising a built-in, so the edit overrides the original
            // instead of adding a second copy of it to the library.
            id: existingMeal?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            subtitle: subtitle,
            emoji: emoji.isEmpty ? "🍽️" : emoji,
            prepMinutes: prepMinutes,
            tags: tags,
            customTags: customTags,
            ingredients: resolvedIngredients,
            defaultServings: servings,
            estimatedCost: existingMeal?.estimatedCost,
            instructions: instructionText.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty },
            source: isEditingBuiltIn ? .manual : originalSource,
            heroImageURL: heroImageURL
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
                        .background(selected.contains(tag) ? AppTheme.accent : AppTheme.raised)
                        .foregroundStyle(selected.contains(tag) ? AppTheme.onAccent : AppTheme.ink)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
