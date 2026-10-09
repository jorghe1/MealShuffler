import AppIntents
import SwiftUI
import WidgetKit

/// Every family of the dinner widget.
///
/// Home-screen families use the app's own palette, which adapts to dark mode. Lock-screen
/// families leave colour to the system, which renders them monochrome or vibrant.
struct DinnerWidgetView: View {
    typealias Dinner = PlannedDinnerReader.Dinner

    @Environment(\.widgetFamily) private var family
    let entry: DinnerEntry

    var body: some View {
        content
            .containerBackground(for: .widget) { background }
            // The whole widget opens tonight's dinner rather than wherever the app was last
            // left -- except the shopping counter, which is about the shop.
            .widgetURL(family == .accessoryCircular ? WidgetLinks.shop : WidgetLinks.tonight)
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryInline: inline
        case .accessoryRectangular: rectangular
        case .systemLarge: large
        case .systemMedium: medium
        default: small
        }
    }

    @ViewBuilder private var background: some View {
        switch family {
        case .accessoryCircular, .accessoryInline, .accessoryRectangular: Color.clear
        default: AppTheme.background
        }
    }

    // MARK: - Small

    @ViewBuilder private var small: some View {
        if let dinner = entry.today {
            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 4) {
                        eyebrow(dinner)
                        Spacer(minLength: 0)
                        Text(dinner.emoji).font(.system(size: 26)).accessibilityHidden(true)
                    }
                    Text(dinner.title)
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    if let meta = meta(for: dinner) {
                        Text(meta).font(.caption2).foregroundStyle(AppTheme.muted).lineLimit(1)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityText(dinner))
                Spacer(minLength: 0)
                cookedControl(for: dinner, title: L10n.string("We cooked this"), fullWidth: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            empty
        }
    }

    // MARK: - Medium

    @ViewBuilder private var medium: some View {
        if let dinner = entry.today {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    VStack(alignment: .leading, spacing: 4) {
                        eyebrow(dinner)
                        HStack(alignment: .top, spacing: 6) {
                            Text(dinner.emoji).font(.system(size: 26)).accessibilityHidden(true)
                            Text(dinner.title)
                                .font(.system(.headline, design: .rounded, weight: .bold))
                                .foregroundStyle(AppTheme.ink)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                        }
                        if let meta = meta(for: dinner) {
                            Text(meta).font(.caption2).foregroundStyle(AppTheme.muted).lineLimit(1)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(accessibilityText(dinner))
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        cookedControl(for: dinner, title: L10n.string("Cooked"), fullWidth: false)
                        swapLink(for: dinner)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                Rectangle()
                    .fill(AppTheme.ink.opacity(0.1))
                    .frame(width: 1)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    if entry.upcoming.isEmpty {
                        Text(L10n.string("Nothing more planned this week"))
                            .font(.caption).foregroundStyle(AppTheme.muted)
                    } else {
                        ForEach(entry.upcoming, id: \.self) { next in
                            compactRow(next)
                        }
                    }
                    Spacer(minLength: 0)
                    shopLink(groceryCountText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        } else {
            empty
        }
    }

    // MARK: - Large

    @ViewBuilder private var large: some View {
        if let dinner = entry.today {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(L10n.string("Week %ld", weekNumber))
                        .font(AppTheme.Typography.section)
                        .foregroundStyle(AppTheme.ink)
                    Spacer(minLength: 4)
                    Text(WeekAnchor.label(forWeekStarting: WeekAnchor.startOfWeek(containing: entry.date)))
                        .font(.caption).foregroundStyle(AppTheme.muted).lineLimit(1)
                }
                .accessibilityElement(children: .combine)

                highlightedRow(dinner)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(entry.rest, id: \.self) { next in
                        compactRow(next)
                    }
                }

                Spacer(minLength: 0)
                shopLink(groceryPreviewText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            empty
        }
    }

    private func highlightedRow(_ dinner: Dinner) -> some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Text(dinner.emoji).font(.system(size: 34)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    eyebrow(dinner)
                    Text(dinner.title)
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if let meta = meta(for: dinner) {
                        Text(meta).font(.caption2).foregroundStyle(AppTheme.muted).lineLimit(1)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityText(dinner))
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 5) {
                cookedControl(for: dinner, title: L10n.string("Cooked"), fullWidth: false)
                swapLink(for: dinner)
            }
        }
        .padding(10)
        .background(AppTheme.accentSoft, in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
    }

    // MARK: - Lock screen

    @ViewBuilder private var rectangular: some View {
        if let dinner = entry.today {
            VStack(alignment: .leading, spacing: 1) {
                Text(rectangularEyebrow(dinner))
                    .font(.caption2.bold())
                    .widgetAccentable()
                    .lineLimit(1)
                Text(dinner.emoji + " " + dinner.title)
                    .font(.headline)
                    .lineLimit(1)
                if let meta = meta(for: dinner) {
                    Text(meta).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityText(dinner))
        } else {
            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.string("No plan yet")).font(.headline).widgetAccentable()
                Text(L10n.string("Open Meal Shuffler to build this week."))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var inline: some View {
        if let dinner = entry.today {
            if entry.isTonight(dinner) {
                Text(L10n.string("%@ tonight", dinner.emoji + " " + dinner.title))
            } else {
                Text(dinner.day.shortName + ": " + dinner.emoji + " " + dinner.title)
            }
        } else {
            Text(L10n.string("No plan yet"))
        }
    }

    private var circular: some View {
        let remaining = entry.summary.groceryRemaining
        return ZStack {
            AccessoryWidgetBackground()
            if remaining > 0 {
                VStack(spacing: 0) {
                    Image(systemName: "cart")
                        .font(.system(size: 13, weight: .semibold))
                    Text(remaining, format: .number)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                .padding(4)
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .bold))
            }
        }
        .widgetAccentable()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(groceryCountText)
    }

    // MARK: - Pieces

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "shuffle").font(.title2).foregroundStyle(AppTheme.accent)
                .accessibilityHidden(true)
            Text(L10n.string("No plan yet"))
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(AppTheme.ink)
            Text(L10n.string("Open Meal Shuffler to build this week."))
                .font(.caption2).foregroundStyle(AppTheme.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func eyebrow(_ dinner: Dinner) -> some View {
        Text(dayLabel(for: dinner).uppercased())
            .font(.caption2.bold())
            .foregroundStyle(AppTheme.accent)
            .lineLimit(1)
    }

    /// One later day: short weekday, emoji and dish.
    private func compactRow(_ dinner: Dinner) -> some View {
        HStack(spacing: 6) {
            Text(dinner.day.shortName)
                .font(.caption2.bold())
                .foregroundStyle(AppTheme.muted)
                .frame(width: 30, alignment: .leading)
            Text(dinner.emoji).font(.caption).accessibilityHidden(true)
            Text(dinner.title)
                .font(.caption)
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(dinner.day.name + ", " + dinner.title)
    }

    /// "We cooked this" on tonight's cooking day; a tick once it has been; nothing otherwise.
    @ViewBuilder
    private func cookedControl(for dinner: Dinner, title: String, fullWidth: Bool) -> some View {
        if dinner.isCooking, entry.isTonight(dinner) {
            if entry.isCooked(dinner) {
                Text(L10n.string("Cooked") + " ✓")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.accent)
                    .padding(.vertical, 6)
            } else if let mealID = dinner.mealID {
                Button(intent: MarkDinnerCookedIntent(mealID: mealID, day: dinner.day, date: dinner.date)) {
                    Text(verbatim: "✓ " + title)
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.onAccent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: fullWidth ? CGFloat.infinity : nil)
                        .background(AppTheme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func swapLink(for dinner: Dinner) -> some View {
        if let url = WidgetLinks.day(dinner.day) {
            Link(destination: url) {
                Text(L10n.string("Swap"))
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.accent)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppTheme.raised, in: Capsule())
            }
        }
    }

    @ViewBuilder
    private func shopLink(_ text: String) -> some View {
        if let url = WidgetLinks.shop {
            Link(destination: url) {
                Text(text)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Text

    /// "Tonight" reads better than the weekday on the day itself.
    private func dayLabel(for dinner: Dinner) -> String {
        entry.isTonight(dinner) ? L10n.string("Tonight") : dinner.day.name
    }

    private func rectangularEyebrow(_ dinner: Dinner) -> String {
        let label = dayLabel(for: dinner)
        guard dinner.isCooking, entry.isTonight(dinner), entry.isCooked(dinner) else { return label }
        return label + " · " + L10n.string("Cooked") + " ✓"
    }

    /// "30 min · Kari cooks"; nil when there is neither.
    private func meta(for dinner: Dinner) -> String? {
        var parts: [String] = []
        if let minutes = dinner.prepMinutes {
            parts.append(L10n.string("%ld min", minutes))
        }
        if let cook = dinner.cook {
            parts.append(L10n.string("%@ cooks", cook))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var weekNumber: Int {
        Calendar.current.component(.weekOfYear, from: entry.date)
    }

    /// "🛒 12 items left".
    private var groceryCountText: String {
        let remaining = entry.summary.groceryRemaining
        switch remaining {
        case 0: return "🛒 " + L10n.string("Nothing left to buy")
        case 1: return "🛒 " + L10n.string("1 item left")
        default: return "🛒 " + L10n.string("%ld items left", remaining)
        }
    }

    /// "🛒 Sour cream, lime, tortillas + 9".
    private var groceryPreviewText: String {
        let summary = entry.summary
        let shown = Array(summary.groceryPreview.prefix(3))
        guard summary.groceryRemaining > 0, !shown.isEmpty else { return groceryCountText }
        let more = summary.groceryRemaining - shown.count
        let list = "🛒 " + shown.joined(separator: ", ")
        return more > 0 ? list + " + " + String(more) : list
    }

    private func accessibilityText(_ dinner: Dinner) -> String {
        var text: String
        if let minutes = dinner.prepMinutes {
            text = L10n.string("%@, %@, about %ld minutes", dayLabel(for: dinner), dinner.title, minutes)
        } else {
            text = dayLabel(for: dinner) + ", " + dinner.title
        }
        if let cook = dinner.cook {
            text += ", " + L10n.string("%@ cooks", cook)
        }
        if dinner.isCooking, entry.isTonight(dinner), entry.isCooked(dinner) {
            text += ", " + L10n.string("Cooked")
        }
        return text
    }
}
