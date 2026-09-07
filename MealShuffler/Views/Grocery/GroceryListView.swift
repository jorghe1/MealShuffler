import SwiftUI

struct GroceryListView: View {
    @EnvironmentObject private var store: AppStore
    @State private var isExporting = false
    @State private var exportMessage: String?
    @State private var showingAddItem = false
    @State private var showingAisleOrder = false

    private var shareText: String {
        PlanTextExporter.groceryList(store.groceryItems, aisleOrder: store.aisleOrder)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Ready to shop")
                            .font(.system(.title, design: .rounded, weight: .bold)).foregroundStyle(AppTheme.ink)
                        Text(L10n.string("%ld of %ld items remaining", remainingCount, store.groceryItems.count))
                            .font(.subheadline).foregroundStyle(AppTheme.muted)
                    }
                    Spacer()
                    Button { showingAddItem = true } label: {
                        Image(systemName: "plus").font(.title3.bold()).frame(width: 48, height: 48)
                            .background(AppTheme.accentSoft).clipShape(Circle())
                    }
                    .accessibilityLabel(L10n.string("Add an item"))
                    exportMenu
                }.padding(.top, 14)

                if store.groceryItems.isEmpty { emptyState }

                ForEach(store.aisleOrder) { aisle in
                    let items = store.groceryItems.filter { $0.aisle == aisle }
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(aisle.name.uppercased())
                                .font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(AppTheme.accent)
                                .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)
                            ForEach(items) { item in
                                Button {
                                    Haptics.check()
                                    store.toggleGroceryItem(item)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: store.checkedGroceryIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                            .font(.title3).foregroundStyle(store.checkedGroceryIDs.contains(item.id) ? AppTheme.accent : AppTheme.muted.opacity(0.45))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.name).foregroundStyle(AppTheme.ink).strikethrough(store.checkedGroceryIDs.contains(item.id))
                                            if !item.mealNames.isEmpty {
                                                Text(item.mealNames.sorted().joined(separator: ", ")).font(.caption2).foregroundStyle(AppTheme.muted).lineLimit(1)
                                            }
                                        }
                                        Spacer()
                                        Text(item.quantityText).font(.subheadline).foregroundStyle(AppTheme.muted)
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 11).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("\(item.name), \(item.quantityText)")
                                .accessibilityAddTraits(
                                    store.checkedGroceryIDs.contains(item.id) ? [.isButton, .isSelected] : [.isButton]
                                )
                                // A List would allow swipe actions; this is a LazyVStack, where
                                // they render but never fire. Long press is the honest affordance.
                                .contextMenu {
                                    Button { store.setStocked(item, stocked: true) } label: {
                                        Label("Already have it", systemImage: "house")
                                    }
                                    if let manual = store.manualItem(matching: item) {
                                        Button(role: .destructive) {
                                            store.removeManualGroceryItems([manual.id])
                                        } label: { Label("Remove", systemImage: "trash") }
                                    }
                                }
                                if item.id != items.last?.id { Divider().padding(.leading, 52) }
                            }
                        }.mealCard()
                    }
                }
                if !store.stockedItems.isEmpty { stockedSection }

                Color.clear.frame(height: 20)
            }.padding(.horizontal, 16)
        }
        .appBackground()
        .navigationTitle("Grocery list")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAisleOrder) {
            AisleOrderView().environmentObject(store)
        }
        .sheet(isPresented: $showingAddItem) {
            AddGroceryItemView { name, quantity, unit, aisle in
                store.addGroceryItem(name: name, quantity: quantity, unit: unit, aisle: aisle)
            }
            .presentationDetents([.medium])
        }
        .alert("Export", isPresented: Binding(get: { exportMessage != nil }, set: { if !$0 { exportMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(exportMessage ?? "") }
    }

    /// Items set aside as already owned, kept visible so they can be put back.
    private var stockedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Already at home".uppercased())
                .font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(AppTheme.muted)
                .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)
            ForEach(store.stockedItems) { item in
                Button { store.setStocked(item, stocked: false) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "house.fill").font(.footnote).foregroundStyle(AppTheme.accent)
                        Text(item.name).foregroundStyle(AppTheme.muted)
                        Spacer()
                        Text("Put back").font(.caption.weight(.semibold)).foregroundStyle(AppTheme.accent)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 11).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(L10n.string("%@, already at home", item.name))
                .accessibilityHint(L10n.string("Puts it back on the list"))
            }
        }
        .mealCard()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "cart").font(.system(.largeTitle)).foregroundStyle(AppTheme.accent)
            Text("Nothing to buy yet").font(.headline).foregroundStyle(AppTheme.ink)
            Text("Plan some dinners and the ingredients show up here, sorted by aisle.")
                .font(.subheadline).foregroundStyle(AppTheme.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(30)
        .mealCard()
    }

    private var exportMenu: some View {
        Menu {
            ShareLink(item: shareText) { Label("Share as text", systemImage: "square.and.arrow.up") }
            Button { showingAisleOrder = true } label: {
                Label("Reorder aisles", systemImage: "arrow.up.arrow.down")
            }
            Button {
                Task { await exportToReminders() }
            } label: { Label("Apple Reminders", systemImage: "checklist") }
            .disabled(isExporting || store.groceryItems.isEmpty)
        } label: {
            if isExporting { ProgressView().frame(width: 48, height: 48) }
            else {
                Image(systemName: "square.and.arrow.up").font(.title3.bold()).frame(width: 48, height: 48)
                    .background(AppTheme.raised).clipShape(Circle())
            }
        }
        .accessibilityLabel(L10n.string("Export grocery list"))
    }

    private var remainingCount: Int {
        store.groceryItems.filter { !store.checkedGroceryIDs.contains($0.id) }.count
    }

    private func exportToReminders() async {
        isExporting = true
        defer { isExporting = false }
        do {
            let count = try await RemindersExportService().export(store.groceryItems)
            exportMessage = L10n.string("Added %ld items to the “Meal Shuffler” list in Reminders.", count)
        } catch { exportMessage = error.localizedDescription }
    }
}

/// Adds a line the plan did not ask for.
private struct AddGroceryItemView: View {
    @Environment(\.dismiss) private var dismiss
    let add: (String, Double?, String, GroceryAisle) -> Void

    @State private var name = ""
    @State private var amount = ""
    @State private var unit = ""
    @State private var aisle: GroceryAisle = .pantry

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("What do you need?", text: $name)
                    HStack {
                        TextField("Amount", text: $amount)
                            .keyboardType(.decimalPad)
                            .frame(maxWidth: 110)
                        TextField("Unit", text: $unit)
                            .textInputAutocapitalization(.never)
                    }
                    Text("Amount and unit are optional. Leave them out for things you just need some of.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Aisle") {
                    Picker("Aisle", selection: $aisle) {
                        ForEach(GroceryAisle.allCases) { Text($0.name).tag($0) }
                    }
                }
            }
            .navigationTitle("Add an item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        add(name, Double(amount.replacingOccurrences(of: ",", with: ".")), unit, aisle)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
