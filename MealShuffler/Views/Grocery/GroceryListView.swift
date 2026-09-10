import SwiftUI

struct GroceryListView: View {
    @EnvironmentObject private var store: AppStore
    @State private var isExporting = false
    @State private var exportMessage: String?
    @State private var showingAddItem = false
    @State private var showingAisleOrder = false
    @State private var showingStaples = false
    @State private var showingPeriod = false
    @State private var editingItem: ManualGroceryItem?
    @State private var visibility = 0

    private var remainingItems: [GroceryItem] { store.groceryItems.filter { !store.checkedGroceryIDs.contains($0.id) } }
    private var visibleItems: [GroceryItem] { visibility == 1 ? store.groceryItems : visibility == 2 ? store.groceryItems.filter { store.checkedGroceryIDs.contains($0.id) } : remainingItems }

    private var shareText: String {
        PlanTextExporter.groceryList(remainingItems, aisleOrder: store.aisleOrder)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Ready to shop")
                            .font(.system(.title, design: .rounded, weight: .bold)).foregroundStyle(AppTheme.ink)
                        Text(L10n.string("%ld of %ld still to buy", remainingCount, store.groceryItems.count))
                            .font(.subheadline).foregroundStyle(AppTheme.muted)
                    }
                    Spacer()
                    Button { showingAddItem = true } label: {
                        Image(systemName: "plus").font(.title3.bold())
                            .frame(width: AppTheme.tapTarget, height: AppTheme.tapTarget)
                            .background(AppTheme.accentSoft).foregroundStyle(AppTheme.accent)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel(L10n.string("Add an item"))
                    exportMenu
                }.padding(.top, 14)

                Button { showingPeriod = true } label: {
                    Label("\(store.shoppingStart.formatted(date: .abbreviated, time: .omitted)) – \(store.shoppingEnd.formatted(date: .abbreviated, time: .omitted))", systemImage: "calendar")
                }
                Picker("Items to show", selection: $visibility) { Text("Remaining").tag(0); Text("All").tag(1); Text("Completed").tag(2) }.pickerStyle(.menu)
                Text(L10n.string("Ingredients for %ld planned dinners", store.shoppingPlan.meals.filter { $0.kind == .meal && $0.mealID != nil }.count)).font(.caption)
                if store.shoppingPlan.meals.contains(where: { item in item.kind == .meal && (item.mealID.flatMap { store.meal(id: $0) }?.ingredients.isEmpty ?? true) }) {
                    Label("Some dinners have no ingredients saved. Check their recipes before shopping.", systemImage: "exclamationmark.triangle").foregroundStyle(AppTheme.warning)
                }
                if store.groceryItems.isEmpty && !store.stockedItems.isEmpty { Label("Everything is already at home", systemImage: "house.fill") }
                else if store.groceryItems.isEmpty { emptyState }
                else if remainingItems.isEmpty { Label("Shopping complete", systemImage: "checkmark.seal.fill").foregroundStyle(AppTheme.accent) }

                ForEach(store.aisleOrder) { aisle in
                    let items = visibleItems.filter { $0.aisle == aisle }
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(aisle.name.uppercased())
                                .font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(AppTheme.accent)
                                .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)
                            ForEach(items) { item in
                                groceryRow(item)
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
        .navigationTitle("Shop")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPeriod) { ShoppingPeriodView().environmentObject(store) }
        .sheet(item: $editingItem) { item in
            AddGroceryItemView(existing: item) { name, quantity, unit, aisle in
                store.updateGroceryItem(ManualGroceryItem(id: item.id, name: name, quantity: quantity, unit: unit, aisle: aisle))
            }
        }
        .sheet(isPresented: $showingAisleOrder) {
            AisleOrderView().environmentObject(store)
        }
        .sheet(isPresented: $showingStaples) {
            NavigationStack { PantryStaplesView().environmentObject(store) }
        }
        .sheet(isPresented: $showingAddItem) {
            AddGroceryItemView { name, quantity, unit, aisle in
                store.addGroceryItem(name: name, quantity: quantity, unit: unit, aisle: aisle)
            }
            .presentationDetents([.medium, .large])
        }
        .alert("Export", isPresented: Binding(get: { exportMessage != nil }, set: { if !$0 { exportMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(exportMessage ?? "") }
    }

    /// One line on the list.
    ///
    /// "Already have it" was a long-press context menu with no visible affordance at all --
    /// a LazyVStack cannot offer swipe actions, so the feature was effectively invisible. It
    /// gets a real button; the context menu stays for the manual-item delete.
    private func groceryRow(_ item: GroceryItem) -> some View {
        let isChecked = store.checkedGroceryIDs.contains(item.id)
        return HStack(spacing: 4) {
            Button {
                Haptics.check()
                store.toggleGroceryItem(item)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isChecked ? AppTheme.accent : AppTheme.muted.opacity(0.45))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).foregroundStyle(AppTheme.ink).strikethrough(isChecked)
                        if !item.mealNames.isEmpty {
                            Text(item.mealNames.sorted().joined(separator: ", "))
                                .font(.caption2).foregroundStyle(AppTheme.muted).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(item.quantityText).font(.subheadline).foregroundStyle(AppTheme.muted)
                }
                .padding(.leading, 16).padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(item.name), \(item.quantityText)")
            .accessibilityAddTraits(isChecked ? [.isButton, .isSelected] : [.isButton])

            if let manual = store.manualItem(matching: item) {
                Menu {
                    Button("Edit item") { editingItem = manual }
                    Button("Remove", role: .destructive) { store.removeManualGroceryItems([manual.id]) }
                } label: { Image(systemName: "ellipsis.circle").iconButtonFrame() }.accessibilityLabel(L10n.string("Edit item: %@", item.name))
            }
            Button {
                Haptics.check()
                store.setStocked(item, stocked: true)
            } label: {
                Image(systemName: "house")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.muted)
                    .iconButtonFrame()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("%@, already at home", item.name))
            .accessibilityHint(L10n.string("Takes it off the list"))
            .padding(.trailing, 6)
        }
        .contextMenu {
            Button { store.setStocked(item, stocked: true) } label: {
                Label("Already have it", systemImage: "house")
            }
            // "We have this right now" against "we always have this". The second one is why
            // salt and oil kept reappearing on a list nobody needed them on.
            Button { store.setStaple(item, isStaple: true) } label: {
                Label("Always have this", systemImage: "cabinet")
            }
            if let manual = store.manualItem(matching: item) {
                Button { editingItem = manual } label: { Label("Edit item", systemImage: "pencil") }
                Button(role: .destructive) {
                    store.removeManualGroceryItems([manual.id])
                } label: { Label("Remove", systemImage: "trash") }
            }
        }
    }

    /// Items set aside as already owned, kept visible so they can be put back.
    private var stockedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.string("Already at home").uppercased())
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

    /// Bring! reads a recipe off its own page, so only dinners that came from a link can
    /// go across. Hidden entirely rather than shown empty: a menu item that never works is
    /// worse than one that is not there.
    private var bringDinners: [BringExport.Dinner] {
        BringExport.exportableDinners(plan: store.plan, meals: store.meals)
    }

    private var exportMenu: some View {
        Menu {
            ShareLink(item: shareText) { Label("Share remaining items", systemImage: "square.and.arrow.up") }
            ShareLink(item: PlanTextExporter.groceryList(store.groceryItems, aisleOrder: store.aisleOrder)) { Label("Share all items", systemImage: "list.bullet") }
            Button { showingAisleOrder = true } label: {
                Label("Reorder aisles", systemImage: "arrow.up.arrow.down")
            }
            Button { showingStaples = true } label: {
                Label("Pantry staples", systemImage: "cabinet")
            }
            Button {
                Task { await exportToReminders() }
            } label: { Label("Apple Reminders", systemImage: "checklist") }
            .disabled(isExporting)
            if !bringDinners.isEmpty {
                Menu {
                    ForEach(bringDinners) { dinner in
                        Link(dinner.meal.name, destination: dinner.link)
                    }
                } label: {
                    Label("Send a dinner to Bring!", systemImage: "cart.badge.plus")
                }
            }
        } label: {
            if isExporting {
                ProgressView().frame(width: AppTheme.tapTarget, height: AppTheme.tapTarget)
            } else {
                Image(systemName: "square.and.arrow.up").font(.title3.bold())
                    .frame(width: AppTheme.tapTarget, height: AppTheme.tapTarget)
                    .background(AppTheme.raised).foregroundStyle(AppTheme.ink)
                    .clipShape(Circle())
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
            let count = try await RemindersExportService().export(remainingItems, periodID: store.shoppingPeriodID)
            exportMessage = L10n.string("Updated %ld items in the “Meal Shuffler” list in Reminders.", count)
        } catch { exportMessage = error.localizedDescription }
    }
}

/// Adds a line the plan did not ask for.
private struct AddGroceryItemView: View {
    @Environment(\.dismiss) private var dismiss
    let add: (String, Double?, String, GroceryAisle) -> Void
    let existing: ManualGroceryItem?

    init(existing: ManualGroceryItem? = nil, add: @escaping (String, Double?, String, GroceryAisle) -> Void) {
        self.existing = existing; self.add = add
        _name = State(initialValue: existing?.name ?? "")
        _amount = State(initialValue: existing?.quantity.map { String($0) } ?? "")
        _unit = State(initialValue: existing?.unit ?? "")
        _aisle = State(initialValue: existing?.aisle ?? .pantry)
    }

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
            .navigationTitle(existing == nil ? L10n.string("Add an item") : L10n.string("Edit item"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        add(name, Double(amount.replacingOccurrences(of: ",", with: ".")), unit, aisle)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || (!amount.isEmpty && !(Double(amount.replacingOccurrences(of: ",", with: ".")).map { $0.isFinite && $0 > 0 } ?? false)))
                }
            }
        }
    }
}

private struct ShoppingPeriodView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var start = Date.now
    @State private var end = Date.now
    var body: some View {
        NavigationStack {
            Form {
                DatePicker("From", selection: $start, in: store.plan.startDate...lastDate, displayedComponents: .date)
                DatePicker("Through", selection: $end, in: start...max(start, lastDate), displayedComponents: .date)
                Text("Choose any dates across this week and next week. Each shopping period keeps its own progress.")
            }
            .navigationTitle("Shopping period")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { store.setShoppingPeriod(from: start, through: max(start, end)); dismiss() } }
            }
            .onAppear { start = min(max(store.shoppingStart, store.plan.startDate), lastDate); end = min(max(store.shoppingEnd, start), lastDate) }
            .onChange(of: start) { _, value in end = max(value, end) }
        }
    }
    private var lastDate: Date { Calendar.current.date(byAdding: .day, value: 13, to: store.plan.startDate) ?? store.plan.startDate }
}
