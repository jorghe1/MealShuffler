import SwiftUI

struct MealHistoryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingClear = false
    @State private var selectedMeal: Meal?

    private var events: [MealFeedbackEvent] {
        store.feedbackEvents.sorted { $0.timestamp > $1.timestamp }
    }

    /// Every meal in the library, longest-unused first.
    ///
    /// This is the app's actual promise made legible. A flat event log says what happened;
    /// it never answered "what have we not had in ages", which is the question a household
    /// planning for variety is really asking.
    private var rotation: [RotationEntry] {
        let cooked = store.lastCookedByMeal
        let snoozed = store.activeSnoozedMealIDs
        return store.meals
            .map { meal in
                RotationEntry(
                    meal: meal,
                    lastCooked: cooked[meal.id],
                    isSnoozed: snoozed.contains(meal.id)
                )
            }
            .sorted { lhs, rhs in
                switch (lhs.lastCooked, rhs.lastCooked) {
                case (nil, nil): return lhs.meal.name < rhs.meal.name
                case (nil, _): return true
                case (_, nil): return false
                case (let left?, let right?): return left < right
                }
            }
    }

    private struct RotationEntry: Identifiable {
        let meal: Meal
        let lastCooked: Date?
        let isSnoozed: Bool

        var id: UUID { meal.id }

        var daysSince: Int? {
            guard let lastCooked else { return nil }
            return Calendar.current.dateComponents([.day], from: lastCooked, to: .now).day
        }

        /// How overdue this looks, 0...1. Capped at eight weeks: past that, everything is
        /// simply "a long time ago" and a longer bar says nothing more.
        var overdue: Double {
            guard let daysSince else { return 1 }
            return min(Double(daysSince) / 56.0, 1)
        }

        var label: String {
            if isSnoozed { return L10n.string("Paused") }
            guard let daysSince else { return L10n.string("Never cooked") }
            if daysSince <= 0 { return L10n.string("Today") }
            if daysSince == 1 { return L10n.string("Yesterday") }
            return L10n.string("%ld days ago", daysSince)
        }
    }

    private var distinctCooked: Int {
        Set(store.feedbackEvents.filter { $0.kind == .cooked }.map(\.mealID)).count
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    stat(title: L10n.string("Cooked"),
                         value: events.filter { $0.kind == .cooked }.count,
                         symbol: "checkmark.seal.fill")
                    stat(title: L10n.string("Different meals"),
                         value: distinctCooked,
                         symbol: "square.grid.2x2")
                    stat(title: L10n.string("Paused"),
                         value: events.filter { $0.kind == .snoozed }.count,
                         symbol: "calendar.badge.minus")
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }

            Section {
                ForEach(rotation) { entry in
                    Button {
                        selectedMeal = entry.meal
                    } label: {
                        rotationRow(entry)
                    }
                    .buttonStyle(.plain)
                    HStack {
                        Button { store.toggleFavorite(entry.meal) } label: { Image(systemName: store.favoriteMealIDs.contains(entry.meal.id) ? "heart.fill" : "heart").iconButtonFrame() }.accessibilityLabel("Family favorite")
                        Menu("Plan for a day") { ForEach(Weekday.ordered()) { day in Button(day.name) { store.setMeal(entry.meal, on: day) } } }
                    }
                    .contextMenu {
                        Menu {
                            ForEach(Weekday.ordered()) { day in
                                Button(day.name) { store.setMeal(entry.meal, on: day) }
                            }
                        } label: {
                            Label("Plan for a day", systemImage: "calendar.badge.plus")
                        }
                    }
                }
            } header: {
                Text("Due a turn")
            } footer: {
                Text("Longest since you cooked it, first. Long-press to put one on a day.")
            }

            Section("Archived weeks") {
                ForEach(store.archivedWeeks) { archive in
                    NavigationLink(WeekAnchor.label(forWeekStarting: archive.startDate)) {
                        List {
                            ForEach(archive.plan.meals) { item in
                                if let meal = item.mealID.flatMap({ id in item.freezerBatch?.recipe ?? archive.recipeSnapshots?.first(where: { $0.id == id }) ?? store.meal(id: id) }) {
                                    Button { selectedMeal = meal } label: {
                                        VStack(alignment: .leading) { Text(archive.plan.date(for: item.day), format: .dateTime.weekday(.wide).day().month()); Text(meal.name) }
                                    }
                                } else { Text(item.kind == .away ? L10n.string("No dinner at home") : item.kind == .takeaway ? L10n.string("Takeaway") : L10n.string("Not planned")) }
                            }
                        }.navigationTitle(WeekAnchor.label(forWeekStarting: archive.startDate))
                    }
                }
            }
            Section("Activity") {
                if events.isEmpty { Text("No activity yet.").foregroundStyle(.secondary) }
                ForEach(events) { event in
                    if let meal = event.recipeSnapshot ?? store.meal(id: event.mealID) {
                        HStack(spacing: 12) {
                            MealThumbnail(meal: meal, size: AppTheme.emojiTileCompact)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(meal.name).font(.headline)
                                Text(eventLabel(event)).font(.caption).foregroundStyle(AppTheme.muted)
                            }
                            Spacer()
                            Text(event.plannedDate ?? event.timestamp, format: .dateTime.day().month(.abbreviated))
                                .font(.caption).foregroundStyle(AppTheme.muted)
                        }
                    }
                }
            }

            Section {
                Text("History affects shuffle locally: meals you cook become slightly more relevant, while recently cooked meals temporarily receive a repetition penalty.")
                    .font(.caption).foregroundStyle(AppTheme.muted)
            }

            if !events.isEmpty {
                Section { Button("Clear history", role: .destructive) { showingClear = true } }
            }
        }
        .sheet(item: $selectedMeal) { MealDetailView(meal: $0) }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Clear history?", isPresented: $showingClear) {
            Button("Clear", role: .destructive) { store.clearHistory() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func rotationRow(_ entry: RotationEntry) -> some View {
        HStack(spacing: 12) {
            MealThumbnail(meal: entry.meal, size: AppTheme.emojiTileCompact)
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.meal.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                // The bar repeats what the label says rather than replacing it, so the row
                // still reads with colour vision differences or a screen reader.
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(AppTheme.ink.opacity(0.08))
                        Capsule()
                            .fill(entry.isSnoozed ? AppTheme.muted : AppTheme.accent)
                            .frame(width: max(proxy.size.width * entry.overdue, 3))
                    }
                }
                .frame(height: 5)
            }
            Spacer(minLength: 8)
            Text(entry.label)
                .font(.caption).foregroundStyle(AppTheme.muted)
            if store.favoriteMealIDs.contains(entry.meal.id) {
                Image(systemName: "heart.fill").font(.caption2).foregroundStyle(AppTheme.destructive)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.meal.name), \(entry.label)")
        .accessibilityHint(L10n.string("Opens the recipe"))
    }

    private func stat(title: String, value: Int, symbol: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol).font(.title3).foregroundStyle(AppTheme.accent)
            Text("\(value)").font(.title2.bold())
            Text(title).font(.caption2).foregroundStyle(AppTheme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 6)
        .mealCard()
        .accessibilityElement(children: .combine)
    }

    private func eventLabel(_ event: MealFeedbackEvent) -> String {
        let action: String
        switch event.kind {
        case .cooked: action = L10n.string("Cooked")
        case .skipped: action = L10n.string("Replaced")
        case .snoozed: action = L10n.string("Paused for 28 days")
        }
        return event.weekday.map { L10n.string("%@ on %@", action, $0.name.lowercased()) } ?? action
    }
}
