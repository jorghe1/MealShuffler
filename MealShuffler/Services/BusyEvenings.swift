import EventKit
import Foundation

/// Which evenings are already full.
///
/// A household knows on Sunday that Tuesday has football at six. That belongs in the plan --
/// a quick dinner that evening -- and it is already in their calendar, so the app reads it
/// rather than asking for it again. Only read, never written; nothing leaves the phone.
protocol BusyEveningProviding: AnyObject {
    /// Days in the week starting at `weekStart` with something in the calendar around dinner.
    func busyDays(inWeekStarting weekStart: Date, dinnerHour: Int) -> Set<Weekday>
}

/// Fixed answers, for tests and previews.
final class FixedBusyEvenings: BusyEveningProviding {
    var days: Set<Weekday>

    init(_ days: Set<Weekday> = []) {
        self.days = days
    }

    func busyDays(inWeekStarting weekStart: Date, dinnerHour: Int) -> Set<Weekday> { days }
}

/// Reads the device calendars through EventKit, when the household has turned it on.
final class CalendarBusyEvenings: BusyEveningProviding {
    static let enabledKey = "calendar-busy-evenings-enabled"
    static let minutesKey = "calendar-busy-evenings-minutes"
    static let defaultMinutes = 25

    private let store = EKEventStore()
    private var cache: (weekStart: Date, dinnerHour: Int, days: Set<Weekday>, readAt: Date)?

    /// Whether the household turned the feature on in Settings. Device-local: calendars are
    /// per phone.
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// The time limit a busy evening gets.
    static var minutes: Int {
        let stored = UserDefaults.standard.integer(forKey: minutesKey)
        return stored > 0 ? stored : defaultMinutes
    }

    static var isAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    /// Asks once. Returns whether events can be read.
    static func requestAccess() async -> Bool {
        if isAuthorized { return true }
        return (try? await EKEventStore().requestFullAccessToEvents()) ?? false
    }

    func busyDays(inWeekStarting weekStart: Date, dinnerHour: Int) -> Set<Weekday> {
        guard Self.isEnabled, Self.isAuthorized else { return [] }
        // Planning runs several times per change; the calendar does not move that fast.
        if let cache, cache.weekStart == weekStart, cache.dinnerHour == dinnerHour,
           Date.now.timeIntervalSince(cache.readAt) < 300 {
            return cache.days
        }
        let calendar = Calendar.current
        var days: Set<Weekday> = []
        for day in Weekday.allCases {
            let date = day.date(inWeekStarting: weekStart, calendar: calendar)
            // From two hours before dinner until an hour after: the window that decides
            // whether there is time to cook.
            guard let start = calendar.date(bySettingHour: max(dinnerHour - 2, 0), minute: 0, second: 0, of: date),
                  let end = calendar.date(bySettingHour: min(dinnerHour + 1, 23), minute: 0, second: 0, of: date) else { continue }
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
            let events = store.events(matching: predicate).filter { !$0.isAllDay && $0.availability != .free }
            if !events.isEmpty { days.insert(day) }
        }
        cache = (weekStart: weekStart, dinnerHour: dinnerHour, days: days, readAt: .now)
        return days
    }

    /// Forgets the last reading, so a change in the calendar shows up when the app returns.
    func invalidate() {
        cache = nil
    }
}
