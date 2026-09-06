import SwiftUI
import WidgetKit

/// Tonight's dinner on the home screen.
///
/// The highest-value surface this app has: a meal plan is made once on a Sunday and then
/// needed at 16:00 on a Tuesday, which is a moment a widget answers with no notification to
/// dismiss and no app to open. Only possible now that a plan knows which calendar week it
/// covers -- a bare `Weekday` cannot say which Tuesday it means.
struct DinnerEntry: TimelineEntry {
    let date: Date
    let today: PlannedDinnerReader.Dinner?
    let upcoming: [PlannedDinnerReader.Dinner]

    static let placeholder = DinnerEntry(
        date: .now,
        today: PlannedDinnerReader.Dinner(
            day: .tuesday, date: .now, title: "Fish tacos",
            emoji: "🌮", prepMinutes: 30, isCooking: true
        ),
        upcoming: []
    )
}

struct DinnerProvider: TimelineProvider {
    private let reader = PlannedDinnerReader()

    func placeholder(in context: Context) -> DinnerEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (DinnerEntry) -> Void) {
        completion(context.isPreview ? .placeholder : entry(for: .now))
    }

    /// One entry per remaining day, so the widget rolls over at midnight on its own rather
    /// than waiting for the system to grant a refresh.
    func getTimeline(in context: Context, completion: @escaping (Timeline<DinnerEntry>) -> Void) {
        let calendar = Calendar.current
        let dinners = reader.upcoming()
        var entries = [entry(for: .now)]

        for dinner in dinners.dropFirst() {
            let midnight = calendar.startOfDay(for: dinner.date)
            if midnight > .now { entries.append(entry(for: midnight)) }
        }

        // Reload after the last planned day so a new week is picked up.
        let reload = entries.last.map { calendar.date(byAdding: .day, value: 1, to: $0.date) ?? $0.date }
            ?? calendar.date(byAdding: .hour, value: 6, to: .now) ?? .now
        completion(Timeline(entries: entries, policy: .after(reload)))
    }

    private func entry(for date: Date) -> DinnerEntry {
        let dinners = reader.upcoming(from: date)
        return DinnerEntry(date: date, today: dinners.first, upcoming: Array(dinners.dropFirst(1).prefix(3)))
    }
}

struct DinnerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DinnerEntry

    var body: some View {
        Group {
            if let today = entry.today {
                switch family {
                case .systemSmall: small(today)
                default: medium(today)
                }
            } else {
                empty
            }
        }
        .containerBackground(AppTheme.background, for: .widget)
    }

    private func small(_ dinner: PlannedDinnerReader.Dinner) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dinner.emoji).font(.system(size: 34)).accessibilityHidden(true)
            Spacer(minLength: 0)
            Text(label(for: dinner).uppercased())
                .font(.caption2.bold()).foregroundStyle(AppTheme.accent)
            Text(dinner.title)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
            if let minutes = dinner.prepMinutes {
                Text(L10n.string("%ld min", minutes))
                    .font(.caption2).foregroundStyle(AppTheme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(dinner))
    }

    private func medium(_ dinner: PlannedDinnerReader.Dinner) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(label(for: dinner).uppercased())
                    .font(.caption2.bold()).foregroundStyle(AppTheme.accent)
                Text(dinner.title)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if let minutes = dinner.prepMinutes {
                    Text(L10n.string("%ld min", minutes))
                        .font(.caption).foregroundStyle(AppTheme.muted)
                }
                Spacer(minLength: 0)
                if !entry.upcoming.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(entry.upcoming, id: \.self) { next in
                            Text("\(next.day.shortName)  \(next.title)")
                                .font(.caption2).foregroundStyle(AppTheme.muted).lineLimit(1)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            Text(dinner.emoji)
                .font(.system(size: 52))
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(dinner))
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "shuffle").font(.title2).foregroundStyle(AppTheme.accent)
            Text("No plan yet")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(AppTheme.ink)
            Text("Open Meal Shuffler to build this week.")
                .font(.caption2).foregroundStyle(AppTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Tonight" reads better than the weekday on the day itself.
    private func label(for dinner: PlannedDinnerReader.Dinner) -> String {
        Calendar.current.isDateInToday(dinner.date) ? L10n.string("Tonight") : dinner.day.name
    }

    private func accessibilityText(_ dinner: PlannedDinnerReader.Dinner) -> String {
        guard let minutes = dinner.prepMinutes else {
            return "\(label(for: dinner)), \(dinner.title)"
        }
        return L10n.string("%@, %@, about %ld minutes", label(for: dinner), dinner.title, minutes)
    }
}

struct DinnerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "no.mealshuffler.widget.dinner", provider: DinnerProvider()) { entry in
            DinnerWidgetView(entry: entry)
        }
        .configurationDisplayName(L10n.string("Dinner today"))
        .description(L10n.string("Tonight's dinner and what follows it."))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct MealShufflerWidgetBundle: WidgetBundle {
    var body: some Widget {
        DinnerWidget()
    }
}
