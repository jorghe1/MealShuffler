import SwiftUI

/// A prepared plan for the week after this one.
///
/// Kept separate from the current week rather than replacing it, so preparing ahead never
/// costs you the week you are actually shopping for. On rollover it is promoted automatically.
struct NextWeekView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var editingDay: Weekday?
    @State private var selectedMeal: Meal?
    @State private var pickingDay: Weekday?

    private var nextWeekStart: Date { WeekAnchor.startOfNextWeek(after: store.plan.startDate) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                header
                if !store.nextWeekConflicts.isEmpty { PlanConflictView(conflicts: store.nextWeekConflicts, nextWeek: true) }

                if let plan = store.nextWeekPlan {
                    ForEach(Weekday.ordered()) { day in
                        if let item = plan[day] {
                            DayPlanCard(day: day, date: plan.date(for: day), item: item,
                                meal: item.mealID.flatMap { store.meal(id: $0) }, explanation: nil,
                                isCompleted: false, clearCompletion: {}, isFavorite: item.mealID.map { store.favoriteMealIDs.contains($0) } ?? false,
                                open: { selectedMeal = item.mealID.flatMap { store.meal(id: $0) } },
                                chooseMeal: { pickingDay = day }, editContext: { editingDay = day },
                                toggleLock: { store.toggleNextWeekLock(day: day) },
                                shuffle: { store.shuffleNextWeek(day: day, intent: $0) }, snooze: {},
                                toggleFavorite: { if let meal = item.mealID.flatMap({ store.meal(id: $0) }) { store.toggleFavorite(meal) } },
                                markCooked: {}, markSkipped: {}, cook: {},
                                swapWith: { store.swapNextWeek(between: day, and: $0) }, allowsCooking: false)
                        } else {
                            Text(day.name).font(.headline)
                            Button("Plan this day") { editingDay = day }
                            Button("Choose a meal") { pickingDay = day }
                        }
                    }

                    Button { Task { await store.generateInBackground(nextWeek: true) } } label: {
                        Label("Shuffle next week", systemImage: "shuffle")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: AppTheme.controlRadius))

                    Button(role: .destructive) { store.discardNextWeek() } label: {
                        Text("Discard next week").font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.top, 2)
                } else {
                    emptyState
                }

                Color.clear.frame(height: 24)
            }
            .padding(.horizontal, 16)
        }
        .appBackground()
        .navigationTitle("Next week")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $pickingDay) { MealPickerView(day: $0, nextWeek: true).environmentObject(store) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if store.canUndo { Button("Undo") { store.undoLastChange() } }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if let plan = store.nextWeekPlan { ShareLink(item: PlanTextExporter.weeklyPlan(plan, meals: store.meals)) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Share next week") }
            }
        }
        .sheet(item: $selectedMeal) { MealDetailView(meal: $0) }
        .sheet(item: $editingDay) { day in
            DayContextEditor(day: day, initialContext: store.context(for: day, nextWeek: true),
                governingRule: store.dinnerModeRule(for: day, nextWeek: true)?.summary(meals: store.meals, context: store.matchContext)) {
                    store.updateNextWeekContext($0, for: day)
                }.environmentObject(store)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(WeekAnchor.label(forWeekStarting: nextWeekStart))
                .font(.caption.bold()).foregroundStyle(AppTheme.accent)
            Text("Get ahead")
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(AppTheme.ink)
            Text("This plan takes over automatically when the week turns. Your current week is untouched.")
                .font(.subheadline).foregroundStyle(AppTheme.muted)
        }
        .padding(.top, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(.largeTitle)).foregroundStyle(AppTheme.accent)
            Text("Nothing planned for next week yet.")
                .font(.headline).foregroundStyle(AppTheme.ink)
            Text("Build it now and it will be waiting when the week turns.")
                .font(.subheadline).foregroundStyle(AppTheme.muted)
                .multilineTextAlignment(.center)
            Button { Task { await store.generateInBackground(nextWeek: true) } } label: {
                Label("Plan next week", systemImage: "sparkles")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: AppTheme.controlRadius))
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(26)
        .mealCard()
        .padding(.top, 20)
    }

    private func title(for item: PlannedMeal) -> String {
        let meal = item.mealID.flatMap { store.meal(id: $0) }
        switch item.kind {
        case .away: return L10n.string("No dinner at home")
        case .takeaway: return L10n.string("Takeaway")
        case .leftovers:
            return meal.map { L10n.string("Leftovers: %@", $0.name) } ?? L10n.string("Leftovers")
        case .meal:
            return meal?.name ?? L10n.string("Not planned")
        }
    }

    private func emoji(for item: PlannedMeal) -> String {
        if let meal = item.mealID.flatMap({ store.meal(id: $0) }) { return meal.emoji }
        switch item.kind {
        case .away: return "🏃"
        case .takeaway: return "🥡"
        case .leftovers: return "♻️"
        case .meal: return "🍽️"
        }
    }
}
