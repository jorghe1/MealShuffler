import SwiftUI

struct PlanConflictView: View {
    @EnvironmentObject private var store: AppStore
    let conflicts: [PlanConflict]
    var nextWeek = false
    @State private var editingDay: Weekday?
    @State private var pickingDay: Weekday?
    @State private var editingRule: PlanningRule?
    var body: some View {
        DisclosureGroup {
            ForEach(conflicts) { conflict in
                VStack(alignment: .leading, spacing: 8) {
                    Text(conflict.message).font(.subheadline)
                    if let suggestion = conflict.suggestion { Text(suggestion).font(.caption).foregroundStyle(AppTheme.muted) }
                    let rule = conflict.ruleID.flatMap { id in store.rules.first { $0.id == id } }
                    let days = Weekday.ordered().filter { rule?.constraint.affectedDays.contains($0) ?? true }
                    Menu("Repair plan") {
                        Menu("Choose a meal") { ForEach(days) { day in Button(day.name) { pickingDay = day } } }
                        Menu("Change portions or dinner plans") { ForEach(days) { day in Button(day.name) { editingDay = day } } }
                        if let rule {
                            Button("Edit rule") { editingRule = rule }
                            if rule.supportsPreference { Button("Make rule preferred") { store.setRuleStrength(.preferred, ruleID: rule.id) } }
                        }
                        Menu("Unlock a day") {
                            ForEach(days) { day in
                                let locked = nextWeek ? store.nextWeekPlan?[day]?.isLocked == true : store.plan[day]?.isLocked == true
                                if locked { Button(day.name) { if nextWeek { store.toggleNextWeekLock(day: day) } else { store.toggleLock(day: day) } } }
                            }
                        }
                    }.buttonStyle(.bordered)
                }.padding(.vertical, 6)
            }
        } label: {
            Label(conflicts.count == 1 ? L10n.string("%ld rule conflict", 1) : L10n.string("%ld rule conflicts", conflicts.count), systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(AppTheme.warning)
        }.padding(14).background(AppTheme.warning.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 16))
        .sheet(item: $pickingDay) { MealPickerView(day: $0, nextWeek: nextWeek).environmentObject(store) }
        .sheet(item: $editingRule) { AddRuleView(editing: $0).environmentObject(store) }
        .sheet(item: $editingDay) { day in
            DayContextEditor(day: day, initialContext: store.context(for: day, nextWeek: nextWeek),
                governingRule: store.dinnerModeRule(for: day, nextWeek: nextWeek)?.summary(meals: store.meals, context: store.matchContext)) {
                    if nextWeek { store.updateNextWeekContext($0, for: day) } else { store.updateContext($0, for: day) }
                }.environmentObject(store)
        }
    }
}
