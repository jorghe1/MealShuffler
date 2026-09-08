import SwiftUI

/// The things the household always has in.
///
/// Distinct from setting an item aside as already owned, which is about this week's shop and
/// is meant to be undone. Salt, oil and rice are a standing fact, and a list that keeps
/// offering them is a list people stop reading.
struct PantryStaplesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var newStaple = ""

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Add a staple", text: $newStaple)
                        .textInputAutocapitalization(.never)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(newStaple.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } footer: {
                Text("Matched by name, so “olive oil” covers every recipe that calls for it, whatever the amount.")
            }

            Section("Always at home") {
                if store.pantryStapleNames.isEmpty {
                    Text("Nothing yet. Add items here, or long-press a line on the shopping list.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.pantryStapleNames, id: \.self) { staple in
                    Text(staple)
                }
                .onDelete { offsets in
                    let names = store.pantryStapleNames
                    store.removeStaples(Set(offsets.compactMap { names.indices.contains($0) ? names[$0] : nil }))
                }
            }
        }
        .navigationTitle("Pantry staples")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func add() {
        let cleaned = newStaple.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        store.pantryStaples.insert(AppStore.stapleKey(cleaned))
        newStaple = ""
    }
}
