import SwiftUI

/// The last onboarding step: a real week, already generated.
///
/// Onboarding used to run welcome -> seven swipes -> rule toggles -> and only then produce
/// anything. That asks for the work before showing the payoff. Generating the week first
/// makes the rules something you adjust because you can see why, rather than a form to fill
/// in before you know what the app does.
struct FirstWeekStepView: View {
    @EnvironmentObject private var store: AppStore
    let finished: () -> Void

    @State private var isTuning = false
    @State private var remindersDeclined = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    Stepper(L10n.string("%ld people at dinner", store.householdSize), value: Binding(get: { store.householdSize }, set: { store.setHouseholdSize($0) }), in: 1...20)

                    ForEach(Weekday.ordered()) { day in
                        if let item = store.plan[day] {
                            FirstWeekRow(
                                day: day,
                                title: title(for: item),
                                emoji: emoji(for: item),
                                minutes: item.mealID.flatMap { store.meal(id: $0)?.prepMinutes }
                            )
                        }
                    }

                    Button {
                        Haptics.shuffle()
                        withAnimation(.snappy) { store.shuffleAll() }
                    } label: {
                        Label("Try another week", systemImage: "shuffle")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: AppTheme.controlRadius))

                    reminderCard
                    rules

                    Color.clear.frame(height: 12)
                }
                .padding(.horizontal, 24)
            }

            Button(action: finished) {
                Text("Start planning")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 17)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: AppTheme.controlRadius))
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
            .padding(.top, 6)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Here's your week")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(AppTheme.ink)
            Text("Built from what you liked. Nothing is fixed — change any of it later.")
                .foregroundStyle(AppTheme.muted).lineSpacing(3)
        }
        .padding(.top, 20)
    }

    /// Asks for notifications here, and only here.
    ///
    /// The only way to find this was a toggle buried in a section called "Settings" inside
    /// the Rules tab, default off -- so most households never learned the feature existed.
    /// This is the moment it makes sense: a real week is on screen, and the offer is about
    /// that week rather than about permissions.
    private var reminderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(
                get: { store.dinnerReminderEnabled },
                set: { wanted in
                    Task { @MainActor in
                        let granted = await store.setDinnerReminder(enabled: wanted)
                        remindersDeclined = wanted && !granted
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Remind me what's for dinner")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.ink)
                    Text("One notification a day, at a time you choose.")
                        .font(.caption).foregroundStyle(AppTheme.muted)
                }
            }
            if remindersDeclined {
                Text("Notifications are off for Meal Shuffler. You can turn them on later in Settings.")
                    .font(.caption).foregroundStyle(AppTheme.warning)
            }
        }
        .padding(16)
        .mealCard()
    }

    /// Folded away by default. The rules are worth adjusting once you can see their effect,
    /// not before.
    private var rules: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.snappy) { isTuning.toggle() }
            } label: {
                HStack {
                    Label("Rules we assumed", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.ink)
                    Spacer()
                    Image(systemName: isTuning ? "chevron.up" : "chevron.down")
                        .font(.caption.bold()).foregroundStyle(AppTheme.muted)
                }
            }
            .buttonStyle(.plain)

            if isTuning {
                HStack {
                    Label("People at dinner", systemImage: "person.2")
                        .font(.subheadline)
                    Spacer()
                    Stepper(
                        "\(store.householdSize)",
                        value: Binding(
                            get: { store.householdSize },
                            set: { store.setHouseholdSize($0) }
                        ),
                        in: 1...12
                    )
                    .fixedSize()
                }

                ForEach(store.rules) { rule in
                    Toggle(isOn: Binding(
                        get: { store.rules.first(where: { $0.id == rule.id })?.isEnabled ?? false },
                        set: { store.setRule(rule, enabled: $0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.title).font(.subheadline.weight(.semibold))
                            Text(rule.summary(meals: store.meals, context: store.matchContext))
                                .font(.caption).foregroundStyle(AppTheme.muted)
                        }
                    }
                    .accessibilityLabel(rule.title)
                }
            }
        }
        .padding(16)
        .mealCard()
    }

    private func title(for item: PlannedMeal) -> String {
        let meal = item.mealID.flatMap { store.meal(id: $0) }
        switch item.kind {
        case .away: return L10n.string("No dinner at home")
        case .takeaway: return L10n.string("Takeaway")
        case .leftovers: return meal.map { L10n.string("Leftovers: %@", $0.name) } ?? L10n.string("Leftovers")
        case .meal: return meal?.name ?? L10n.string("Not planned")
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

private struct FirstWeekRow: View {
    let day: Weekday
    let title: String
    let emoji: String
    let minutes: Int?

    var body: some View {
        HStack(spacing: 12) {
            MealThumbnail(emoji: emoji, size: AppTheme.emojiTileCompact)
            VStack(alignment: .leading, spacing: 2) {
                Text(day.name.uppercased())
                    .font(.caption2.bold()).tracking(0.7).foregroundStyle(AppTheme.accent)
                Text(title).font(.headline).foregroundStyle(AppTheme.ink).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let minutes {
                Text(L10n.string("%ld min", minutes))
                    .font(.caption).foregroundStyle(AppTheme.muted)
            }
        }
        .padding(12)
        .mealCard()
        .accessibilityElement(children: .combine)
    }
}
