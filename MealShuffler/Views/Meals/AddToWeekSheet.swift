import SwiftUI

/// Picks the day a recipe goes on, this week or next.
///
/// It was a menu of seven weekday names: only this week, days already gone included, nothing
/// saying what each day already had, and no word afterwards about what had happened. Now each
/// day shows what it would replace, days that have passed or been cooked are left out, and
/// the choice is confirmed.
struct AddToWeekSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let meal: Meal
    /// Called once the meal is on a day, so the recipe underneath can close too.
    let added: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if !thisWeekDays.isEmpty {
                    Section("This week") {
                        ForEach(thisWeekDays) { day in row(day, nextWeek: false) }
                    }
                }
                Section {
                    ForEach(Weekday.ordered()) { day in row(day, nextWeek: true) }
                } header: {
                    Text("Next week")
                } footer: {
                    Text("The dinner is locked on the day you choose, so a shuffle leaves it there.")
                }
            }
            .navigationTitle("Add to the week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private var thisWeekDays: [Weekday] {
        let today = Calendar.current.startOfDay(for: .now)
        return Weekday.ordered().filter { store.plan.date(for: $0) >= today && !store.isCompleted(on: $0) }
    }

    private var nextWeekStart: Date { WeekAnchor.startOfNextWeek(after: store.plan.startDate) }

    private func row(_ day: Weekday, nextWeek: Bool) -> some View {
        let item = nextWeek ? store.nextWeekPlan?[day] : store.plan[day]
        let planned = item.flatMap { $0.freezerBatch?.recipe ?? $0.mealID.flatMap { store.meal(id: $0) } }
        let date = nextWeek ? day.date(inWeekStarting: nextWeekStart) : store.plan.date(for: day)
        let isThisMeal = item?.kind == .meal && item?.mealID == meal.id
        return Button {
            add(on: day, nextWeek: nextWeek)
        } label: {
            HStack(spacing: AppTheme.Space.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(day.name) · \(date.formatted(.dateTime.day().month()))")
                        .font(.body.weight(.semibold)).foregroundStyle(AppTheme.ink)
                    Text(item.map { DayRow.title(for: $0, meal: planned) } ?? L10n.string("Not planned"))
                        .font(.caption).foregroundStyle(AppTheme.muted).lineLimit(1)
                }
                Spacer(minLength: AppTheme.Space.s)
                if isThisMeal {
                    Image(systemName: "checkmark").foregroundStyle(AppTheme.accent)
                } else if item?.isLocked == true {
                    Image(systemName: "lock.fill").font(.footnote).foregroundStyle(AppTheme.muted)
                        .accessibilityLabel("Locked")
                }
            }
            .frame(minHeight: AppTheme.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isThisMeal)
        .accessibilityIdentifier("addToWeek.\(nextWeek ? "next" : "this").\(day.rawValue)")
    }

    private func add(on day: Weekday, nextWeek: Bool) {
        let when = nextWeek ? L10n.string("%@ next week", day.name.lowercased()) : day.name.lowercased()
        if nextWeek {
            store.setNextWeekMeal(meal, on: day)
        } else {
            store.setMeal(meal, on: day)
            // setMeal refuses a day already cooked, and says why itself.
            guard store.plan[day]?.mealID == meal.id else { dismiss(); return }
        }
        Haptics.success()
        store.confirmation = L10n.string("%@ is planned for %@.", meal.name, when)
        // Closing the recipe underneath takes this sheet with it, in one movement.
        added()
    }
}
