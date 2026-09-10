import EventKit
import Foundation

enum PlanTextExporter {
    static func weeklyPlan(_ plan: WeeklyPlan, meals: [Meal]) -> String {
        ([L10n.string("MEAL PLAN"), WeekAnchor.label(forWeekStarting: plan.startDate)] + Weekday.ordered().map { day in
            let date = plan.date(for: day).formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
            guard let item = plan[day] else { return "\(date): \(L10n.string("Not planned"))" }
            let title: String
            switch item.kind {
            case .away: title = L10n.string("No dinner at home")
            case .takeaway: title = L10n.string("Takeaway")
            case .leftovers:
                title = item.freezerBatch.map { L10n.string("From the freezer: %@", $0.recipe.name) } ?? item.mealID
                    .flatMap { id in meals.first(where: { $0.id == id }) }
                    .map { L10n.string("Leftovers: %@", $0.name) }
                    ?? L10n.string("Leftovers")
            case .meal:
                title = item.mealID.flatMap { id in meals.first(where: { $0.id == id }) }?.name
                    ?? L10n.string("Not planned")
            }
            return "\(date): \(title)"
        }).joined(separator: "\n")
    }

    static func groceryList(_ items: [GroceryItem], aisleOrder: [GroceryAisle] = GroceryAisle.allCases) -> String {
        aisleOrder.compactMap { aisle in
            let aisleItems = items.filter { $0.aisle == aisle }
            guard !aisleItems.isEmpty else { return nil }
            return ([aisle.name.uppercased()] + aisleItems.map { "• \($0.name) – \($0.quantityText)" }).joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}
@MainActor
struct RemindersExportService {
    private let eventStore = EKEventStore()

    func export(_ items: [GroceryItem], periodID: String = "current") async throws -> Int {
        let granted = try await eventStore.requestFullAccessToReminders()
        guard granted else { throw RemindersExportError.accessDenied }
        let calendar = try reminderList()
        let predicate = eventStore.predicateForReminders(in: [calendar])
        let existing: [EKReminder] = await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { continuation.resume(returning: $0 ?? []) }
        }
        func marker(_ id: String) -> URL? {
            var components = URLComponents()
            components.scheme = "mealshuffler"; components.host = "grocery"
            components.queryItems = [URLQueryItem(name: "period", value: periodID), URLQueryItem(name: "item", value: id)]
            return components.url
        }
        let wanted = Set(items.compactMap { marker($0.id) })
        var reused: Set<URL> = []
        for reminder in existing {
            guard let url = reminder.url, url.scheme == "mealshuffler", url.host == "grocery",
                  URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "period" })?.value == periodID else { continue }
            if !wanted.contains(url) || reused.contains(url) { try eventStore.remove(reminder, commit: false) }
            else { reused.insert(url) }
        }
        for item in items {
            let url = marker(item.id)
            let reminder = existing.first(where: { $0.url == url }) ?? EKReminder(eventStore: eventStore)
            reminder.calendar = calendar
            reminder.url = url
            reminder.title = "\(item.name) – \(item.quantityText)"
            reminder.notes = item.mealNames.isEmpty ? nil : L10n.string("For: %@", item.mealNames.sorted().joined(separator: ", "))
            try eventStore.save(reminder, commit: false)
        }
        try eventStore.commit()
        return items.count
    }

    private func reminderList() throws -> EKCalendar {
        if let existing = eventStore.calendars(for: .reminder).first(where: { $0.title == "Meal Shuffler" }) { return existing }
        guard let source = eventStore.defaultCalendarForNewReminders()?.source else { throw RemindersExportError.noDefaultList }
        let calendar = EKCalendar(for: .reminder, eventStore: eventStore)
        calendar.title = "Meal Shuffler"
        calendar.source = source
        try eventStore.saveCalendar(calendar, commit: true)
        return calendar
    }
}

enum RemindersExportError: LocalizedError {
    case accessDenied, noDefaultList
    var errorDescription: String? {
        switch self {
        case .accessDenied: L10n.string("Access to Reminders was not granted.")
        case .noDefaultList: L10n.string("Create a default list in Reminders first.")
        }
    }
}
