import SwiftUI

/// The week: tonight first, then the seven days, with one action that shuffles what is left.
///
/// It used to be about two and a half screens tall: a header with its own shuffle button, a
/// composition bar, an emoji strip, a share banner that appeared after every shuffle, a
/// "Tonight" card repeating one of the days, seven tall cards with three controls each (21 for
/// a week), a second shuffle button, and next week and history links below all of that. The
/// days are rows now -- swipe to lock or reroll, tap for everything else -- so the week fits
/// on one screen, and next week is a switch at the top rather than a link at the bottom.
struct WeekPlanView: View {
    @Environment(AppStore.self) private var store
    @EnvironmentObject private var router: AppRouter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var sheet: WeekSheet?
    @State private var cooking: CookingSession?
    /// Bumped per day to spin that day's reel.
    @State private var spins: [Weekday: Int] = [:]
    @State private var nextSpins: [Weekday: Int] = [:]
    @State private var lastCookedSession: CookingSession?

    /// Which meal is being cooked, and for which day, so the "we cooked this" at the end
    /// lands on the right entry.
    private struct CookingSession: Identifiable {
        let meal: Meal
        let day: Weekday
        let servings: Double
        let date: Date
        var id: String { "\(day.rawValue)-\(meal.id.uuidString)" }
    }

    /// Everything this screen can present, as one value: changing it swaps the sheet.
    private enum WeekSheet: Identifiable {
        case day(Weekday, nextWeek: Bool)
        case picker(Weekday, nextWeek: Bool)
        case context(Weekday, nextWeek: Bool)
        case recipe(Meal, servings: Double)
        case share
        case rules
        case photo(Meal)

        var id: String {
            switch self {
            case .day(let day, let next): "day-\(day.rawValue)-\(next)"
            case .picker(let day, let next): "picker-\(day.rawValue)-\(next)"
            case .context(let day, let next): "context-\(day.rawValue)-\(next)"
            case .recipe(let meal, _): "recipe-\(meal.id)"
            case .share: "share"
            case .rules: "rules"
            case .photo(let meal): "photo-\(meal.id)"
            }
        }
    }

    var body: some View {
        List {
            Section {
                header
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: AppTheme.Space.xs, bottom: AppTheme.Space.s, trailing: AppTheme.Space.xs))

            if router.showsNextWeek {
                nextWeekSections
            } else {
                thisWeekSections
            }

            // Room for the floating shuffle button.
            Section { Color.clear.frame(height: 56) }
                .listRowBackground(Color.clear)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle(L10n.string("Week %ld", weekNumber(of: displayedWeekStart)))
        .toolbar { toolbar }
        .overlay(alignment: .bottom) { shuffleButton }
        .animation(reduceMotion ? nil : .snappy, value: router.showsNextWeek)
        .sheet(item: $sheet) { presented in sheetContent(presented) }
        .fullScreenCover(item: $cooking, onDismiss: offerPhotoAfterCooking) { session in
            CookModeView(meal: session.meal, day: session.day, servings: session.servings, plannedDate: session.date)
                .environment(store)
        }
        .onChange(of: router.openDay) { _, day in openRequestedDay(day) }
        .onAppear { openRequestedDay(router.openDay) }
        .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
            // Only when the week is what is on screen: the other tabs stay alive behind it.
            guard router.tab == .week, sheet == nil, cooking == nil, !store.isGenerating else { return }
            shuffle()
        }
    }

    /// The widget's "Change" opens that day's sheet.
    private func openRequestedDay(_ day: Weekday?) {
        guard let day else { return }
        router.openDay = nil
        router.showsNextWeek = false
        sheet = .day(day, nextWeek: false)
    }

    /// The last session cooked, so the photo offer can follow the cook-mode cover.
    private func offerPhotoAfterCooking() {
        guard let session = lastCookedSession else { return }
        lastCookedSession = nil
        if store.isCompleted(on: session.day), store.meal(id: session.meal.id)?.photoName == nil {
            sheet = .photo(session.meal)
        }
    }

    // MARK: - Header

    private var displayedWeekStart: Date {
        router.showsNextWeek ? WeekAnchor.startOfNextWeek(after: store.plan.startDate) : store.plan.startDate
    }

    private func weekNumber(of start: Date) -> Int {
        Calendar.current.component(.weekOfYear, from: start)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppTheme.Space.s) {
            Text(WeekAnchor.label(forWeekStarting: displayedWeekStart))
                .font(.subheadline).foregroundStyle(AppTheme.muted)
            Picker("Week", selection: $router.showsNextWeek) {
                Text("This week").tag(false)
                Text(store.nextWeekPlan == nil ? L10n.string("Next week · empty") : L10n.string("Next week")).tag(true)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("week.weekPicker")
            if !router.showsNextWeek { ruleChips }
        }
    }

    /// The rules, shown where they do their work. Tapping one opens them all.
    private var ruleChips: some View {
        let active = store.rules.filter { $0.isActive(inWeek: store.plan.startDate) }
        let blocked = Set(store.blockingConflicts.compactMap(\.ruleID))
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Space.s) {
                ForEach(active) { rule in
                    Button { sheet = .rules } label: {
                        Label(rule.title, systemImage: blocked.contains(rule.id) ? "exclamationmark.triangle.fill" : "checkmark")
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                            .padding(.horizontal, AppTheme.Space.m)
                            .frame(minHeight: 34)
                            .background(blocked.contains(rule.id) ? AppTheme.warning.opacity(0.12) : AppTheme.accentSoft)
                            .foregroundStyle(blocked.contains(rule.id) ? AppTheme.warning : AppTheme.accent)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(L10n.string("Opens your rules"))
                }
                Button { sheet = .rules } label: {
                    Label(active.isEmpty ? L10n.string("Add a rule") : L10n.string("Rules"), systemImage: "plus")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, AppTheme.Space.m)
                        .frame(minHeight: 34)
                        .background(AppTheme.raised)
                        .foregroundStyle(AppTheme.ink)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, AppTheme.Space.xxs)
        }
        .scrollClipDisabled()
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if store.canUndo {
                Button {
                    Haptics.check()
                    withAnimation(reduceMotion ? nil : .snappy) { store.undoLastChange() }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .accessibilityLabel(store.undoLabel.map { L10n.string("Undo: %@", $0) } ?? L10n.string("Undo"))
            }
            if router.showsNextWeek {
                if let plan = store.nextWeekPlan {
                    ShareLink(item: PlanTextExporter.weeklyPlan(plan, meals: store.meals)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share next week")
                }
            } else {
                Button { sheet = .share } label: { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Share this week")
            }
        }
    }

    // MARK: - This week

    @ViewBuilder private var thisWeekSections: some View {
        if let today = todayItem {
            Section {
                TonightCard(
                    day: today.day,
                    item: today.item,
                    meal: today.meal,
                    badge: badge(for: today.day, item: today.item, meal: today.meal, plan: store.plan),
                    cook: store.cook(for: today.day)?.displayName,
                    isCompleted: store.isCompleted(on: today.day),
                    openRecipe: { if let meal = today.meal { sheet = .recipe(meal, servings: today.item.effectiveServings) } },
                    startCooking: {
                        if let meal = today.meal {
                            let session = CookingSession(meal: meal, day: today.day, servings: today.item.effectiveServings,
                                                         date: store.plan.date(for: today.day))
                            lastCookedSession = session
                            cooking = session
                        }
                    },
                    change: { sheet = .day(today.day, nextWeek: false) }
                )
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }

        if !store.blockingConflicts.isEmpty {
            Section {
                PlanConflictView(conflicts: store.blockingConflicts)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }

        Section {
            ForEach(Weekday.ordered()) { day in
                dayRow(day, in: store.plan, nextWeek: false)
            }
        } footer: {
            VStack(alignment: .leading, spacing: AppTheme.Space.s) {
                WeekCompositionView(plan: store.plan, meals: store.meals)
                ForEach(store.planNotes) { note in
                    Text(note.message).font(.caption).foregroundStyle(AppTheme.muted)
                }
            }
            .padding(.top, AppTheme.Space.s)
        }
    }

    private var todayItem: (day: Weekday, item: PlannedMeal, meal: Meal?)? {
        guard let day = Weekday.ordered().first(where: { Calendar.current.isDateInToday(store.plan.date(for: $0)) }),
              let item = store.plan[day], item.kind != .away else { return nil }
        return (day: day, item: item, meal: item.freezerBatch?.recipe ?? item.mealID.flatMap { store.meal(id: $0) })
    }

    // MARK: - Next week

    @ViewBuilder private var nextWeekSections: some View {
        if let plan = store.nextWeekPlan {
            if !store.nextWeekConflicts.isEmpty {
                Section {
                    PlanConflictView(conflicts: store.nextWeekConflicts, nextWeek: true)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            Section {
                ForEach(Weekday.ordered()) { day in
                    dayRow(day, in: plan, nextWeek: true)
                }
            } footer: {
                Text("This plan takes over automatically when the week turns. Your current week is untouched.")
                    .font(.caption)
            }
            Section {
                Button(role: .destructive) { store.discardNextWeek() } label: {
                    Text("Discard next week").frame(maxWidth: .infinity)
                }
            }
        } else {
            Section {
                VStack(spacing: AppTheme.Space.m) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.largeTitle).foregroundStyle(AppTheme.accent)
                    Text("Nothing planned for next week yet.")
                        .font(.headline).foregroundStyle(AppTheme.ink)
                    Text("Shuffle it now and it will be waiting when the week turns.")
                        .font(.subheadline).foregroundStyle(AppTheme.muted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.Space.xl)
            }
        }
    }

    // MARK: - Days

    private func dayRow(_ day: Weekday, in plan: WeeklyPlan, nextWeek: Bool) -> some View {
        let item = plan[day]
        let meal = item.flatMap { $0.freezerBatch?.recipe ?? $0.mealID.flatMap { store.meal(id: $0) } }
        let date = plan.date(for: day)
        let isPast = !nextWeek && date < Calendar.current.startOfDay(for: .now)
        let isCompleted = !nextWeek && store.isCompleted(on: day)
        let spin = nextWeek ? nextSpins[day, default: 0] : spins[day, default: 0]
        let position = Double(Weekday.position(of: day))
        let cook = store.cook(for: day, nextWeek: nextWeek)?.displayName
        let isBusy = store.busyDays(inWeekStarting: plan.startDate).contains(day)
        return Button {
            sheet = .day(day, nextWeek: nextWeek)
        } label: {
            DayRow(
                day: day,
                date: date,
                item: item,
                meal: meal,
                badge: item.flatMap { badge(for: day, item: $0, meal: meal, plan: plan) },
                isToday: !nextWeek && Calendar.current.isDateInToday(date),
                isDimmed: isPast || isCompleted,
                isCompleted: isCompleted,
                cook: cook,
                isBusy: isBusy,
                spin: spin,
                delay: position * 0.09
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("week.day.\(day.rawValue)")
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if let item {
                Button {
                    Haptics.check()
                    if nextWeek { store.toggleNextWeekLock(day: day) } else { store.toggleLock(day: day) }
                } label: {
                    Label(item.isLocked ? L10n.string("Unlock") : L10n.string("Lock"),
                          systemImage: item.isLocked ? "lock.open" : "lock.fill")
                }
                .tint(AppTheme.accent)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !isPast && !isCompleted {
                Button {
                    reroll(day, nextWeek: nextWeek)
                } label: {
                    Label("New dinner", systemImage: "shuffle")
                }
                .tint(AppTheme.accent)
                Button {
                    sheet = .picker(day, nextWeek: nextWeek)
                } label: {
                    Label("Choose", systemImage: "hand.tap")
                }
                .tint(AppTheme.muted)
            }
        }
    }

    /// The rule that put this dinner here, in the household's own words.
    private func badge(for day: Weekday, item: PlannedMeal, meal: Meal?, plan: WeeklyPlan) -> String? {
        let active = store.rules.filter { $0.isActive(inWeek: plan.startDate) }
        return WeekPosterContent.badge(for: day, item: item, meal: meal, rules: active, context: store.matchContext)
    }

    private func reroll(_ day: Weekday, nextWeek: Bool, intent: MealSwapIntent = .different) {
        Haptics.shuffle()
        if nextWeek {
            nextSpins[day, default: 0] += 1
            withAnimation(reduceMotion ? nil : .snappy) { store.shuffleNextWeek(day: day, intent: intent) }
        } else {
            spins[day, default: 0] += 1
            withAnimation(reduceMotion ? nil : .snappy) { store.shuffle(day: day, intent: intent) }
        }
    }

    // MARK: - Shuffle

    /// The one prominent action. It counts what it will change, so a locked or past day
    /// explains itself by not being counted.
    @ViewBuilder private var shuffleButton: some View {
        let nextWeek = router.showsNextWeek
        let count = nextWeek
            ? (store.nextWeekPlan?.meals.filter { !$0.isLocked }.count ?? 7)
            : store.remainingDinnerCount
        if count > 0 {
            Button(action: shuffle) {
                Label(
                    nextWeek && store.nextWeekPlan == nil
                        ? L10n.string("Shuffle next week")
                        : (count == 1 ? L10n.string("Shuffle 1 day") : L10n.string("Shuffle %ld days", count)),
                    systemImage: "shuffle"
                )
                .font(.headline)
                .padding(.horizontal, AppTheme.Space.xl)
                .frame(minHeight: 50)
                .background(AppTheme.accent)
                .foregroundStyle(AppTheme.onAccent)
                .clipShape(Capsule())
                .shadow(color: AppTheme.accent.opacity(0.3), radius: 12, y: 6)
            }
            .buttonStyle(.plain)
            .disabled(store.isGenerating)
            .accessibilityIdentifier("week.shuffle")
            .padding(.bottom, AppTheme.Space.m)
            .accessibilityHint(L10n.string("Locked and finished days stay as they are"))
        }
    }

    /// Every day that can still change spins, top to bottom, then the week is drawn.
    ///
    /// The reels start at the tap rather than when the plan arrives, so the response is
    /// immediate; the draw takes a fraction of the time the reels take to settle.
    private func shuffle() {
        Haptics.shuffle()
        playShuffleRhythm()
        if router.showsNextWeek {
            for day in Weekday.ordered() where store.nextWeekPlan?[day]?.isLocked != true {
                nextSpins[day, default: 0] += 1
            }
            Task { await store.generateInBackground(nextWeek: true) }
        } else {
            let today = Calendar.current.startOfDay(for: .now)
            for day in Weekday.ordered() {
                let isFixed = store.plan[day]?.isLocked == true || store.isCompleted(on: day)
                    || store.plan.date(for: day) < today
                if !isFixed { spins[day, default: 0] += 1 }
            }
            Task { await store.generateInBackground() }
        }
    }

    /// Light ticks while the reels roll, then a success when the last day has landed --
    /// roughly the length of the longest reel. Every landing in between taps on its own.
    private func playShuffleRhythm() {
        guard !reduceMotion else { return }
        Task { @MainActor in
            for _ in 0..<9 {
                Haptics.tick()
                try? await Task.sleep(for: .milliseconds(115))
            }
            try? await Task.sleep(for: .milliseconds(120))
            Haptics.success()
        }
    }

    // MARK: - Sheets

    @ViewBuilder private func sheetContent(_ presented: WeekSheet) -> some View {
        switch presented {
        case .day(let day, let nextWeek):
            DaySheet(day: day, nextWeek: nextWeek) { action in handle(action, day: day, nextWeek: nextWeek) }
                .environment(store)
                .presentationDetents([.medium, .large])
        case .picker(let day, let nextWeek):
            MealPickerView(day: day, nextWeek: nextWeek).environment(store)
        case .context(let day, let nextWeek):
            DayContextEditor(
                day: day,
                initialContext: store.context(for: day, nextWeek: nextWeek),
                governingRule: store.dinnerModeRule(for: day, nextWeek: nextWeek)?.summary(meals: store.meals, context: store.matchContext)
            ) { context in
                if nextWeek { store.updateNextWeekContext(context, for: day) } else { store.updateContext(context, for: day) }
            }
            .environment(store)
            .presentationDetents([.medium, .large])
        case .recipe(let meal, let servings):
            MealDetailView(meal: meal, initialServings: servings).presentationDetents([.medium, .large])
        case .share:
            WeekShareView().environment(store)
        case .photo(let meal):
            DinnerPhotoSheet(meal: meal).environment(store)
                .presentationDetents([.medium])
        case .rules:
            NavigationStack {
                RulesView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { sheet = nil } }
                    }
            }
            .environment(store)
        }
    }

    private func handle(_ action: DaySheet.Action, day: Weekday, nextWeek: Bool) {
        let plan: WeeklyPlan? = nextWeek ? store.nextWeekPlan : store.plan
        let item = plan?[day]
        let meal = item.flatMap { $0.freezerBatch?.recipe ?? $0.mealID.flatMap { store.meal(id: $0) } }
        switch action {
        case .openRecipe:
            if let meal { sheet = .recipe(meal, servings: item?.effectiveServings ?? Double(meal.defaultServings)) }
        case .cook:
            sheet = nil
            if let meal, let item {
                let session = CookingSession(meal: meal, day: day, servings: item.effectiveServings, date: store.plan.date(for: day))
                lastCookedSession = session
                cooking = session
            }
        case .choose:
            sheet = .picker(day, nextWeek: nextWeek)
        case .replace(let intent):
            sheet = nil
            reroll(day, nextWeek: nextWeek, intent: intent)
        case .swap(let other):
            sheet = nil
            withAnimation(reduceMotion ? nil : .snappy) {
                if nextWeek { store.swapNextWeek(between: day, and: other) } else { store.swapMeals(between: day, and: other) }
            }
        case .planDay:
            sheet = .context(day, nextWeek: nextWeek)
        case .toggleLock:
            if nextWeek { store.toggleNextWeekLock(day: day) } else { store.toggleLock(day: day) }
        case .toggleFavorite:
            if let meal { store.toggleFavorite(meal) }
        case .markCooked:
            if let meal {
                Haptics.success()
                store.markCooked(meal, on: day)
                // The cheapest moment to get a real picture of the family's own dinner.
                if store.meal(id: meal.id)?.photoName == nil { sheet = .photo(meal) }
            }
        case .clearCooked:
            store.clearCompletion(on: day)
        case .notToday:
            sheet = nil
            if let meal { spins[day, default: 0] += 1; store.markSkipped(meal, on: day) }
        case .notForAWhile:
            sheet = nil
            if let meal { spins[day, default: 0] += 1; store.snooze(meal, on: day) }
        }
    }
}

// MARK: - Tonight

/// Tonight's dinner, with the two things a household does with it.
private struct TonightCard: View {
    let day: Weekday
    let item: PlannedMeal
    let meal: Meal?
    let badge: String?
    let cook: String?
    let isCompleted: Bool
    let openRecipe: () -> Void
    let startCooking: () -> Void
    let change: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: item.kind == .meal ? openRecipe : change) {
                MealArtwork(meal: item.kind == .meal ? meal : nil, fallbackEmoji: DayRow.fallbackSymbol(for: item, meal: meal))
                    .frame(height: 132)
                    .overlay(alignment: .topLeading) {
                        Text("Tonight")
                            .eyebrowStyle()
                            .padding(.horizontal, AppTheme.Space.s).padding(.vertical, AppTheme.Space.xs)
                            .background(AppTheme.surface)
                            .clipShape(Capsule())
                            .padding(AppTheme.Space.m)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("Open the recipe"))

            VStack(alignment: .leading, spacing: AppTheme.Space.m) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: AppTheme.Space.xs) {
                        Text(DayRow.title(for: item, meal: meal))
                            .font(AppTheme.Typography.title).foregroundStyle(AppTheme.ink)
                        Text([DayRow.metadata(for: item, meal: meal), cook.map { L10n.string("%@ cooks", $0) }]
                                .compactMap { $0 }.joined(separator: " · "))
                            .font(.subheadline).foregroundStyle(AppTheme.muted)
                    }
                    Spacer(minLength: AppTheme.Space.s)
                    if let badge { RuleBadge(text: badge) }
                }
                HStack(spacing: AppTheme.Space.s) {
                    if isCompleted {
                        Label("Cooked", systemImage: "checkmark.seal.fill")
                            .font(.headline).foregroundStyle(AppTheme.accent)
                            .frame(maxWidth: .infinity, minHeight: AppTheme.tapTarget, alignment: .leading)
                    } else if item.kind == .meal, meal != nil {
                        Button(action: startCooking) { Label("Start cooking", systemImage: "flame") }
                            .buttonStyle(.primary)
                    }
                    Button(action: change) { Text("Change") }
                        .buttonStyle(.secondary)
                }
            }
            .padding(AppTheme.Space.l)
        }
        .mealCard()
    }
}

// MARK: - A day

/// One day as a row: when, what, why, and whether it is locked.
struct DayRow: View {
    let day: Weekday
    let date: Date
    let item: PlannedMeal?
    let meal: Meal?
    let badge: String?
    let isToday: Bool
    let isDimmed: Bool
    let isCompleted: Bool
    var cook: String? = nil
    var isBusy = false
    let spin: Int
    let delay: Double
    @ScaledMetric(relativeTo: .title3) private var dateColumn: CGFloat = 38

    var body: some View {
        HStack(spacing: AppTheme.Space.m) {
            VStack(spacing: 0) {
                Text(Weekday.shortSymbol(for: day).uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(isToday ? AppTheme.accent : AppTheme.muted)
                Text(date.formatted(.dateTime.day()))
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(isToday ? AppTheme.accent : AppTheme.ink)
            }
            .frame(minWidth: dateColumn)

            ReelThumbnail(
                meal: item?.kind == .meal ? meal : nil,
                fallbackEmoji: item.map { Self.fallbackSymbol(for: $0, meal: meal) } ?? "·",
                spin: spin,
                delay: delay
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(item.map { Self.title(for: $0, meal: meal) } ?? L10n.string("Not planned"))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(2)
                    .id(meal?.id.uuidString ?? item.map { "\($0.kind)" } ?? "none")
                    .transition(.push(from: .top))
                HStack(spacing: AppTheme.Space.xs) {
                    if let badge {
                        RuleBadge(text: badge)
                            .id(badge + (meal?.id.uuidString ?? ""))
                            .transition(.scale(scale: 1.6).combined(with: .opacity))
                    } else if let item {
                        Text([Self.metadata(for: item, meal: meal), cook.map { L10n.string("%@ cooks", $0) }]
                                .compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(AppTheme.muted)
                            .lineLimit(1)
                    }
                    if isBusy {
                        Image(systemName: "calendar.badge.clock")
                            .font(.caption2).foregroundStyle(AppTheme.muted)
                            .accessibilityLabel(L10n.string("Busy evening in your calendar"))
                    }
                }
            }
            Spacer(minLength: AppTheme.Space.xs)
            if isCompleted {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(AppTheme.accent)
                    .accessibilityLabel("Cooked")
            } else if item?.isLocked == true {
                Image(systemName: "lock.fill").font(.footnote).foregroundStyle(AppTheme.accent)
                    .accessibilityLabel("Locked")
            }
        }
        .padding(.vertical, AppTheme.Space.xxs)
        .opacity(isDimmed ? 0.55 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(L10n.string("Opens this day. Swipe to lock or replace."))
    }

    static func fallbackSymbol(for item: PlannedMeal, meal: Meal?) -> String {
        if let meal, item.kind == .meal { return meal.emoji }
        return switch item.kind {
        case .away: "🏃"
        case .takeaway: "🥡"
        case .leftovers: "♻️"
        case .meal: "🍽️"
        }
    }

    static func title(for item: PlannedMeal, meal: Meal?) -> String {
        if let batch = item.freezerBatch { return L10n.string("From the freezer: %@", batch.recipe.name) }
        switch item.kind {
        case .leftovers: return meal.map { L10n.string("Leftovers: %@", $0.name) } ?? L10n.string("Leftovers")
        case .away: return L10n.string("No dinner at home")
        case .takeaway: return L10n.string("Takeaway")
        case .meal: return meal?.name ?? L10n.string("Not planned")
        }
    }

    static func metadata(for item: PlannedMeal, meal: Meal?) -> String {
        if let meal, item.kind == .meal {
            let time = meal.prepMinutes > 0 ? L10n.string("%ld min", meal.prepMinutes) : L10n.string("Time not specified")
            return [time, L10n.portions(item.effectiveServings)].joined(separator: " · ")
        }
        return item.kind == .away ? L10n.string("Day off") : L10n.string("%ld people", item.servings)
    }
}

/// "✓ Fredagstaco": the household's own rule, next to the day it decided.
struct RuleBadge: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "checkmark")
            .font(.caption2.weight(.bold))
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(AppTheme.accentSoft)
            .foregroundStyle(AppTheme.accent)
            .clipShape(Capsule())
    }
}

/// A day's picture that spins like a slot-machine reel when the day is reshuffled.
///
/// The reels used to spin in a small strip of emoji above the week while the cards below
/// simply changed. They spin in the rows now, top to bottom, each landing with a tap under the
/// thumb -- the moment the week is drawn happens where people are looking. With Reduce Motion
/// on, the picture simply changes.
private struct ReelThumbnail: View {
    let meal: Meal?
    let fallbackEmoji: String
    let spin: Int
    let delay: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var face: String?
    @State private var rolling: Task<Void, Never>?
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = AppTheme.rowThumbnail

    var body: some View {
        ZStack {
            MealThumbnail(meal: meal, fallbackEmoji: fallbackEmoji, size: size)
                .opacity(face == nil ? 1 : 0)
                .scaleEffect(face == nil ? 1 : 0.85)
            if let face {
                Text(face)
                    .font(.title2)
                    .id(face)
                    .transition(.asymmetric(insertion: .move(edge: .top), removal: .move(edge: .bottom)))
            }
        }
        .frame(width: size, height: size)
        .background(face == nil ? Color.clear : AppTheme.artworkPaper)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
        .onChange(of: spin) { _, _ in roll() }
        .onDisappear { rolling?.cancel() }
        .accessibilityHidden(true)
    }

    private func roll() {
        rolling?.cancel()
        guard !reduceMotion else { return }
        rolling = Task { @MainActor in
            // Later days roll longer, so the week lands from the top down.
            let steps = 7 + Int((delay / 0.09).rounded())
            for step in 0..<steps {
                var next = SlotReel.faces.randomElement() ?? fallbackEmoji
                if next == face {
                    next = SlotReel.faces[((SlotReel.faces.firstIndex(of: next) ?? 0) + 1) % SlotReel.faces.count]
                }
                withAnimation(.linear(duration: 0.06)) { face = next }
                // Slows towards the end, like a reel settling.
                try? await Task.sleep(for: .milliseconds(45 + step * 6))
                if Task.isCancelled { return }
            }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.62)) { face = nil }
            Haptics.land()
        }
    }
}

// MARK: - Day sheet

/// Everything that can be done with one day, in one place.
///
/// These were a capsule, a lock and a menu on every card. A day's actions are rarer than its
/// glance, so they wait behind a tap.
struct DaySheet: View {
    enum Action {
        case openRecipe, cook, choose, planDay, toggleLock, toggleFavorite
        case markCooked, clearCooked, notToday, notForAWhile
        case replace(MealSwapIntent)
        case swap(Weekday)
    }

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let day: Weekday
    let nextWeek: Bool
    let perform: (Action) -> Void

    private var plan: WeeklyPlan? { nextWeek ? store.nextWeekPlan : store.plan }
    private var item: PlannedMeal? { plan?[day] }
    private var meal: Meal? { item.flatMap { $0.freezerBatch?.recipe ?? $0.mealID.flatMap { store.meal(id: $0) } } }
    private var date: Date { plan?.date(for: day) ?? day.date(inWeekStarting: store.plan.startDate) }
    private var isToday: Bool { !nextWeek && Calendar.current.isDateInToday(date) }
    private var isPast: Bool { !nextWeek && date < Calendar.current.startOfDay(for: .now) }
    private var isCompleted: Bool { !nextWeek && store.isCompleted(on: day) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: AppTheme.Space.m) {
                        MealThumbnail(meal: item?.kind == .meal ? meal : nil,
                                      fallbackEmoji: item.map { DayRow.fallbackSymbol(for: $0, meal: meal) } ?? "·")
                        VStack(alignment: .leading, spacing: AppTheme.Space.xs) {
                            Text("\(day.name) · \(date.formatted(.dateTime.day().month()))")
                                .eyebrowStyle()
                            Text(item.map { DayRow.title(for: $0, meal: meal) } ?? L10n.string("Not planned"))
                                .font(.headline).foregroundStyle(AppTheme.ink)
                            if let item {
                                Text(DayRow.metadata(for: item, meal: meal)).font(.caption).foregroundStyle(AppTheme.muted)
                            }
                        }
                    }
                    if !nextWeek, let explanation = store.explanation(for: day) {
                        Label(explanation, systemImage: "sparkles")
                            .font(.footnote).foregroundStyle(AppTheme.muted)
                    }
                    if meal != nil {
                        Button { perform(.openRecipe) } label: { Label("Open the recipe", systemImage: "book") }
                    }
                    if isToday, item?.kind == .meal, meal != nil, !isCompleted {
                        Button { perform(.cook) } label: { Label("Start cooking", systemImage: "flame") }
                    }
                }

                if !isPast && !isCompleted {
                    Section("Change the dinner") {
                        Button { perform(.choose) } label: { Label("Choose a dinner", systemImage: "hand.tap") }
                        ForEach(MealSwapIntent.allCases) { intent in
                            Button { perform(.replace(intent)) } label: { Label(intent.name, systemImage: intent.symbol) }
                        }
                        Menu {
                            ForEach(Weekday.ordered().filter { $0 != day }) { other in
                                Button(other.name) { perform(.swap(other)) }
                            }
                        } label: {
                            Label("Swap with another day", systemImage: "arrow.left.arrow.right")
                        }
                    }
                }

                if item?.kind == .meal, store.household.members.count > 1 || store.cook(for: day, nextWeek: nextWeek) != nil {
                    Section {
                        Picker(selection: Binding(
                            get: { store.cook(for: day, nextWeek: nextWeek)?.id },
                            set: { store.setCook($0, for: day, nextWeek: nextWeek) }
                        )) {
                            Text("Not decided").tag(nil as UUID?)
                            ForEach(store.household.members) { member in
                                Text(member.displayName).tag(member.id as UUID?)
                            }
                        } label: {
                            Label("Who cooks", systemImage: "frying.pan")
                        }
                    }
                }

                Section {
                    Button { perform(.planDay) } label: { Label("Plan this day", systemImage: "person.2") }
                    if let item {
                        Button { perform(.toggleLock) } label: {
                            Label(item.isLocked ? L10n.string("Unlock this day") : L10n.string("Lock this day"),
                                  systemImage: item.isLocked ? "lock.open" : "lock")
                        }
                    }
                    if let meal {
                        let favorite = store.favoriteMealIDs.contains(meal.id)
                        Button { perform(.toggleFavorite) } label: {
                            Label(favorite ? L10n.string("Remove family favorite") : L10n.string("Family favorite"),
                                  systemImage: favorite ? "heart.slash" : "heart")
                        }
                    }
                } footer: {
                    Text("Plan this day covers who is eating, portions, a time limit, takeaway, leftovers or nobody home.")
                }

                if !nextWeek, let item, item.kind == .meal, meal != nil, !isUpcoming {
                    Section {
                        if isCompleted {
                            Button { perform(.clearCooked) } label: { Label("Undo cooking completion", systemImage: "arrow.uturn.backward") }
                        } else {
                            Button { perform(.markCooked) } label: { Label("We cooked this", systemImage: "checkmark.seal") }
                            if isToday {
                                Button { perform(.notToday) } label: { Label("Not for today", systemImage: "forward") }
                            }
                            Button(role: .destructive) { perform(.notForAWhile) } label: {
                                Label("Not again for a while", systemImage: "calendar.badge.minus")
                            }
                        }
                    }
                }
            }
            .navigationTitle(day.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("daySheet.done")
                }
            }
        }
    }

    /// A day still ahead can be marked cooked only once it has come.
    private var isUpcoming: Bool { date > Calendar.current.startOfDay(for: .now).addingTimeInterval(86_399) }
}

struct DayContextEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let day: Weekday
    /// Set when a rule already decides this day's plan, so the picker can say why it will
    /// not stick rather than silently losing the choice on the next shuffle.
    let governingRule: String?
    let save: (DayPlanContext) -> Void
    @State private var context: DayPlanContext
    @State private var hasTimeLimit: Bool

    init(
        day: Weekday,
        initialContext: DayPlanContext,
        governingRule: String?,
        save: @escaping (DayPlanContext) -> Void
    ) {
        self.day = day; self.governingRule = governingRule; self.save = save
        _context = State(initialValue: initialContext)
        _hasTimeLimit = State(initialValue: initialContext.maximumPrepMinutes != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Plan", selection: $context.mode) {
                        ForEach(DayDinnerMode.allCases) { Label($0.name, systemImage: symbol($0)).tag($0) }
                    }
                    .disabled(governingRule != nil && context.overridesDinnerMode != true)
                    if governingRule != nil {
                        Toggle("Make an exception this week", isOn: Binding(
                            get: { context.overridesDinnerMode == true }, set: { context.overridesDinnerMode = $0 }
                        ))
                    }
                    if context.mode != .away {
                    Stepper(L10n.string("%ld people eating", context.diners), value: $context.diners, in: 1...20)
                    Picker("Portion size", selection: Binding(get: { context.portionScale ?? 1 }, set: { context.portionScale = $0 })) {
                        Text("Half portions").tag(0.5)
                        Text("Three-quarter portions").tag(0.75)
                        Text("Standard portions").tag(1.0)
                        Text("Large portions").tag(1.5)
                    }
                    if context.mode == .cook {
                        LabeledContent("Total to cook", value: L10n.portions(Double(context.cookedServings) * (context.portionScale ?? 1)))
                    } else { LabeledContent("Portions needed", value: L10n.portions(context.effectiveDiners)) }
                    }
                } header: {
                    Text(L10n.string("What's happening on %@?", day.name.lowercased()))
                } footer: {
                    if let governingRule {
                        Text(L10n.string("The rule “%@” already decides this. Change it under Rules.", governingRule))
                    }
                }
                if context.mode != .away {
                Section("Who is eating?") {
                    ForEach(store.household.members) { member in
                        Toggle(member.displayName, isOn: Binding(
                            get: { context.attendingMemberIDs?.contains(member.id) ?? true },
                            set: { attending in
                                var ids = context.attendingMemberIDs ?? Set(store.household.members.map(\.id))
                                if attending { ids.insert(member.id) } else { ids.remove(member.id) }
                                context.attendingMemberIDs = ids
                                context.diners = max(1, ids.count)
                            }
                        ))
                    }
                    Text("Attendance updates the number eating and personal dislikes. Adjust it for guests and choose a portion size for appetites.").font(.caption)
                }
                }
                if context.mode == .cook {
                    Section("Cooking") {
                        Stepper(
                            context.extraServings == 0
                                ? L10n.string("No extra servings")
                                : L10n.string("Make %ld extra", context.extraServings),
                            value: $context.extraServings,
                            in: 0...12
                        )
                        Toggle("Time limit", isOn: $hasTimeLimit)
                        if hasTimeLimit {
                            Stepper(L10n.string("Maximum %ld minutes", context.maximumPrepMinutes ?? 30), value: Binding(
                                get: { context.maximumPrepMinutes ?? 30 }, set: { context.maximumPrepMinutes = $0 }
                            ), in: 10...120, step: 5)
                        }
                    }
                }
                if context.mode == .leftovers {
                    Section("Leftovers from") {
                        Picker("Freezer batch", selection: $context.freezerBatchID) {
                            Text("Use an earlier dinner").tag(nil as UUID?)
                            ForEach(store.householdTools.freezer) { batch in Text(batch.recipe.name + " · " + L10n.portions(batch.portions)).tag(batch.id as UUID?) }
                        }
                        if context.freezerBatchID == nil {
                        Picker("Earlier day", selection: $context.leftoverSourceDay) {
                            Text("Choose automatically").tag(nil as Weekday?)
                            ForEach(daysBefore) { Text($0.name).tag($0 as Weekday?) }
                        }
                        }
                    }
                }
            }
            .navigationTitle(day.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if context.mode != .leftovers { context.freezerBatchID = nil }
                        context.maximumPrepMinutes = hasTimeLimit ? (context.maximumPrepMinutes ?? 30) : nil
                        save(context); dismiss()
                    }.fontWeight(.semibold)
                }
            }
        }
    }

    private var daysBefore: [Weekday] {
        let ordered = Weekday.ordered()
        guard let index = ordered.firstIndex(of: day) else { return [] }
        return Array(ordered.prefix(index))
    }
    private func symbol(_ mode: DayDinnerMode) -> String {
        switch mode { case .cook: "fork.knife"; case .leftovers: "arrow.3.trianglepath"; case .away: "figure.run"; case .takeaway: "takeoutbag.and.cup.and.straw" }
    }
}

struct MealDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let meal: Meal
    @State private var servings: Double
    @ScaledMetric(relativeTo: .caption) private var stepCircle: CGFloat = 26

    init(meal: Meal, initialServings: Double? = nil) {
        self.meal = meal
        _servings = State(initialValue: initialServings ?? Double(meal.defaultServings))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero
                    VStack(alignment: .leading, spacing: 7) {
                        Text(meal.name).font(.system(.title, design: .rounded, weight: .bold))
                        Text(meal.subtitle).foregroundStyle(AppTheme.muted)
                        Label(
                            L10n.string("%ld minutes · %ld servings", meal.prepMinutes, meal.defaultServings),
                            systemImage: "clock"
                        )
                        .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.accent)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Ingredients").font(.title3.bold())
                        Stepper(L10n.portions(servings), value: $servings, in: 0.5...40, step: 0.5)
                        ForEach(meal.ingredients) { ingredient in
                            HStack {
                                Text(ingredient.name)
                                Spacer()
                                Text(ingredient.amountText(scale: Double(servings) / Double(max(meal.defaultServings, 1))))
                                    .foregroundStyle(AppTheme.muted)
                            }
                            Divider()
                        }
                    }
                    if !meal.instructions.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Instructions").font(.title3.bold())
                            ForEach(Array(meal.instructions.enumerated()), id: \.offset) { index, instruction in
                                HStack(alignment: .top, spacing: 10) {
                                    Text("\(index + 1)").font(.caption.bold())
                                        .frame(width: stepCircle, height: stepCircle)
                                        .background(AppTheme.accentSoft).clipShape(Circle())
                                    Text(instruction)
                                }
                            }
                        }
                    }
                }.padding(20)
            }
            .appBackground()
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }

    /// Uses the imported photograph when the recipe came with one.
    private var hero: some View {
        MealArtwork(meal: meal)
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.heroRadius, style: .continuous))
            .accessibilityHidden(true)
    }
}
