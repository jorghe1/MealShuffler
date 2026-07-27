import EventKit
import Foundation

enum PlanTextExporter {
    static func weeklyPlan(_ plan: WeeklyPlan, meals: [Meal]) -> String {
        (["MIDDAGSPLAN"] + Weekday.allCases.compactMap { day in
            guard let item = plan[day] else { return nil }
            let title: String
            switch item.kind {
            case .away: title = "Ingen middag hjemme"
            case .takeaway: title = "Takeaway"
            case .leftovers: title = item.mealID.flatMap { id in meals.first(where: { $0.id == id }) }.map { "Rester: \($0.name)" } ?? "Rester"
            case .meal: title = item.mealID.flatMap { id in meals.first(where: { $0.id == id }) }?.name ?? "Ikke planlagt"
            }
            return "\(day.name): \(title)"
        }).joined(separator: "\n")
    }

    static func groceryList(_ items: [GroceryItem]) -> String {
        GroceryAisle.allCases.compactMap { aisle in
            let aisleItems = items.filter { $0.aisle == aisle }
            guard !aisleItems.isEmpty else { return nil }
            return ([aisle.name.uppercased()] + aisleItems.map { "• \($0.name) – \($0.quantityText)" }).joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}
@MainActor
struct RemindersExportService {
    private let eventStore = EKEventStore()

    func export(_ items: [GroceryItem]) async throws -> Int {
        let granted = try await eventStore.requestFullAccessToReminders()
        guard granted else { throw RemindersExportError.accessDenied }
        let calendar = try reminderList()
        for item in items {
            let reminder = EKReminder(eventStore: eventStore)
            reminder.calendar = calendar
            reminder.title = "\(item.name) – \(item.quantityText)"
            reminder.notes = item.mealNames.isEmpty ? nil : "Til: \(item.mealNames.sorted().joined(separator: ", "))"
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
        case .accessDenied: "Tilgang til Påminnelser ble ikke gitt."
        case .noDefaultList: "Opprett en standardliste i Påminnelser først."
        }
    }
}
