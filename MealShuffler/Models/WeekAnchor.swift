import Foundation

/// Ties the abstract week to the calendar.
///
/// `Weekday` on its own is a floating artefact: it cannot say which Tuesday it means, so the
/// plan never rolls over, history cannot be dated, and nothing can be scheduled against it.
enum WeekAnchor {
    /// Midnight on the first day of the week containing `date`, honouring the locale's
    /// `firstWeekday` rather than assuming Monday.
    static func startOfWeek(containing date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start
            ?? calendar.startOfDay(for: date)
    }

    static func startOfCurrentWeek(calendar: Calendar = .current) -> Date {
        startOfWeek(containing: .now, calendar: calendar)
    }

    static func startOfNextWeek(after start: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .weekOfYear, value: 1, to: start) ?? start.addingTimeInterval(7 * 86_400)
    }

    /// Human label for a week, e.g. "6–12 Oct".
    static func label(forWeekStarting start: Date, calendar: Calendar = .current) -> String {
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        let formatter = DateIntervalFormatter()
        formatter.calendar = calendar
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: start, to: end)
    }
}

extension Weekday {
    /// The days in the order this locale's week actually runs.
    ///
    /// `allCases` is declared Monday-first. A locale starting on Sunday needs Sunday to be the
    /// first card in the planner, the first day generated, and a valid leftovers source for
    /// Monday -- all of which depend on this order rather than the declaration order.
    static func ordered(calendar: Calendar = .current) -> [Weekday] {
        // Calendar counts Sunday as 1; allCases starts at Monday.
        let rotation = (calendar.firstWeekday + 5) % 7
        guard rotation > 0, rotation < allCases.count else { return allCases }
        return Array(allCases[rotation...] + allCases[..<rotation])
    }

    /// Position within the locale's week, 0-based.
    static func position(of day: Weekday, calendar: Calendar = .current) -> Int {
        ordered(calendar: calendar).firstIndex(of: day) ?? 0
    }

    /// The calendar date this weekday falls on within the week starting at `weekStart`.
    func date(inWeekStarting weekStart: Date, calendar: Calendar = .current) -> Date {
        calendar.date(
            byAdding: .day,
            value: Weekday.position(of: self, calendar: calendar),
            to: weekStart
        ) ?? weekStart
    }

    /// Locale-correct short name. Replaces a three-character prefix of the localized name,
    /// which only worked by coincidence for English and Norwegian.
    static func shortSymbol(for day: Weekday, calendar: Calendar = .current) -> String {
        var formatterCalendar = calendar
        formatterCalendar.locale = .current
        let symbols = formatterCalendar.shortWeekdaySymbols
        // shortWeekdaySymbols is always Sunday-first regardless of firstWeekday.
        let sundayFirstIndex = (Weekday.allCases.firstIndex(of: day).map { $0 + 1 } ?? 0) % 7
        guard symbols.indices.contains(sundayFirstIndex) else { return String(day.name.prefix(3)) }
        return symbols[sundayFirstIndex]
    }
}

/// Stable per-install identity.
///
/// Not an account and not a secret. It exists so every write can record *where* it came from,
/// which is the one thing a future merge cannot reconstruct after the fact.
enum DeviceIdentity {
    private static let key = "meal-shuffler-device-id"

    static let current: UUID = {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: key), let existing = UUID(uuidString: raw) {
            return existing
        }
        let fresh = UUID()
        defaults.set(fresh.uuidString, forKey: key)
        return fresh
    }()
}
