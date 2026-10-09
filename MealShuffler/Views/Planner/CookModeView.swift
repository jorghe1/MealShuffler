import ActivityKit
import SwiftUI
import UserNotifications

/// Step-by-step cooking, with the screen kept awake.
///
/// The app was only useful while planning. This is the other half of the promise: it is open
/// on the counter while dinner is actually being made, which is also when marking a meal
/// cooked costs nothing rather than being an admin task remembered later.
struct CookModeView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let meal: Meal
    let day: Weekday
    let servings: Double
    let plannedDate: Date

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var timerMinutes = 10
    @State private var timerEndsAt: Date?
    @State private var timerWarning: String?
    @State private var step = 0
    @State private var gathered: Set<String> = []
    @State private var didMarkCooked = false
    @State private var showGathered = false
    /// The running timer on the lock screen and in the Dynamic Island.
    @State private var liveActivity: Activity<CookingTimerAttributes>?

    private var scale: Double { servings / Double(max(meal.defaultServings, 1)) }
    private var hasSteps: Bool { !meal.instructions.isEmpty }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if hasSteps { progressBar }

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        ingredients
                        if scale != 1 { Text("Ingredient amounts are scaled. Quantities written inside the method remain as in the original recipe.").font(.caption).foregroundStyle(AppTheme.muted) }
                        if hasSteps { instructions } else { noSteps }
                        timerControls
                        Color.clear.frame(height: 20)
                    }
                    .padding(20)
                }

                footer
            }
            .appBackground()
            .navigationTitle(meal.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        // Nobody wants to wipe their hands to wake the screen mid-recipe.
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            let saved = store.householdTools.cooking[progressKey] ?? CookingProgress()
            step = min(saved.step, max(0, meal.instructions.count - 1)); gathered = saved.gathered; timerEndsAt = saved.timerEndsAt
            didMarkCooked = store.isCompleted(on: day)
            endLeftoverLiveActivities()
            syncLiveActivity()
        }
        .onChange(of: step) { _, _ in persist(); syncLiveActivity() }
        .onChange(of: gathered) { _, _ in persist() }
        .onChange(of: timerEndsAt) { _, _ in persist(); syncLiveActivity() }
        // Ends the lock-screen timer when it runs out while this screen is open.
        .task(id: timerEndsAt) {
            guard let end = timerEndsAt else { return }
            let wait = end.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled, timerEndsAt == end else { return }
            finishLiveActivity()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            endLiveActivity()
        }
    }

    // MARK: - Live Activity

    private var currentStepText: String? {
        guard hasSteps else { return nil }
        let index = min(max(step, 0), meal.instructions.count - 1)
        // Activity payloads are capped at 4 KB; a pasted recipe step can be very long.
        let text = String(meal.instructions[index].prefix(160))
        return L10n.string("Step %ld of %ld", index + 1, meal.instructions.count) + ": " + text
    }

    /// Starts, updates or ends the Live Activity to match the in-app timer.
    private func syncLiveActivity() {
        guard let end = timerEndsAt, end > .now else {
            endLiveActivity()
            return
        }
        let state = CookingTimerAttributes.ContentState(endsAt: end, stepText: currentStepText)
        let content = ActivityContent(state: state, staleDate: end)
        if let activity = liveActivity {
            Task { await activity.update(content) }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = CookingTimerAttributes(mealName: meal.name, emoji: meal.emoji)
        // Failing to start one only loses the lock-screen copy; the in-app timer and its
        // notification still run.
        liveActivity = try? Activity<CookingTimerAttributes>.request(
            attributes: attributes,
            content: content,
            pushType: nil
        )
    }

    private func endLiveActivity() {
        guard let activity = liveActivity else { return }
        liveActivity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    /// Leaves "Timer finished" on the lock screen briefly rather than vanishing.
    private func finishLiveActivity() {
        guard let activity = liveActivity, let end = timerEndsAt else { return }
        liveActivity = nil
        let state = CookingTimerAttributes.ContentState(endsAt: end, stepText: currentStepText)
        let content = ActivityContent(state: state, staleDate: end)
        Task { await activity.end(content, dismissalPolicy: .after(Date.now.addingTimeInterval(120))) }
    }

    /// Timers from an earlier run of the app -- quit or killed with a timer going -- that no
    /// screen is managing any more.
    private func endLeftoverLiveActivities() {
        guard liveActivity == nil else { return }
        let leftovers = Activity<CookingTimerAttributes>.activities
        guard !leftovers.isEmpty else { return }
        Task {
            for activity in leftovers {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private var progressKey: String { store.cookingKey(meal: meal, day: day, date: plannedDate) }
    private func persist() {
        store.householdTools.cooking[progressKey] = CookingProgress(step: step, gathered: gathered, timerEndsAt: timerEndsAt)
    }
    private var timerControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Cooking timer", systemImage: "timer").font(.headline)
            if let end = timerEndsAt {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    if end > timeline.date { Text(end, style: .timer).font(.largeTitle.monospacedDigit()) }
                    else { Label("Timer finished", systemImage: "bell.fill").font(.headline) }
                }
                Button("Cancel timer") {
                    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [progressKey])
                    timerEndsAt = nil
                    timerWarning = nil
                }
            } else {
                Stepper(L10n.string("%ld minutes", timerMinutes), value: $timerMinutes, in: 1...240)
                Button("Start timer") {
                    let end = Date.now.addingTimeInterval(Double(timerMinutes) * 60)
                    timerEndsAt = end
                    timerWarning = nil
                    Task {
                        let center = UNUserNotificationCenter.current()
                        let allowed = (try? await center.requestAuthorization(options: [.alert, .sound])) == true
                        guard timerEndsAt == end else { return }
                        guard allowed else {
                            timerWarning = L10n.string("Notifications are unavailable. Keep this screen open to see when the timer finishes.")
                            return
                        }
                        let content = UNMutableNotificationContent()
                        content.title = meal.name; content.body = L10n.string("Timer finished"); content.sound = .default
                        do {
                            try await center.add(UNNotificationRequest(identifier: progressKey, content: content,
                                trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSinceNow), repeats: false)))
                            if timerEndsAt != end { center.removePendingNotificationRequests(withIdentifiers: [progressKey]) }
                        } catch {
                            if timerEndsAt == end {
                                timerWarning = L10n.string("Notifications are unavailable. Keep this screen open to see when the timer finishes.")
                            }
                        }
                    }
                }.buttonStyle(.secondary)
            }
            if let timerWarning {
                Label(timerWarning, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(AppTheme.warning)
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).mealCard()
    }

    private var progressBar: some View {
        HStack(spacing: 5) {
            ForEach(meal.instructions.indices, id: \.self) { index in
                Capsule()
                    .fill(index <= step ? AppTheme.accent : AppTheme.ink.opacity(0.12))
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .accessibilityElement()
        .accessibilityLabel(L10n.string("Step %ld of %ld", step + 1, meal.instructions.count))
    }

    private var ingredients: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Ingredients").font(.system(.title3, design: .rounded, weight: .bold))
                Spacer()
                Text(L10n.portions(servings))
                    .font(.caption.weight(.semibold)).foregroundStyle(AppTheme.accent)
            }
            Toggle("Show gathered ingredients", isOn: $showGathered)
            ForEach(meal.ingredients.filter { showGathered || !gathered.contains($0.id) }) { ingredient in
                Button {
                    if gathered.contains(ingredient.id) { gathered.remove(ingredient.id) }
                    else { gathered.insert(ingredient.id) }
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: gathered.contains(ingredient.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(gathered.contains(ingredient.id) ? AppTheme.accent : AppTheme.muted.opacity(0.45))
                        Text(ingredient.name)
                            .foregroundStyle(AppTheme.ink)
                            .strikethrough(gathered.contains(ingredient.id))
                        Spacer()
                        // Scaled to the servings actually being cooked, not the recipe's default.
                        Text(ingredient.amountText(scale: scale))
                            .font(.subheadline).foregroundStyle(AppTheme.muted)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(gathered.contains(ingredient.id) ? [.isButton, .isSelected] : [.isButton])
            }
        }
        .padding(18)
        .mealCard()
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 14) {
            DisclosureGroup("All steps") {
                ForEach(Array(meal.instructions.enumerated()), id: \.offset) { index, text in
                    Button { step = index } label: { Text("\(index + 1). \(text)").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading) }
                }
            }
            Text(L10n.string("Step %ld of %ld", step + 1, meal.instructions.count))
                .font(.caption.bold()).foregroundStyle(AppTheme.accent)
            Text(meal.instructions[min(step, meal.instructions.count - 1)])
                .font(.system(.title3, design: .rounded))
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .mealCard()
    }

    private var noSteps: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No steps saved for this meal")
                .font(.headline).foregroundStyle(AppTheme.ink)
            Text("Add them when you next edit the recipe and they will show up here.")
                .font(.subheadline).foregroundStyle(AppTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .mealCard()
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if hasSteps, step > 0 {
                Button { withAnimation(reduceMotion ? nil : .snappy) { step -= 1 } } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.secondary)
            }

            if hasSteps, step < meal.instructions.count - 1 {
                Button { withAnimation(reduceMotion ? nil : .snappy) { step += 1 } } label: {
                    Label("Next step", systemImage: "chevron.right")
                }
                .buttonStyle(.primary)
            } else {
                Button {
                    Haptics.success()
                    store.handleReminderAction(.cooked(mealID: meal.id, day: day, date: plannedDate))
                    didMarkCooked = true
                    dismiss()
                } label: {
                    Label("We cooked this", systemImage: "checkmark.seal")
                }
                .buttonStyle(.primary)
                .disabled(didMarkCooked)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .padding(.top, 8)
        .background(AppTheme.background)
    }
}
