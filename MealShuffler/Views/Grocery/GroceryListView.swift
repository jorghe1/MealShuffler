import SwiftUI

struct GroceryListView: View {
    @EnvironmentObject private var store: AppStore
    @State private var isExporting = false
    @State private var exportMessage: String?

    private var shareText: String { PlanTextExporter.groceryList(store.groceryItems) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Ready to shop")
                            .font(.system(size: 27, weight: .bold, design: .rounded)).foregroundStyle(AppTheme.ink)
                        Text(L10n.string("%ld of %ld items remaining", remainingCount, store.groceryItems.count))
                            .font(.subheadline).foregroundStyle(AppTheme.muted)
                    }
                    Spacer()
                    exportMenu
                }.padding(.top, 14)

                ForEach(GroceryAisle.allCases) { aisle in
                    let items = store.groceryItems.filter { $0.aisle == aisle }
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(aisle.name.uppercased())
                                .font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(AppTheme.accent)
                                .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)
                            ForEach(items) { item in
                                Button { store.toggleGroceryItem(item) } label: {
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
                                }.buttonStyle(.plain)
                                if item.id != items.last?.id { Divider().padding(.leading, 52) }
                            }
                        }.mealCard()
                    }
                }
                Color.clear.frame(height: 20)
            }.padding(.horizontal, 16)
        }
        .appBackground()
        .navigationTitle("Grocery list")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Export", isPresented: Binding(get: { exportMessage != nil }, set: { if !$0 { exportMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(exportMessage ?? "") }
    }

    private var exportMenu: some View {
        Menu {
            ShareLink(item: shareText) { Label("Share as text", systemImage: "square.and.arrow.up") }
            Button {
                Task { await exportToReminders() }
            } label: { Label("Apple Reminders", systemImage: "checklist") }
            .disabled(isExporting || store.groceryItems.isEmpty)
        } label: {
            if isExporting { ProgressView().frame(width: 48, height: 48) }
            else {
                Image(systemName: "square.and.arrow.up").font(.title3.bold()).frame(width: 48, height: 48)
                    .background(.white).clipShape(Circle())
            }
        }
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
