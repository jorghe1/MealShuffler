import SwiftUI
import WidgetKit

/// Tonight's dinner on the home screen and the lock screen.
///
/// The highest-value surface this app has: a meal plan is made once on a Sunday and then
/// needed at 16:00 on a Tuesday, which is a moment a widget answers with no notification to
/// dismiss and no app to open. Only possible now that a plan knows which calendar week it
/// covers -- a bare `Weekday` cannot say which Tuesday it means.
struct DinnerEntry: TimelineEntry {
    let date: Date
    /// The first planned dinner on or after `date`; usually tonight's.
    let today: PlannedDinnerReader.Dinner?
    /// Every planned dinner after `today`, to the end of the week.
    let rest: [PlannedDinnerReader.Dinner]
    /// What the app wrote for the widget: the shopping list and days already cooked.
    let summary: WidgetSummary

    /// The next few days, for the medium widget.
    var upcoming: [PlannedDinnerReader.Dinner] { Array(rest.prefix(3)) }

    /// Whether `dinner` falls on this entry's own day.
    ///
    /// Compared with the entry's date rather than with now: WidgetKit renders future entries
    /// ahead of time, and Tuesday's entry must already say "Tonight" when it is drawn on Monday.
    func isTonight(_ dinner: PlannedDinnerReader.Dinner, calendar: Calendar = .current) -> Bool {
        calendar.isDate(dinner.date, inSameDayAs: date)
    }

    func isCooked(_ dinner: PlannedDinnerReader.Dinner) -> Bool {
        summary.cookedStamps.contains(WidgetSummary.stamp(for: dinner.date))
    }

    static let placeholder = DinnerEntry(
        date: .now,
        today: PlannedDinnerReader.Dinner(
            day: .tuesday, date: .now, title: "Fish tacos",
            emoji: "🌮", prepMinutes: 30, isCooking: true,
            cook: "Kari", mealID: nil
        ),
        rest: [
            PlannedDinnerReader.Dinner(
                day: .wednesday, date: .now.addingTimeInterval(86_400), title: "Pasta pesto",
                emoji: "🍝", prepMinutes: 20, isCooking: true
            ),
            PlannedDinnerReader.Dinner(
                day: .thursday, date: .now.addingTimeInterval(2 * 86_400), title: "Chicken curry",
                emoji: "🍛", prepMinutes: 40, isCooking: true
            ),
            PlannedDinnerReader.Dinner(
                day: .friday, date: .now.addingTimeInterval(3 * 86_400), title: "Pizza",
                emoji: "🍕", prepMinutes: 45, isCooking: true
            )
        ],
        summary: WidgetSummary(groceryRemaining: 12, groceryPreview: ["Sour cream", "lime", "tortillas"], cookedStamps: [])
    )
}

struct DinnerProvider: TimelineProvider {
    private let reader = PlannedDinnerReader()

    func placeholder(in context: Context) -> DinnerEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (DinnerEntry) -> Void) {
        completion(context.isPreview ? .placeholder : entry(for: .now, summary: WidgetSummary.load()))
    }

    /// An entry at every midnight until the week turns, planned or not, then a reload.
    ///
    /// Entries used to follow planned days only, and the reload came a day after the last
    /// one -- or 24 hours after *now* when nothing was planned -- so Monday could show
    /// Sunday's dinner, and a day with nothing planned kept the day before on screen.
    func getTimeline(in context: Context, completion: @escaping (Timeline<DinnerEntry>) -> Void) {
        let calendar = Calendar.current
        let now = Date.now
        // Read once: the app reloads every timeline whenever it rewrites the summary, and the
        // widget's own button does the same after ticking a day.
        let summary = WidgetSummary.load()
        var entries = [entry(for: now, summary: summary)]
        var midnight = calendar.startOfDay(for: now)
        for _ in 0..<8 {
            guard let next = calendar.date(byAdding: .day, value: 1, to: midnight) else { break }
            midnight = next
            entries.append(entry(for: midnight, summary: summary))
            // The first midnight of a new week: reload there, when the app or a background
            // refresh may have written the new week.
            if WeekAnchor.startOfWeek(containing: midnight, calendar: calendar) == midnight { break }
        }
        let reload = entries.last?.date ?? calendar.date(byAdding: .hour, value: 6, to: now) ?? now
        completion(Timeline(entries: entries, policy: .after(reload)))
    }

    private func entry(for date: Date, summary: WidgetSummary) -> DinnerEntry {
        let dinners = reader.upcoming(from: date)
        return DinnerEntry(date: date, today: dinners.first, rest: Array(dinners.dropFirst(1)), summary: summary)
    }
}

/// The app's own links. `AppRouter.open(_:)` handles each of them.
enum WidgetLinks {
    static let tonight = URL(string: "mealshuffler://tonight")
    static let shop = URL(string: "mealshuffler://shop")

    /// Opens that day's sheet, where the dish can be swapped.
    static func day(_ day: Weekday) -> URL? {
        URL(string: "mealshuffler://day/\(day.rawValue)")
    }
}

struct DinnerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "no.mealshuffler.widget.dinner", provider: DinnerProvider()) { entry in
            DinnerWidgetView(entry: entry)
        }
        .configurationDisplayName(L10n.string("Dinner today"))
        .description(L10n.string("Tonight's dinner and what follows it."))
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryRectangular, .accessoryInline, .accessoryCircular
        ])
    }
}

@main
struct MealShufflerWidgetBundle: WidgetBundle {
    var body: some Widget {
        DinnerWidget()
        CookingTimerLiveActivity()
    }
}
