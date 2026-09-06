import Foundation
import UserNotifications

/// One notification a day: what is for dinner, at a time the household chooses.
///
/// Only possible now that a plan knows which calendar week it covers -- a bare `Weekday`
/// cannot say which Tuesday it means.
struct DinnerReminderService {
    private let center: UNUserNotificationCenter
    private static let identifierPrefix = "dinner-reminder-"

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func isAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    /// Replaces all scheduled reminders with ones matching the plan as it now stands.
    ///
    /// Called after every plan change, so a reshuffled Thursday never notifies about the meal
    /// it replaced.
    func reschedule(
        plan: WeeklyPlan,
        meals: [Meal],
        hour: Int,
        minute: Int = 0,
        calendar: Calendar = .current,
        now: Date = .now
    ) async {
        cancelAll()
        guard await isAuthorized() else { return }

        for item in plan.meals {
            guard let body = reminderBody(for: item, meals: meals) else { continue }
            let day = plan.date(for: item.day, calendar: calendar)
            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = hour
            components.minute = minute
            guard let fireDate = calendar.date(from: components), fireDate > now else { continue }

            let content = UNMutableNotificationContent()
            content.title = L10n.string("Dinner today")
            content.body = body
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate),
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: Self.identifierPrefix + item.day.rawValue,
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }

    func cancelAll() {
        let identifiers = Weekday.allCases.map { Self.identifierPrefix + $0.rawValue }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private func reminderBody(for item: PlannedMeal, meals: [Meal]) -> String? {
        switch item.kind {
        case .away:
            return nil
        case .takeaway:
            return L10n.string("Takeaway tonight.")
        case .leftovers:
            guard let meal = item.mealID.flatMap({ id in meals.first(where: { $0.id == id }) }) else {
                return L10n.string("Leftovers tonight.")
            }
            return L10n.string("Leftovers: %@", meal.name)
        case .meal:
            guard let meal = item.mealID.flatMap({ id in meals.first(where: { $0.id == id }) }) else {
                return nil
            }
            return L10n.string("%@ · about %ld min", meal.name, meal.prepMinutes)
        }
    }
}
