import SwiftUI

/// What a friend sent, before any of it touches this household's rules or library.
///
/// Everything starts selected, nothing is added until asked, and the outcome says exactly what
/// happened -- including the rules that were left out because this household already has
/// them, or has one that says the opposite. A friend's list never overrides your own.
struct IncomingShareView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let share: IncomingShare
    @State private var excluded: Set<Int> = []
    @State private var result: String?
    @State private var saveError: String?
    @State private var rules: [PlanningRule] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                }
                .listRowBackground(Color.clear)

                switch share {
                case .rules(let shared): rulesSection(shared).disabled(result != nil)
                case .recipes(let shared): recipesSection(shared)
                }

                if let result {
                    Section {
                        Label(result, systemImage: "checkmark.seal.fill")
                            .foregroundStyle(AppTheme.accent)
                    }
                }
                if let saveError {
                    Section {
                        Label(saveError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(AppTheme.warning)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .appBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(result == nil ? L10n.string("Not now") : L10n.string("Done")) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { actions }
            .onAppear {
                if case .rules(let shared) = share, rules.isEmpty {
                    rules = HouseRulesShare.sanitized(shared.rules, meals: store.meals)
                }
            }
        }
    }

    private var sender: String {
        switch share {
        case .rules(let shared): shared.from
        case .recipes(let shared): shared.from
        }
    }

    private var title: String {
        switch share {
        case .rules: L10n.string("House rules")
        case .recipes: L10n.string("Shared recipes")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(sender.isEmpty ? L10n.string("A friend sent you something") : L10n.string("From %@", sender))
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(AppTheme.ink)
            Text(explanation)
                .font(.subheadline).foregroundStyle(AppTheme.muted)
        }
        .padding(.vertical, 6)
    }

    private var explanation: String {
        switch share {
        case .rules:
            L10n.string("Pick the rules you want. Any that repeat or contradict your own are skipped, so nothing you already have changes.")
        case .recipes:
            L10n.string("Pick the recipes you want. They are added as your own copies, and dishes you already have are skipped.")
        }
    }

    // MARK: - Rules

    @ViewBuilder private func rulesSection(_ shared: SharedRules) -> some View {
        Section {
            ForEach(Array(rules.enumerated()), id: \.offset) { index, rule in
                Toggle(isOn: included(index)) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(rule.summary(meals: store.meals, context: store.matchContext))
                            .font(.subheadline.weight(.semibold))
                        if rule.strength == .preferred {
                            Text(rule.strength.name).font(.caption).foregroundStyle(AppTheme.muted)
                        }
                    }
                }
            }
        } footer: {
            let dropped = shared.rules.count - rules.count
            if dropped > 0 {
                Text(L10n.string("%ld rules were about people or recipes you do not have, so they were left out.", dropped))
            }
        }
    }

    // MARK: - Recipes

    @ViewBuilder private func recipesSection(_ shared: SharedRecipes) -> some View {
        Section {
            ForEach(Array(shared.recipes.enumerated()), id: \.offset) { index, recipe in
                let known = store.mealNamed(recipe.name) != nil
                Toggle(isOn: included(index)) {
                    HStack(spacing: 12) {
                        MealThumbnail(emoji: recipe.emoji, imageURL: recipe.image, size: AppTheme.emojiTileCompact)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(recipe.name).font(.subheadline.weight(.semibold))
                            Text(known ? L10n.string("Already in your meals") : recipeDetail(recipe))
                                .font(.caption).foregroundStyle(AppTheme.muted)
                        }
                    }
                }
                .disabled(known || result != nil)
            }
        }
    }

    private func recipeDetail(_ recipe: SharedRecipe) -> String {
        let time = recipe.prepMinutes > 0 ? L10n.string("%ld min", recipe.prepMinutes) : L10n.string("Time not specified")
        return time + " · " + L10n.string("%ld ingredients", recipe.ingredients.count)
    }

    // MARK: - Acting

    private func included(_ index: Int) -> Binding<Bool> {
        Binding(
            get: { !excluded.contains(index) },
            set: { isOn in
                if isOn { excluded.remove(index) } else { excluded.insert(index) }
            }
        )
    }

    private var selectionCount: Int {
        switch share {
        case .rules: rules.indices.filter { !excluded.contains($0) }.count
        case .recipes(let shared):
            shared.recipes.indices.filter { !excluded.contains($0) && store.mealNamed(shared.recipes[$0].name) == nil }.count
        }
    }

    @ViewBuilder private var actions: some View {
        VStack(spacing: 10) {
            if result == nil {
                Button(action: add) {
                    Text(addTitle)
                }
                .buttonStyle(.primary)
                .disabled(selectionCount == 0)
            } else if case .rules = share {
                // The reason a household accepts someone's rules is to see what week they make.
                Button {
                    Haptics.shuffle()
                    dismiss()
                    Task { await store.generateInBackground() }
                } label: {
                    Label("Shuffle a week with them", systemImage: "shuffle")
                }
                .buttonStyle(.primary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.bar)
    }

    private var addTitle: String {
        switch share {
        case .rules: L10n.string("Add %ld rules", selectionCount)
        case .recipes: L10n.string("Add %ld recipes", selectionCount)
        }
    }

    private func add() {
        saveError = nil
        switch share {
        case .rules:
            let chosen = rules.indices.filter { !excluded.contains($0) }.map { rules[$0] }
            let outcome = store.importSharedRules(chosen)
            var parts = [L10n.string("Added %ld rules.", outcome.added)]
            if outcome.duplicates > 0 { parts.append(L10n.string("%ld you already had.", outcome.duplicates)) }
            if outcome.conflicts > 0 { parts.append(L10n.string("%ld would contradict your own rules and were left out.", outcome.conflicts)) }
            result = parts.joined(separator: " ")
        case .recipes(let shared):
            let chosen = shared.recipes.indices.filter { !excluded.contains($0) }.map { shared.recipes[$0] }
            if let added = store.importSharedRecipes(chosen) {
                result = L10n.string("Added %ld recipes to your meals.", added)
            } else {
                saveError = L10n.string("The recipes could not be saved. Try again.")
                return
            }
        }
        Haptics.success()
    }
}
