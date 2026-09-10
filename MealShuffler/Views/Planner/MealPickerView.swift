import SwiftUI

/// Chooses the dinner for one day.
///
/// The action the app could not express. Rules say what the generator should prefer, intents
/// say what kind of replacement to roll, and locks pin whatever it already picked -- none of
/// them says "Thursday is lasagne", which is the first thing a household wants from a
/// planner. Picking here locks the day, so the choice survives the next shuffle.
struct MealPickerView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let day: Weekday
    var nextWeek = false

    @State private var searchText = ""
    @State private var filter: MealFilter = .all

    /// Meals already on the plan on another day, so picking one does not quietly create a
    /// repeat the generator spends real effort avoiding.
    private var elsewhereThisWeek: [UUID: Weekday] {
        var byMeal: [UUID: Weekday] = [:]
        for item in (nextWeek ? store.nextWeekPlan?.meals ?? [] : store.plan.meals) where item.day != day {
            if let mealID = item.mealID, byMeal[mealID] == nil { byMeal[mealID] = item.day }
        }
        return byMeal
    }

    private var results: [Meal] {
        store.meals
            .filter { filter.matches($0, favorites: store.favoriteMealIDs) }
            .filter { $0.matches(searchText: searchText) }
            .sorted { lhs, rhs in
                let leftFavorite = store.favoriteMealIDs.contains(lhs.id)
                let rightFavorite = store.favoriteMealIDs.contains(rhs.id)
                if leftFavorite != rightFavorite { return leftFavorite }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    filterRow
                    if results.isEmpty { emptyState }
                    ForEach(results) { meal in
                        Button {
                            if nextWeek { store.setNextWeekMeal(meal, on: day) } else { store.setMeal(meal, on: day) }
                            Haptics.success()
                            dismiss()
                        } label: {
                            MealRow(meal: meal, isFavorite: store.favoriteMealIDs.contains(meal.id), note: note(for: meal))
                                .mealCard()
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(L10n.string("Puts this on %@", day.name.lowercased()))
                    }
                    Color.clear.frame(height: 20)
                }
                .padding(16)
            }
            .appBackground()
            .navigationTitle(L10n.string("Dinner on %@", day.name.lowercased()))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search meals")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private var filterRow: some View {
        HStack(spacing: 8) {
            ForEach(MealFilter.allCases) { option in
                Button {
                    withAnimation(.snappy) { filter = option }
                } label: {
                    Text(option.name).chipStyle(selected: filter == option)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(filter == option ? [.isButton, .isSelected] : [.isButton])
            }
            Spacer(minLength: 0)
        }
    }

    private func note(for meal: Meal) -> String? {
        elsewhereThisWeek[meal.id].map { L10n.string("Already on %@", $0.name.lowercased()) }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(.largeTitle)).foregroundStyle(AppTheme.accent)
            Text("No meals match")
                .font(.headline).foregroundStyle(AppTheme.ink)
            Text("Try another word, or add the meal in the Meals tab first.")
                .font(.subheadline).foregroundStyle(AppTheme.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(30)
        .mealCard()
    }
}
