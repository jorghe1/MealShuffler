import SwiftUI

/// Puts the shopping list in the order of your own shop.
///
/// The list is grouped by aisle so it can be walked rather than hunted through, which only
/// works if the grouping matches the walk. A fixed order is right in exactly one supermarket.
struct AisleOrderView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.aisleOrder) { aisle in
                        HStack(spacing: 12) {
                            Image(systemName: symbol(for: aisle))
                                .foregroundStyle(AppTheme.accent).frame(width: 26)
                            Text(aisle.name)
                        }
                    }
                    .onMove(perform: store.moveAisles)
                } header: {
                    Text("Order")
                } footer: {
                    Text("Drag the sections into the order you walk your shop. The shared list follows the same order.")
                }

                if store.aisleOrder != GroceryAisle.allCases {
                    Section {
                        Button("Reset to default") { store.resetAisleOrder() }
                    }
                }
            }
            // Always editable: a list whose only purpose is reordering should not hide the
            // handles behind an Edit button.
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder aisles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func symbol(for aisle: GroceryAisle) -> String {
        switch aisle {
        case .produce: "carrot"
        case .bread: "birthday.cake"
        case .meatAndFish: "fish"
        case .dairy: "drop"
        case .pantry: "shippingbox"
        case .frozen: "snowflake"
        }
    }
}
