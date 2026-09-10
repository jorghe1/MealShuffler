import SwiftUI

struct FreezerView: View {
    @EnvironmentObject private var store: AppStore
    @State private var recipeID: UUID?
    @State private var portions = 4.0
    @State private var label = ""
    var body: some View {
        Form {
            Section("Add a batch") {
                Picker("Recipe", selection: $recipeID) {
                    Text("Choose a meal").tag(nil as UUID?)
                    ForEach(store.meals) { Text($0.name).tag($0.id as UUID?) }
                }
                TextField("Container label", text: $label)
                Stepper(L10n.portions(portions), value: $portions, in: 0.5...40, step: 0.5)
                Button("Add to freezer") {
                    if let id = recipeID, let recipe = store.meal(id: id) {
                        store.addFreezerBatch(recipe, portions: portions, label: label)
                        label = ""; recipeID = nil
                    }
                }.disabled(recipeID == nil)
            }
            Section("In the freezer") {
                if store.householdTools.freezer.isEmpty { Text("No batches saved yet.") }
                ForEach(store.householdTools.freezer) { batch in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(batch.recipe.name).font(.headline)
                        if !batch.label.isEmpty { Text(batch.label) }
                        Text(batch.frozenOn, format: .dateTime.day().month().year()).font(.caption)
                        Text(L10n.portions(batch.portions))
                        Menu("Use portions") {
                            ForEach(Array(stride(from: 0.5, through: batch.portions, by: 0.5)), id: \.self) { amount in
                                Button(L10n.portions(amount)) { store.consumeFreezerBatch(batch.id, portions: amount) }
                            }
                        }
                    }
                }
            }
        }.navigationTitle("Freezer")
    }
}

struct RecipeCollectionsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var name = ""
    @State private var selectedMeal: Meal?
    var body: some View {
        List {
            Section("New collection") {
                TextField("Name", text: $name)
                Button("Add collection") {
                    let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !title.isEmpty, store.householdTools.collections[title] == nil { store.householdTools.collections[title] = [] }
                    name = ""
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ForEach(store.householdTools.collections.keys.sorted(), id: \.self) { title in
                NavigationLink(title) {
                    List {
                        ForEach(store.meals) { meal in
                            HStack {
                                Toggle(meal.name, isOn: Binding(
                                    get: { store.householdTools.collections[title]?.contains(meal.id) == true },
                                    set: { included in
                                        if included { store.householdTools.collections[title, default: []].insert(meal.id) }
                                        else { store.householdTools.collections[title]?.remove(meal.id) }
                                    }))
                                Button { selectedMeal = meal } label: { Image(systemName: "info.circle").iconButtonFrame() }
                                    .accessibilityLabel(L10n.string("View recipe: %@", meal.name))
                            }
                        }
                    }.navigationTitle(title)
                }
            }.onDelete { offsets in
                let titles = store.householdTools.collections.keys.sorted()
                for offset in offsets { store.householdTools.collections.removeValue(forKey: titles[offset]) }
            }
        }.navigationTitle("Collections")
            .sheet(item: $selectedMeal) { MealDetailView(meal: $0) }
    }
}
