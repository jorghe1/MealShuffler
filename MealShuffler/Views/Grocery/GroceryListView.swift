import SwiftUI

/// The shopping list, built to be used one-handed in a shop.
///
/// It opened with a slogan ("Ready to shop"), two identical circle buttons, a date range in
/// blue, a visibility picker and two captions in four different styles before the first item.
/// Now the list starts at the top: progress, a field to add something, the aisles. Ticked
/// items and things already at home fold away at the bottom, so the list gets shorter as you
/// go, and everything that is about the list rather than on it sits behind one menu.
struct GroceryListView: View {
    @EnvironmentObject private var store: AppStore
    @State private var isExporting = false
    @State private var exportMessage: String?
    @State private var showingAddItem = false
    @State private var showingAisleOrder = false
    @State private var showingStaples = false
    @State private var showingPeriod = false
    @State private var editingItem: ManualGroceryItem?
    @State private var quickItem = ""
    @State private var showingBought = false
    @State private var showingStocked = false
    @FocusState private var quickFocused: Bool

    @Environment(\.openURL) private var openURL
    @State private var pendingBringList: URL?

    private var allItems: [GroceryItem] { store.groceryItems }
    private var remainingItems: [GroceryItem] { allItems.filter { !store.checkedGroceryIDs.contains($0.id) } }

    private var shareText: String {
        PlanTextExporter.groceryList(remainingItems, aisleOrder: store.aisleOrder)
    }

    private var plannedDinnerCount: Int {
        store.shoppingPlan.meals.filter { $0.kind == .meal && $0.mealID != nil }.count
    }

    var body: some View {
        let items = allItems
        let remaining = items.filter { !store.checkedGroceryIDs.contains($0.id) }
        List {
            Section {
                progress(total: items.count, remaining: remaining.count)
                HStack(spacing: AppTheme.Space.s) {
                    Image(systemName: "plus.circle.fill").foregroundStyle(AppTheme.accent).font(.title3)
                    TextField("Add an item…", text: $quickItem)
                        .submitLabel(.done)
                        .focused($quickFocused)
                        .onSubmit(addQuickItem)
                    if !quickItem.isEmpty {
                        Button("Details") { showingAddItem = true }
                            .font(.footnote.weight(.semibold))
                            .buttonStyle(.borderless)
                    }
                }
                .frame(minHeight: AppTheme.tapTarget)
            } footer: {
                if hasDinnersWithoutIngredients {
                    Label("Some dinners have no ingredients saved. Check their recipes before shopping.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(AppTheme.warning)
                }
            }

            if items.isEmpty {
                Section {
                    emptyState
                }
            } else if remaining.isEmpty {
                Section {
                    Label("Shopping complete", systemImage: "checkmark.seal.fill")
                        .font(.headline).foregroundStyle(AppTheme.accent)
                }
            }

            ForEach(store.aisleOrder) { aisle in
                let aisleItems = remaining.filter { $0.aisle == aisle }
                if !aisleItems.isEmpty {
                    Section(aisle.name) {
                        ForEach(aisleItems) { item in groceryRow(item) }
                    }
                }
            }

            let bought = items.filter { store.checkedGroceryIDs.contains($0.id) }
            if !bought.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: $showingBought) {
                        ForEach(bought) { item in groceryRow(item) }
                    } label: {
                        Text(L10n.string("Bought (%ld)", bought.count)).foregroundStyle(AppTheme.muted)
                    }
                }
            }

            if !store.stockedItems.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: $showingStocked) {
                        ForEach(store.stockedItems) { item in
                            Button { store.setStocked(item, stocked: false) } label: {
                                HStack {
                                    Text(item.name).foregroundStyle(AppTheme.muted)
                                    Spacer()
                                    Text("Put back").font(.caption.weight(.semibold)).foregroundStyle(AppTheme.accent)
                                }
                            }
                            .accessibilityLabel(L10n.string("%@, already at home", item.name))
                            .accessibilityHint(L10n.string("Puts it back on the list"))
                        }
                    } label: {
                        Text(L10n.string("Already at home (%ld)", store.stockedItems.count)).foregroundStyle(AppTheme.muted)
                    }
                } footer: {
                    Text("Swipe an item to set it aside as already at home. Things you always have go in pantry staples, in the menu above.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle("Shopping list")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { listMenu }
        }
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
            AddGroceryItemView(prefilledName: quickItem) { name, quantity, unit, aisle in
                store.addGroceryItem(name: name, quantity: quantity, unit: unit, aisle: aisle)
                quickItem = ""
            }
            .presentationDetents([.medium, .large])
        }
        .alert("Export", isPresented: Binding(get: { exportMessage != nil }, set: { if !$0 { exportMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(exportMessage ?? "") }
        // Said once, plainly, before anything leaves the phone: this is the one export that
        // passes the list through a server.
        .confirmationDialog("Send the list to Bring!?", isPresented: Binding(
            get: { pendingBringList != nil }, set: { if !$0 { pendingBringList = nil } }
        ), titleVisibility: .visible) {
            Button("Send") {
                if let link = pendingBringList { openURL(link) }
                pendingBringList = nil
            }
            Button("Cancel", role: .cancel) { pendingBringList = nil }
        } message: {
            Text("Bring! reads the list from our recipe service, which passes it on without keeping it.")
        }
    }

    // MARK: - Header

    /// The one number that matters in the shop, and which dinners it is for.
    private func progress(total: Int, remaining: Int) -> some View {
        let done = total - remaining
        return VStack(alignment: .leading, spacing: AppTheme.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(total == 0 ? L10n.string("Nothing to buy yet") : L10n.string("%ld of %ld bought", done, total))
                    .font(.headline).foregroundStyle(AppTheme.ink)
                Spacer()
                Button { showingPeriod = true } label: {
                    Text(periodLabel).font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .accessibilityHint(L10n.string("Changes which days the list covers"))
            }
            ProgressView(value: Double(done), total: Double(max(total, 1)))
                .tint(AppTheme.accent)
            Text(plannedDinnerCount == 1
                 ? L10n.string("For 1 planned dinner")
                 : L10n.string("For %ld planned dinners", plannedDinnerCount))
                .font(.caption).foregroundStyle(AppTheme.muted)
        }
        .padding(.vertical, AppTheme.Space.xs)
    }

    private var periodLabel: String {
        let start = store.shoppingStart.formatted(.dateTime.day().month(.abbreviated))
        let end = store.shoppingEnd.formatted(.dateTime.day().month(.abbreviated))
        return "\(start) – \(end)"
    }

    private var hasDinnersWithoutIngredients: Bool {
        store.shoppingPlan.meals.contains { item in
            item.kind == .meal && (item.mealID.flatMap { store.meal(id: $0) }?.ingredients.isEmpty ?? true)
        }
    }

    private func addQuickItem() {
        let name = quickItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        store.addGroceryItem(name: name, quantity: nil, unit: "", aisle: IngredientParser.inferAisle(from: name))
        Haptics.check()
        quickItem = ""
        quickFocused = true
    }

    // MARK: - An item

    /// Tap to tick; swipe to set it aside as already at home. The meals an item is for are a
    /// long-press away, not under every line in the shop.
    private func groceryRow(_ item: GroceryItem) -> some View {
        let isChecked = store.checkedGroceryIDs.contains(item.id)
        return Button {
            Haptics.check()
            withAnimation(.snappy) { store.toggleGroceryItem(item) }
        } label: {
            HStack(spacing: AppTheme.Space.m) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isChecked ? AppTheme.accent : AppTheme.muted.opacity(0.5))
                Text(item.name)
                    .foregroundStyle(isChecked ? AppTheme.muted : AppTheme.ink)
                    .strikethrough(isChecked)
                Spacer(minLength: AppTheme.Space.s)
                Text(item.quantityText).font(.subheadline).foregroundStyle(AppTheme.muted)
            }
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name), \(item.quantityText)")
        .accessibilityAddTraits(isChecked ? [.isButton, .isSelected] : [.isButton])
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                Haptics.check()
                store.setStocked(item, stocked: true)
            } label: {
                Label("Already have it", systemImage: "house")
            }
            .tint(AppTheme.accent)
            if let manual = store.manualItem(matching: item) {
                Button(role: .destructive) { store.removeManualGroceryItems([manual.id]) } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
        .contextMenu {
            if !item.mealNames.isEmpty {
                Text(L10n.string("For %@", item.mealNames.sorted().joined(separator: ", ")))
            }
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

    private var emptyState: some View {
        VStack(spacing: AppTheme.Space.s) {
            Image(systemName: "cart").font(.largeTitle).foregroundStyle(AppTheme.accent)
            Text(store.stockedItems.isEmpty ? L10n.string("Nothing to buy yet") : L10n.string("Everything is already at home"))
                .font(.headline).foregroundStyle(AppTheme.ink)
            Text("Plan some dinners and the ingredients show up here, sorted by aisle.")
                .font(.subheadline).foregroundStyle(AppTheme.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.Space.xl)
    }

    // MARK: - The list's own menu

    /// Bring! reads a recipe off its own page, so only dinners that came from a link can
    /// go across. Hidden entirely rather than shown empty: a menu item that never works is
    /// worse than one that is not there.
    private var bringDinners: [BringExport.Dinner] {
        BringExport.exportableDinners(plan: store.plan, meals: store.meals)
    }

    private var listMenu: some View {
        Menu {
            Section {
                if let link = BringExport.listLink(items: remainingItems, title: WeekAnchor.label(forWeekStarting: store.shoppingStart)) {
                    Button { pendingBringList = link } label: {
                        Label("Send the list to Bring!", systemImage: "cart.fill.badge.plus")
                    }
                } else if !remainingItems.isEmpty, RemoteRecipeExtractor.Configuration.fromBundle() != nil {
                    Button {
                        exportMessage = L10n.string("This list is too large for Bring! Use Share remaining items instead.")
                    } label: { Label("Send the list to Bring!", systemImage: "cart.fill.badge.plus") }
                }
                if !bringDinners.isEmpty {
                    Menu {
                        ForEach(bringDinners) { dinner in
                            Link(dinner.meal.name, destination: dinner.link)
                        }
                    } label: {
                        Label("Send a dinner to Bring!", systemImage: "cart.badge.plus")
                    }
                }
                Button {
                    Task { await exportToReminders() }
                } label: { Label("Apple Reminders", systemImage: "checklist") }
                .disabled(isExporting)
                ShareLink(item: shareText) { Label("Share remaining items", systemImage: "square.and.arrow.up") }
                ShareLink(item: PlanTextExporter.groceryList(allItems, aisleOrder: store.aisleOrder)) {
                    Label("Share all items", systemImage: "list.bullet")
                }
            }
            Section {
                Button { showingPeriod = true } label: { Label("Shopping period", systemImage: "calendar") }
                Button { showingStaples = true } label: { Label("Pantry staples", systemImage: "cabinet") }
                Button { showingAisleOrder = true } label: { Label("Shop order", systemImage: "arrow.up.arrow.down") }
            }
        } label: {
            if isExporting {
                ProgressView()
            } else {
                Image(systemName: "ellipsis.circle")
            }
        }
        .accessibilityLabel(L10n.string("Shopping list options"))
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

    init(existing: ManualGroceryItem? = nil, prefilledName: String = "", add: @escaping (String, Double?, String, GroceryAisle) -> Void) {
        self.existing = existing; self.add = add
        let name = existing?.name ?? prefilledName
        _name = State(initialValue: name)
        _amount = State(initialValue: existing?.quantity.map { String($0) } ?? "")
        _unit = State(initialValue: existing?.unit ?? "")
        _aisle = State(initialValue: existing?.aisle ?? (name.isEmpty ? .pantry : IngredientParser.inferAisle(from: name)))
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
