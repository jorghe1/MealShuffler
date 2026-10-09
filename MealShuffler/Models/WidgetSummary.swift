import Foundation

/// What the widget shows that it cannot work out for itself.
///
/// The widget decodes the saved plan, but the shopping list is built by the app's planner,
/// which a widget extension does not carry. The app writes this small summary to the shared
/// container after every save instead, and the widget reads it.
struct WidgetSummary: Codable, Equatable {
    /// Items still to buy on the current shopping list.
    var groceryRemaining: Int
    /// The first few, in shop order, for the large widget.
    var groceryPreview: [String]
    /// Days marked cooked from the widget or the app, as yyyy-MM-dd stamps, so the widget can
    /// show a tick straight away without waiting for the app.
    var cookedStamps: Set<String>

    static let empty = WidgetSummary(groceryRemaining: 0, groceryPreview: [], cookedStamps: [])

    private static let key = "widget-summary"

    static func load(from defaults: UserDefaults = AppGroup.defaults) -> WidgetSummary {
        guard let data = defaults.data(forKey: key),
              let summary = try? JSONDecoder().decode(WidgetSummary.self, from: data) else { return .empty }
        return summary
    }

    func save(to defaults: UserDefaults = AppGroup.defaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }

    /// Locale-independent day key.
    static func stamp(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// Dinners marked cooked from the widget, waiting for the app to record them.
///
/// A widget button runs in the widget's process, which has no store. Writing the app's state
/// file from there would be overwritten by the app's next save, so the widget leaves a note
/// here and the app records it the next time it is active or refreshed in the background.
enum WidgetActionInbox {
    struct CookedNote: Codable, Equatable {
        let mealID: UUID
        let day: Weekday
        let date: Date
    }

    private static let key = "widget-cooked-inbox"

    static func add(_ note: CookedNote, defaults: UserDefaults = AppGroup.defaults) {
        var notes = all(defaults: defaults)
        guard !notes.contains(note) else { return }
        notes.append(note)
        if let data = try? JSONEncoder().encode(notes) { defaults.set(data, forKey: key) }
    }

    static func all(defaults: UserDefaults = AppGroup.defaults) -> [CookedNote] {
        guard let data = defaults.data(forKey: key),
              let notes = try? JSONDecoder().decode([CookedNote].self, from: data) else { return [] }
        return notes
    }

    /// Returns what was waiting and empties the inbox.
    static func drain(defaults: UserDefaults = AppGroup.defaults) -> [CookedNote] {
        let notes = all(defaults: defaults)
        defaults.removeObject(forKey: key)
        return notes
    }
}
