import SwiftUI
import UIKit

/// The week on the kitchen wall: an iPad on the fridge or the counter, readable from across
/// the room, that never goes to sleep while it is showing.
///
/// Seven columns for the days, and a panel for what the room needs now: tonight, what is
/// still to buy, and the kids' wishes. On a phone the days stack instead.
struct KitchenBoardView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        NavigationStack {
            Group {
                if sizeClass == .regular {
                    HStack(alignment: .top, spacing: AppTheme.Space.l) {
                        days
                        panel.frame(width: 320)
                    }
                    .padding(AppTheme.Space.xl)
                } else {
                    ScrollView {
                        VStack(spacing: AppTheme.Space.l) {
                            panel
                            days
                        }
                        .padding(AppTheme.Space.screen)
                    }
                }
            }
            .appBackground()
            .navigationTitle(WeekAnchor.label(forWeekStarting: store.plan.startDate))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    // MARK: - Days

    @ViewBuilder private var days: some View {
        if sizeClass == .regular {
            HStack(alignment: .top, spacing: AppTheme.Space.s) {
                ForEach(Weekday.ordered(), id: \.self) { day in
                    BoardDayColumn(day: day).frame(maxWidth: .infinity)
                }
            }
        } else {
            VStack(spacing: AppTheme.Space.s) {
                ForEach(Weekday.ordered(), id: \.self) { day in BoardDayColumn(day: day) }
            }
        }
    }

    // MARK: - Panel

    private var panel: some View {
        VStack(alignment: .leading, spacing: AppTheme.Space.l) {
            groceries
            wishes
        }
    }

    private var groceries: some View {
        let remaining = store.groceryItems.filter { !store.checkedGroceryIDs.contains($0.id) }
        return VStack(alignment: .leading, spacing: AppTheme.Space.s) {
            HStack {
                Text("Still to buy").eyebrowStyle()
                Spacer()
                Text("\(remaining.count)").font(.headline.monospacedDigit()).foregroundStyle(AppTheme.muted)
            }
            if remaining.isEmpty {
                Label("Everything is bought", systemImage: "checkmark.circle")
                    .foregroundStyle(AppTheme.accent)
            } else {
                ForEach(remaining.prefix(10)) { item in
                    Button {
                        Haptics.check()
                        store.toggleGroceryItem(item)
                    } label: {
                        HStack(spacing: AppTheme.Space.s) {
                            Image(systemName: "circle").foregroundStyle(AppTheme.muted)
                            Text(item.name).foregroundStyle(AppTheme.ink).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .font(.title3)
                        .frame(minHeight: AppTheme.tapTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if remaining.count > 10 {
                    Text(L10n.string("+ %ld more", remaining.count - 10))
                        .font(.subheadline).foregroundStyle(AppTheme.muted)
                }
            }
        }
        .padding(AppTheme.Space.l)
        .mealCard()
    }

    @ViewBuilder private var wishes: some View {
        let wishes = store.pendingWishes.compactMap { wish -> (id: UUID, name: String, meal: Meal)? in
            guard let member = store.household.members.first(where: { $0.id == wish.memberID }),
                  let meal = store.meal(id: wish.mealID) else { return nil }
            return (id: wish.id, name: member.displayName, meal: meal)
        }
        if !wishes.isEmpty {
            VStack(alignment: .leading, spacing: AppTheme.Space.s) {
                Text("Wishes").eyebrowStyle()
                ForEach(wishes, id: \.id) { wish in
                    HStack(spacing: AppTheme.Space.s) {
                        Text("⭐️")
                        Text(L10n.string("%@ wishes for %@", wish.name, wish.meal.name))
                            .foregroundStyle(AppTheme.ink)
                    }
                    .font(.title3)
                }
            }
            .padding(AppTheme.Space.l)
            .mealCard()
        }
    }
}

/// One day of the board: big enough to read from the other side of the kitchen.
private struct BoardDayColumn: View {
    @Environment(AppStore.self) private var store
    let day: Weekday

    var body: some View {
        let date = store.plan.date(for: day)
        let isToday = Calendar.current.isDateInToday(date)
        let isPast = !isToday && date < Calendar.current.startOfDay(for: .now)
        let item = store.plan[day]
        let meal = item?.freezerBatch?.recipe ?? item?.mealID.flatMap { store.meal(id: $0) }
        let cook = store.cook(for: day)

        VStack(alignment: .leading, spacing: AppTheme.Space.s) {
            HStack {
                Text(day.name)
                    .font(.headline)
                    .foregroundStyle(isToday ? AppTheme.onAccent : AppTheme.ink)
                Spacer(minLength: 0)
                if store.isCompleted(on: day) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(isToday ? AppTheme.onAccent : AppTheme.accent)
                }
            }
            Group {
                if let item, item.kind == .meal, let meal {
                    MealArtwork(meal: meal)
                } else {
                    Text(emoji(for: item?.kind)).font(.system(size: 40))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(AppTheme.raised)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 220)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
            .accessibilityHidden(true)
            Text(title(item: item, meal: meal))
                .font(.title3.weight(.bold))
                .foregroundStyle(isToday ? AppTheme.onAccent : AppTheme.ink)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
            if let item, item.kind == .meal, meal != nil {
                Text(DayRow.metadata(for: item, meal: meal))
                    .font(.subheadline)
                    .foregroundStyle(isToday ? AppTheme.onAccent.opacity(0.85) : AppTheme.muted)
            }
            if let cook {
                Label(cook.displayName, systemImage: "frying.pan")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isToday ? AppTheme.onAccent : AppTheme.accent)
            }
            Spacer(minLength: 0)
        }
        .padding(AppTheme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isToday ? AppTheme.accent : AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .opacity(isPast ? 0.55 : 1)
        .accessibilityElement(children: .combine)
    }

    private func emoji(for kind: PlannedMealKind?) -> String {
        switch kind {
        case .leftovers: "♻️"
        case .away: "🏃"
        case .takeaway: "🥡"
        case .meal, nil: "·"
        }
    }

    private func title(item: PlannedMeal?, meal: Meal?) -> String {
        guard let item else { return L10n.string("Not planned") }
        switch item.kind {
        case .meal: return meal?.name ?? L10n.string("Not planned")
        case .leftovers: return meal.map { L10n.string("Leftovers: %@", $0.name) } ?? L10n.string("Leftovers")
        case .away: return L10n.string("No dinner at home")
        case .takeaway: return L10n.string("Takeaway")
        }
    }
}

