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
    @State private var estimatedCost: Int
    @State private var ingredientText: String
    @State private var instructionText: String
    @State private var tags: Set<MealTag>

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
        _estimatedCost = State(initialValue: existingMeal?.estimatedCost ?? 0)
        let ingredients = existingMeal?.ingredients.map {
            "\($0.quantity.formatted(.number.precision(.fractionLength(0...2)))) \($0.unit) \($0.name)"
        } ?? draft.ingredientLines
        let joinedIngredients = ingredients.joined(separator: "\n")
        importedIngredientText = joinedIngredients
        _ingredientText = State(initialValue: joinedIngredients)
        _instructionText = State(initialValue: (existingMeal?.instructions ?? draft.instructions).joined(separator: "\n"))
        _tags = State(initialValue: existingMeal?.tags ?? draft.tags)
    }

    var body: some View {
        NavigationStack {
            Form {
                if needsReview {
                    Section {
                        Label("Read from a photo — check the details before saving.",
                              systemImage: "exclamationmark.circle")
                            .font(.subheadline).foregroundStyle(AppTheme.warning)
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
                    Stepper(
                        estimatedCost == 0
                            ? L10n.string("Price not set")
                            : L10n.string("About NOK %ld total", estimatedCost),
                        value: $estimatedCost,
                        in: 0...2_000,
                        step: 25
                    )
                }

                Section("Categories") {
                    TagCloud(selected: $tags)
                }

                Section("Ingredients – one per line") {
                    TextEditor(text: $ingredientText).frame(minHeight: 150)
                    Text("Example: 500 g chicken breast").font(.caption).foregroundStyle(.secondary)
                }

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

    private func save() {
        // The service classifies each ingredient's aisle, which re-parsing the text would
        // throw away. Keep its work when the user accepted the import as written.
        let lines = ingredientText.components(separatedBy: .newlines)
        let resolvedIngredients: [Ingredient]
        if let importedIngredients, ingredientText == importedIngredientText {
            resolvedIngredients = importedIngredients
        } else {
            resolvedIngredients = IngredientParser.parse(lines: lines)
        }
        let meal = Meal(
            // Keeps the id when customising a built-in, so the edit overrides the original
            // instead of adding a second copy of it to the library.
            id: existingMeal?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            subtitle: subtitle,
            emoji: emoji.isEmpty ? "🍽️" : emoji,
            prepMinutes: prepMinutes,
            tags: tags,
            ingredients: resolvedIngredients,
            defaultServings: servings,
            estimatedCost: estimatedCost == 0 ? nil : estimatedCost,
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
                        .background(selected.contains(tag) ? AppTheme.accent : Color.secondary.opacity(0.1))
                        .foregroundStyle(selected.contains(tag) ? AppTheme.onAccent : AppTheme.ink)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
