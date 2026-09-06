import SwiftUI

/// A prepared plan for the week after this one.
///
/// Kept separate from the current week rather than replacing it, so preparing ahead never
/// costs you the week you are actually shopping for. On rollover it is promoted automatically.
struct NextWeekView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    private var nextWeekStart: Date { WeekAnchor.startOfNextWeek(after: store.plan.startDate) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                header

                if let plan = store.nextWeekPlan {
                    ForEach(Weekday.ordered()) { day in
                        if let item = plan[day] {
                            NextWeekRow(
                                day: day,
                                date: plan.date(for: day),
                                title: title(for: item),
                                emoji: emoji(for: item)
                            )
                        }
                    }

                    Button { withAnimation(.snappy) { store.planNextWeek() } } label: {
                        Label("Shuffle next week", systemImage: "shuffle")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 18))

                    Button(role: .destructive) { store.discardNextWeek() } label: {
                        Text("Discard next week").font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.top, 2)
                } else {
                    emptyState
                }

                Color.clear.frame(height: 24)
            }
            .padding(.horizontal, 16)
        }
        .appBackground()
        .navigationTitle("Next week")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(WeekAnchor.label(forWeekStarting: nextWeekStart))
                .font(.caption.bold()).foregroundStyle(AppTheme.accent)
            Text("Get ahead")
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(AppTheme.ink)
            Text("This plan takes over automatically when the week turns. Your current week is untouched.")
                .font(.subheadline).foregroundStyle(AppTheme.muted)
        }
        .padding(.top, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(.largeTitle)).foregroundStyle(AppTheme.accent)
            Text("Nothing planned for next week yet.")
                .font(.headline).foregroundStyle(AppTheme.ink)
            Text("Build it now and it will be waiting when the week turns.")
                .font(.subheadline).foregroundStyle(AppTheme.muted)
                .multilineTextAlignment(.center)
            Button { withAnimation(.snappy) { store.planNextWeek() } } label: {
                Label("Plan next week", systemImage: "sparkles")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 18))
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(26)
        .mealCard()
        .padding(.top, 20)
    }

    private func title(for item: PlannedMeal) -> String {
        let meal = item.mealID.flatMap { store.meal(id: $0) }
        switch item.kind {
        case .away: return L10n.string("No dinner at home")
        case .takeaway: return L10n.string("Takeaway")
        case .leftovers:
            return meal.map { L10n.string("Leftovers: %@", $0.name) } ?? L10n.string("Leftovers")
        case .meal:
            return meal?.name ?? L10n.string("Not planned")
        }
    }

    private func emoji(for item: PlannedMeal) -> String {
        if let meal = item.mealID.flatMap({ store.meal(id: $0) }) { return meal.emoji }
        switch item.kind {
        case .away: return "🏃"
        case .takeaway: return "🥡"
        case .leftovers: return "♻️"
        case .meal: return "🍽️"
        }
    }
}

private struct NextWeekRow: View {
    let day: Weekday
    let date: Date
    let title: String
    let emoji: String

    var body: some View {
        HStack(spacing: 13) {
            Text(emoji)
                .font(.system(size: 28))
                .frame(width: 50, height: 50)
                .background(AppTheme.accentSoft.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(date, format: .dateTime.weekday(.wide).day().month(.abbreviated))
                    .font(.caption2.bold()).foregroundStyle(AppTheme.accent)
                Text(title).font(.headline).foregroundStyle(AppTheme.ink)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .mealCard()
    }
}
