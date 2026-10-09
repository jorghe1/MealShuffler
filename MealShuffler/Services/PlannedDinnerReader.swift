import Foundation

/// Reads the saved plan without going through `AppStore`.
///
/// The widget runs in its own process and only needs to answer "what is for dinner". Bringing
/// the whole store across would drag in the generator, SwiftUI and the import services; this
/// keeps the extension to the model layer and the repository.
struct PlannedDinnerReader {
    struct Dinner: Hashable {
        let day: Weekday
        let date: Date
        let title: String
        let emoji: String
        /// Prep time in minutes, when a meal is actually being cooked.
        let prepMinutes: Int?
        let isCooking: Bool
        /// Display name of whoever the day names as cook. Only set on a cooking day, and only
        /// while that member is still in the household.
        var cook: String? = nil
        /// The recipe being cooked, for marking it cooked from the widget. Nil on any day that
        /// is not cooking a known recipe.
        var mealID: UUID? = nil
    }

    private let repository: any AppStateRepository

    init(repository: any AppStateRepository = FileStateRepository.live()) {
        self.repository = repository
    }

    /// Dinners from `date` to the end of that plan's week, in calendar order.
    ///
    /// Returns an empty array when nothing is planned yet, which the widget renders as its
    /// own invitation rather than as an error.
    func upcoming(from date: Date = .now, calendar: Calendar = .current) -> [Dinner] {
        guard let snapshot = repository.load() else { return [] }
        guard let active = activePlan(in: snapshot, on: date, calendar: calendar) else { return [] }
        let plan = active.plan
        let contexts = active.contexts

        let meals = MealCatalog.resolve(custom: snapshot.customMeals)
        let members = snapshot.household.members
        let today = calendar.startOfDay(for: date)

        return Weekday.ordered(calendar: calendar).compactMap { day -> Dinner? in
            let dayDate = plan.date(for: day, calendar: calendar)
            guard calendar.startOfDay(for: dayDate) >= today, let item = plan[day] else { return nil }
            var result = dinner(for: item, on: day, date: dayDate, meals: meals)
            if result.isCooking, let cookID = contexts[day]?.cookMemberID {
                result.cook = members.first(where: { $0.id == cookID })?.displayName
            }
            return result
        }
    }

    /// The plan covering `date`: this week's, or next week's if it has already been prepared
    /// and the current one has run out -- with the day settings that belong to that plan.
    private func activePlan(
        in snapshot: AppStateSnapshot,
        on date: Date,
        calendar: Calendar
    ) -> (plan: WeeklyPlan, contexts: [Weekday: DayPlanContext])? {
        let weekStart = WeekAnchor.startOfWeek(containing: date, calendar: calendar)
        // Give or take a time zone: a plan made in Oslo is still this week in New York, read
        // on this calendar's days. An exact match showed "No plan yet" after a flight west.
        if WeekAnchor.isSameWeek(snapshot.plan.startDate, weekStart) {
            return (plan: snapshot.plan.anchored(to: weekStart), contexts: snapshot.dayContexts)
        }
        if let next = snapshot.nextWeekPlan, WeekAnchor.isSameWeek(next.startDate, weekStart) {
            return (plan: next.anchored(to: weekStart), contexts: snapshot.nextWeekContexts)
        }
        // A plan the app has not yet rolled over. Showing a stale week would be worse
        // than showing the invitation.
        guard snapshot.plan.startDate >= weekStart else { return nil }
        return (plan: snapshot.plan, contexts: snapshot.dayContexts)
    }

    private func dinner(
        for item: PlannedMeal,
        on day: Weekday,
        date: Date,
        meals: [Meal]
    ) -> Dinner {
        let meal = item.freezerBatch?.recipe ?? item.mealID.flatMap { id in meals.first(where: { $0.id == id }) }
        switch item.kind {
        case .away:
            return Dinner(day: day, date: date, title: L10n.string("No dinner at home"),
                          emoji: "🏃", prepMinutes: nil, isCooking: false)
        case .takeaway:
            return Dinner(day: day, date: date, title: L10n.string("Takeaway"),
                          emoji: "🥡", prepMinutes: nil, isCooking: false)
        case .leftovers:
            let title = meal.map { L10n.string(item.freezerBatch == nil ? "Leftovers: %@" : "From the freezer: %@", $0.name) } ?? L10n.string("Leftovers")
            return Dinner(day: day, date: date, title: title,
                          emoji: "♻️", prepMinutes: nil, isCooking: false)
        case .meal:
            guard let meal else {
                return Dinner(day: day, date: date, title: L10n.string("Not planned"),
                              emoji: "🍽️", prepMinutes: nil, isCooking: false)
            }
            return Dinner(day: day, date: date, title: meal.name,
                          emoji: meal.emoji, prepMinutes: meal.prepMinutes, isCooking: true,
                          mealID: meal.id)
        }
    }
}
