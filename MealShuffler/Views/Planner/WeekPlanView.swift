import SwiftUI

struct WeekPlanView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedMeal: Meal?
    @State private var selectedServings: Double = 4
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editingDay: Weekday?
    @State private var pickingDay: Weekday?
    @State private var cooking: CookingSession?

    /// Which meal is being cooked, and for which day, so the "we cooked this" at the end
    /// lands on the right entry.
    private struct CookingSession: Identifiable {
        let meal: Meal
        let day: Weekday
        let servings: Double
        let date: Date
        var id: String { "\(day.rawValue)-\(meal.id.uuidString)" }
    }

    var body: some View {
        ScrollViewReader { scroll in
        ScrollView {
            LazyVStack(spacing: 14) {
                plannerHeader
                weekStrip(scroll: scroll)
                todayCard
                if !store.blockingConflicts.isEmpty { PlanConflictView(conflicts: store.blockingConflicts) }
                if !store.planNotes.isEmpty { notesRow }

                ForEach(Weekday.ordered()) { day in
                    if let item = store.plan[day] {
                        DayPlanCard(
                            day: day,
                            date: store.plan.date(for: day),
                            item: item,
                            meal: item.freezerBatch?.recipe ?? item.mealID.flatMap { store.meal(id: $0) },
                            explanation: store.explanation(for: day),
                            isCompleted: store.isCompleted(on: day),
                            clearCompletion: { store.clearCompletion(on: day) },
                            isFavorite: item.mealID.map { store.favoriteMealIDs.contains($0) } ?? false,
                            open: { if let id = item.mealID { selectedServings = item.effectiveServings; selectedMeal = store.meal(id: id) } },
                            chooseMeal: { pickingDay = day },
                            editContext: { editingDay = day },
                            toggleLock: { store.toggleLock(day: day) },
                            shuffle: { intent in
                                Haptics.shuffle()
                                withAnimation(reduceMotion ? nil : .snappy) { store.shuffle(day: day, intent: intent) }
                            },
                            snooze: {
                                if let id = item.mealID, let meal = store.meal(id: id) { store.snooze(meal, on: day) }
                            },
                            toggleFavorite: {
                                if let id = item.mealID, let meal = store.meal(id: id) { store.toggleFavorite(meal) }
                            },
                            markCooked: {
                                if let id = item.mealID, let meal = store.meal(id: id) { store.markCooked(meal, on: day) }
                            },
                            markSkipped: {
                                if let id = item.mealID, let meal = store.meal(id: id) { store.markSkipped(meal, on: day) }
                            },
                            cook: {
                                if let id = item.mealID, let meal = store.meal(id: id) {
                                    cooking = CookingSession(meal: meal, day: day, servings: item.effectiveServings, date: store.plan.date(for: day))
                                }
                            },
                            swapWith: { otherDay in store.swapMeals(between: day, and: otherDay) }
                        )
                        .id(day)
                        // Each card arrives on its own rather than the list redrawing as a
                        // block, so the signature interaction reads as a change.
                        .transition(.asymmetric(
                            insertion: reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity),
                            removal: .opacity
                        ))
                    } else {
                        VStack(alignment: .leading) {
                            Text(day.name).font(.headline)
                            Text("Not planned")
                            Button("Choose a meal") { pickingDay = day }
                            Button("Plan this day") { editingDay = day }
                        }.padding().frame(maxWidth: .infinity, alignment: .leading).mealCard().id(day)
                    }
                }

                Button {
                    Haptics.shuffle()
                    Task { await store.generateInBackground() }
                } label: {
                    Label(L10n.string("Shuffle %ld remaining dinners", store.remainingDinnerCount), systemImage: "shuffle")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: AppTheme.controlRadius))
                .padding(.top, 4)

                nextWeekCard
                historyLink
                Color.clear.frame(height: 24)
            }
            .padding(.horizontal, 16)
        }
        }
        .appBackground()
        .navigationTitle("This week")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: PlanTextExporter.weeklyPlan(store.plan, meals: store.meals)) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share this week")
            }
        }
        .sheet(item: $selectedMeal) { meal in
            MealDetailView(meal: meal, initialServings: selectedServings).presentationDetents([.medium, .large])
        }
        .fullScreenCover(item: $cooking) { session in
            CookModeView(meal: session.meal, day: session.day, servings: session.servings, plannedDate: session.date)
                .environmentObject(store)
        }
        .sheet(item: $pickingDay) { day in
            MealPickerView(day: day).environmentObject(store)
        }
        .sheet(item: $editingDay) { day in
            DayContextEditor(
                day: day,
                initialContext: store.context(for: day),
                governingRule: store.dinnerModeRule(for: day)?.summary(meals: store.meals, context: store.matchContext)
            ) { store.updateContext($0, for: day) }
            .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder private var todayCard: some View {
        if let day = Weekday.ordered().first(where: { Calendar.current.isDateInToday(store.plan.date(for: $0)) }),
           let item = store.plan[day], item.kind == .meal,
           let meal = item.mealID.flatMap({ store.meal(id: $0) }) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Tonight", systemImage: "sun.horizon").font(.headline)
                Text(meal.name).font(.title2.bold())
                Text(L10n.portions(item.effectiveServings)).foregroundStyle(AppTheme.muted)
                Button("Open recipe") { selectedServings = item.effectiveServings; selectedMeal = meal }
                if store.isCompleted(on: day) {
                    Label("Cooked", systemImage: "checkmark.seal.fill").foregroundStyle(AppTheme.accent)
                } else {
                    Button { cooking = CookingSession(meal: meal, day: day, servings: item.effectiveServings, date: store.plan.date(for: day)) } label: {
                        Label("Start cooking", systemImage: "flame").frame(maxWidth: .infinity).padding(.vertical, 8)
                    }.buttonStyle(.borderedProminent)
                }
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading).mealCard()
        }
    }

    /// The week's date range, the two actions that change it, and what kind of week it
    /// turned out to be.
    ///
    /// Replaces a slogan and a permanent tooltip, neither of which told anyone anything
    /// about their own week.
    private var plannerHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(WeekAnchor.label(forWeekStarting: store.plan.startDate))
                        .font(.caption.bold()).foregroundStyle(AppTheme.accent)
                    Text("Your week")
                        .font(.system(.title, design: .rounded, weight: .bold)).foregroundStyle(AppTheme.ink)
                }
                Spacer()
                if store.canUndo { undoButton }
                shuffleButton
            }
            WeekCompositionView(plan: store.plan, meals: store.meals)
        }
        .padding(.vertical, 14)
    }

    private var shuffleButton: some View {
        Button {
            Haptics.shuffle()
            Task { await store.generateInBackground() }
        } label: {
            Image(systemName: "shuffle").font(.title2.bold())
                .frame(width: AppTheme.primaryAction, height: AppTheme.primaryAction)
                .background(AppTheme.accent).foregroundStyle(AppTheme.onAccent).clipShape(Circle())
                .shadow(color: AppTheme.accent.opacity(0.25), radius: 10, y: 5)
        }
        .disabled(store.remainingDinnerCount == 0)
        .accessibilityLabel(L10n.string("Shuffle %ld remaining dinners", store.remainingDinnerCount))
    }

    /// Sits next to shuffle because that is what usually creates the need for it. Shuffle
    /// used to throw the previous week away with no way back, in an app named after it.
    private var undoButton: some View {
        Button {
            Haptics.check()
            withAnimation(reduceMotion ? nil : .snappy) { store.undoLastChange() }
        } label: {
            Image(systemName: "arrow.uturn.backward").font(.body.bold())
                .frame(width: AppTheme.tapTarget, height: AppTheme.tapTarget)
                .background(AppTheme.raised).foregroundStyle(AppTheme.ink).clipShape(Circle())
        }
        .transition(.scale.combined(with: .opacity))
        .accessibilityLabel(store.undoLabel.map { L10n.string("Undo: %@", $0) } ?? L10n.string("Undo"))
    }

    /// Next week used to be an unlabelled toolbar glyph. It is one of the app's better
    /// ideas, and it sits here because the end of this week is when you think about it.
    private var nextWeekCard: some View {
        NavigationLink {
            NextWeekView()
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "calendar.badge.plus")
                    .font(.title3).foregroundStyle(AppTheme.accent)
                    .frame(width: AppTheme.emojiTileCompact, height: AppTheme.emojiTileCompact)
                    .background(AppTheme.accentSoft.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Next week").font(.headline).foregroundStyle(AppTheme.ink)
                    Text(nextWeekSummary).font(.caption).foregroundStyle(AppTheme.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(AppTheme.muted)
            }
            .padding(12)
            .mealCard()
        }
        .buttonStyle(.plain)
    }

    private var nextWeekSummary: String {
        guard let next = store.nextWeekPlan else {
            return L10n.string("Nothing planned yet. Get ahead in one tap.")
        }
        let dinners = next.meals.filter { $0.kind == .meal && $0.mealID != nil }.count
        return L10n.string("%ld dinners ready to take over", dinners)
    }

    private var historyLink: some View {
        NavigationLink {
            MealHistoryView()
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title3).foregroundStyle(AppTheme.accent)
                    .frame(width: AppTheme.emojiTileCompact, height: AppTheme.emojiTileCompact)
                    .background(AppTheme.accentSoft.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("History").font(.headline).foregroundStyle(AppTheme.ink)
                    Text("What you have cooked, and what is due a turn").font(.caption).foregroundStyle(AppTheme.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(AppTheme.muted)
            }
            .padding(12)
            .mealCard()
        }
        .buttonStyle(.plain)
    }

    /// Seven full-height cards mean you cannot see your own week without scrolling.
    /// This answers "what does this week look like" in one glance, and jumps to a day.
    private func weekStrip(scroll: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Weekday.ordered()) { day in
                    let item = store.plan[day]
                    Button {
                        withAnimation(reduceMotion ? nil : .snappy) { scroll.scrollTo(day, anchor: .top) }
                    } label: {
                        VStack(spacing: 3) {
                            Text(day.shortName.uppercased())
                                .font(.caption2.bold()).foregroundStyle(AppTheme.muted)
                            Text(glanceEmoji(item))
                                .font(.system(size: 22))
                                .opacity(isCooking(item) ? 1 : 0.55)
                            // A locked day is the one thing about a week worth seeing at a
                            // glance: it is what shuffle will not touch.
                            Image(systemName: "lock.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(AppTheme.accent)
                                .opacity(item?.isLocked == true ? 1 : 0)
                        }
                        .frame(width: 48, height: 62)
                        .background(AppTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                                .stroke(isToday(day) ? AppTheme.accent : .clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(glanceLabel(day: day, item: item))
                    .accessibilityHint(L10n.string("Jumps to that day"))
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
        .scrollClipDisabled()
    }

    private func isToday(_ day: Weekday) -> Bool {
        Calendar.current.isDateInToday(store.plan.date(for: day))
    }

    private func isCooking(_ item: PlannedMeal?) -> Bool {
        item?.kind == .meal && item?.mealID != nil
    }

    private func glanceEmoji(_ item: PlannedMeal?) -> String {
        guard let item else { return "·" }
        if let meal = item.mealID.flatMap({ store.meal(id: $0) }), item.kind == .meal { return meal.emoji }
        switch item.kind {
        case .away: return "🏃"
        case .takeaway: return "🥡"
        case .leftovers: return "♻️"
        case .meal: return "🍽️"
        }
    }

    private func glanceLabel(day: Weekday, item: PlannedMeal?) -> String {
        let meal = item?.mealID.flatMap { store.meal(id: $0) }
        let label: String
        switch item?.kind {
        case .away: label = L10n.string("No dinner at home")
        case .takeaway: label = L10n.string("Takeaway")
        case .leftovers: label = L10n.string("Leftovers")
        default: label = meal?.name ?? L10n.string("Not planned")
        }
        return "\(day.name), \(label)"
    }

    /// Nothing is broken here, so this deliberately avoids the warning styling the
    /// conflict banner uses.
    private var notesRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(store.planNotes) { note in
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "info.circle").foregroundStyle(AppTheme.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(note.message).font(.caption).foregroundStyle(AppTheme.ink)
                        if let suggestion = note.suggestion {
                            Text(suggestion).font(.caption2).foregroundStyle(AppTheme.muted)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(14)
        .background(AppTheme.accentSoft.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
    }
}

struct DayPlanCard: View {
    let day: Weekday
    let date: Date
    let item: PlannedMeal
    let meal: Meal?
    let explanation: String?
    let isCompleted: Bool
    let clearCompletion: () -> Void
    let isFavorite: Bool
    let open: () -> Void
    let chooseMeal: () -> Void
    let editContext: () -> Void
    let toggleLock: () -> Void
    let shuffle: (MealSwapIntent) -> Void
    let snooze: () -> Void
    let toggleFavorite: () -> Void
    let markCooked: () -> Void
    let markSkipped: () -> Void
    let cook: () -> Void
    let swapWith: (Weekday) -> Void
    var allowsCooking = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                MealThumbnail(meal: isCooking ? meal : nil, fallbackEmoji: cardEmoji)
                VStack(alignment: .leading, spacing: 4) {
                    Text(dayLabel).font(.caption2.bold()).tracking(0.8).foregroundStyle(AppTheme.accent)
                    Text(cardTitle).font(.headline).foregroundStyle(AppTheme.ink).fixedSize(horizontal: false, vertical: true)
                    if isCompleted { Label("Cooked", systemImage: "checkmark.seal.fill").font(.caption).foregroundStyle(AppTheme.accent) }
                    Text(cardMetadata).font(.caption).foregroundStyle(AppTheme.muted)
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .contentShape(Rectangle())
            .onTapGesture { if meal != nil { open() } else { editContext() } }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(dayLabel), \(cardTitle), \(cardMetadata)")
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(meal == nil ? L10n.string("Plan this day") : L10n.string("Opens the recipe"))

            if let explanation {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "sparkles").foregroundStyle(AppTheme.accent)
                    Text(explanation).font(.caption).foregroundStyle(AppTheme.muted)
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.top, 9)
            }

            // Controls sit on their own row rather than inside the card's tap area, where a
            // near miss on a 34pt lock opened the recipe instead.
            HStack(spacing: 4) {
                Button(action: chooseMeal) {
                    Label("Choose", systemImage: "hand.tap")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .frame(minHeight: 44)
                        .background(AppTheme.accentSoft)
                        .foregroundStyle(AppTheme.accent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("Choose the dinner for %@", day.name))

                Spacer(minLength: 0)

                Button(action: toggleLock) {
                    Image(systemName: item.isLocked ? "lock.fill" : "lock.open")
                        .foregroundStyle(item.isLocked ? AppTheme.accent : AppTheme.muted)
                        .iconButtonFrame()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.isLocked ? L10n.string("Unlock this day") : L10n.string("Lock this day"))

                menu
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
        }
        .mealCard()
    }

    private var menu: some View {
        Menu {
            Button(action: chooseMeal) { Label("Choose a dinner", systemImage: "hand.tap") }
            Section("Replace dinner") {
                ForEach(MealSwapIntent.allCases) { intent in
                    Button { shuffle(intent) } label: { Label(intent.name, systemImage: intent.symbol) }
                }
            }
            Section("Move") {
                Menu("Swap with another day") {
                    ForEach(Weekday.ordered().filter { $0 != day }) { other in Button(other.name) { swapWith(other) } }
                }
            }
            if meal != nil {
                Section {
                  if allowsCooking {
                    if item.kind == .meal { Button(action: cook) { Label("Start cooking", systemImage: "flame") } }
                    if isCompleted { Button("Undo cooking completion", action: clearCompletion) }
                    else { Button(action: markCooked) { Label(item.kind == .meal ? L10n.string("We cooked this") : L10n.string("We ate this"), systemImage: "checkmark.seal") } }
                    Button(action: markSkipped) { Label("Not for today", systemImage: "forward") }
                  }
                    Button(action: toggleFavorite) {
                        Label(
                            isFavorite ? L10n.string("Remove family favorite") : L10n.string("Family favorite"),
                            systemImage: isFavorite ? "heart.slash" : "heart"
                        )
                    }
                    if allowsCooking { Button(role: .destructive, action: snooze) { Label("Not again for a while", systemImage: "calendar.badge.minus") } }
                }
            }
            Button(action: editContext) { Label("Plan this day", systemImage: "person.2") }
        } label: {
            Image(systemName: "ellipsis.circle").font(.title3)
                .foregroundStyle(AppTheme.muted)
                .iconButtonFrame()
        }
        .accessibilityLabel(L10n.string("Options for %@", day.name))
    }

    private var isCooking: Bool { item.kind == .meal }

    /// Shows the actual date alongside the weekday now that the plan is anchored.
    private var dayLabel: String {
        let formatted = date.formatted(.dateTime.day().month(.abbreviated))
        return "\(day.name.uppercased()) · \(formatted)"
    }

    private var cardEmoji: String {
        if let meal, isCooking { return meal.emoji }
        return switch item.kind {
        case .away: "🏃"
        case .takeaway: "🥡"
        case .leftovers: "♻️"
        case .meal: "🍽️"
        }
    }

    private var cardTitle: String {
        if let batch = item.freezerBatch { return L10n.string("From the freezer: %@", batch.recipe.name) }
        if case .leftovers = item.kind {
            return meal.map { L10n.string("Leftovers: %@", $0.name) } ?? L10n.string("Leftovers")
        }
        if let meal { return meal.name }
        return switch item.kind {
        case .away: L10n.string("No dinner at home")
        case .takeaway: L10n.string("Takeaway")
        default: L10n.string("Not planned")
        }
    }

    private var cardMetadata: String {
        if let meal, isCooking { return [meal.prepMinutes > 0 ? L10n.string("%ld min", meal.prepMinutes) : L10n.string("Time not specified"), L10n.portions(item.effectiveServings)].joined(separator: " · ") }
        return item.kind == .away
            ? L10n.string("Day off")
            : L10n.string("%ld people", item.servings)
    }
}

struct DayContextEditor: View {
    @EnvironmentObject private var store: AppStore
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
                                        .frame(width: 26, height: 26)
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
        ZStack {
            RoundedRectangle(cornerRadius: AppTheme.heroRadius, style: .continuous).fill(AppTheme.accentSoft)
            if let url = meal.heroImageURL {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        Text(meal.emoji).font(.system(size: 105))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.heroRadius, style: .continuous))
            } else {
                Text(meal.emoji).font(.system(size: 105))
            }
        }
        .frame(height: 220)
        .accessibilityHidden(true)
    }
}
