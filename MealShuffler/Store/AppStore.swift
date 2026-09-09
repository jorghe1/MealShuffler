import Combine
import Foundation

@MainActor
final class AppStore: ObservableObject {
    @Published var hasCompletedOnboarding: Bool { didSet { save() } }
    @Published var memberPreferences: [UUID: [UUID: MealPreference]] { didSet { save() } }
    @Published var rules: [PlanningRule] { didSet { save() } }
    @Published var plan: WeeklyPlan { didSet { save() } }
    @Published var conflicts: [PlanConflict] = []
    @Published var checkedGroceryIDs: Set<String> { didSet { save() } }
    /// Items the household already has in. Kept apart from `checkedGroceryIDs` because
    /// "we own this" and "I picked this up just now" are different facts with different
    /// lifetimes -- one survives the shop, the other is the shop.
    @Published var stockedGroceryIDs: Set<String> { didSet { save() } }
    @Published var manualGroceryItems: [ManualGroceryItem] { didSet { save() } }
    /// Things the household always has in: salt, oil, rice.
    ///
    /// Distinct from `stockedGroceryIDs`, which is "we happen to have this right now" and is
    /// meant to be put back. A staple is a standing fact, so it never reaches the list at all.
    @Published var pantryStaples: Set<String> { didSet { save() } }
    /// The order aisles appear in the shopping list.
    ///
    /// A fixed order is wrong in every shop but one, and the walk through a supermarket is
    /// the whole reason the list is grouped at all.
    @Published var aisleOrder: [GroceryAisle] { didSet { save() } }
    @Published var customMeals: [Meal] { didSet { save() } }
    @Published var favoriteMealIDs: Set<UUID> { didSet { save() } }
    @Published var dayContexts: [Weekday: DayPlanContext] { didSet { save() } }
    @Published var feedbackEvents: [MealFeedbackEvent] { didSet { save() } }
    @Published var householdSize: Int { didSet { save() } }
    @Published var household: Household { didSet { save() } }
    @Published var archivedWeeks: [ArchivedWeek] { didSet { save() } }
    @Published var nextWeekPlan: WeeklyPlan? { didSet { save() } }
    @Published var dinnerReminderEnabled: Bool { didSet { save() } }
    @Published var dinnerReminderHour: Int { didSet { save() } }
    /// A second, earlier nudge timed off the recipe's own prep time.
    @Published var prepLeadReminderEnabled: Bool { didSet { save() } }
    @Published var groceryReminderEnabled: Bool { didSet { save() } }
    @Published var groceryReminderWeekday: Weekday { didSet { save() } }
    @Published var groceryReminderHour: Int { didSet { save() } }
    @Published var inviteNotice: String?
    /// Recipes shared in from other apps, waiting to be turned into meals.
    @Published var pendingCaptures: [CapturedRecipe] = []

    /// The plan as it stood before the last change, so the signature action is reversible.
    ///
    /// Shuffle threw the previous week away with nothing to put it back, which is a hard
    /// thing to ship in an app named after shuffling. Session-only on purpose: an undo the
    /// user last saw a week ago is not an undo.
    @Published private var undoCheckpoint: PlanCheckpoint?

    private struct PlanCheckpoint {
        let plan: WeeklyPlan
        let contexts: [Weekday: DayPlanContext]
        let feedbackEvents: [MealFeedbackEvent]
        let label: String
    }

    private let generator: MealPlanGenerator
    private var isRestoring = true
    private let repository: any AppStateRepository
    private let widgetRefresher: any WidgetRefreshing
    private let reminderService: any ReminderScheduling
    /// Hash of everything the widget and the notification schedule are derived from, so a
    /// grocery tick does not reschedule seven notifications.
    private var lastBackgroundSignature: Int?
    private var pendingSave: Task<Void, Never>?
    private static let feedbackRetentionDays = 400
    private static let feedbackEventLimit = 2_000
    private static let archiveLimit = 26

    /// Custom meals that have not been deleted. Tombstones stay in `customMeals` so a future
    /// sync can tell "deleted here" apart from "never existed here".
    var activeCustomMeals: [Meal] { customMeals.filter { !$0.isDeleted } }

    /// Built-ins, with any customised version substituted in, followed by the user's own.
    ///
    /// Resolution lives in `MealCatalog` so the widget resolves the library identically.
    var meals: [Meal] { MealCatalog.resolve(custom: customMeals) }

    /// Test seam: a disposable defaults suite instead of the shared container.
    convenience init(defaults: UserDefaults, random: RandomSource = SystemRandomSource()) {
        self.init(repository: UserDefaultsStateRepository(defaults: defaults), random: random)
    }

    convenience init(random: RandomSource = SystemRandomSource()) {
        self.init(repository: FileStateRepository.live(), random: random)
    }

    init(
        repository: any AppStateRepository,
        random: RandomSource = SystemRandomSource(),
        widgetRefresher: any WidgetRefreshing = WidgetKitRefresher(),
        reminderService: any ReminderScheduling = DinnerReminderService()
    ) {
        self.repository = repository
        self.widgetRefresher = widgetRefresher
        self.reminderService = reminderService
        generator = MealPlanGenerator(random: random)
        if let state = repository.load() {
            hasCompletedOnboarding = state.hasCompletedOnboarding
            memberPreferences = state.memberPreferences
            rules = state.rules
            plan = state.plan
            checkedGroceryIDs = state.checkedGroceryIDs
            stockedGroceryIDs = state.stockedGroceryIDs
            manualGroceryItems = state.manualGroceryItems
            pantryStaples = state.pantryStaples
            aisleOrder = AppStore.completeAisleOrder(state.aisleOrder)
            customMeals = state.customMeals
            favoriteMealIDs = state.favoriteMealIDs
            dayContexts = state.dayContexts
            feedbackEvents = AppStore.prunedFeedback(state.feedbackEvents)
            householdSize = state.householdSize
            household = state.household
            archivedWeeks = state.archivedWeeks
            nextWeekPlan = state.nextWeekPlan
            dinnerReminderEnabled = state.dinnerReminderEnabled
            dinnerReminderHour = state.dinnerReminderHour
            prepLeadReminderEnabled = state.prepLeadReminderEnabled
            groceryReminderEnabled = state.groceryReminderEnabled
            groceryReminderWeekday = state.groceryReminderWeekday
            groceryReminderHour = state.groceryReminderHour
        } else {
            hasCompletedOnboarding = false
            memberPreferences = [:]
            rules = PlanningRule.starterRules(meals: SampleMeals.all)
            plan = .empty
            checkedGroceryIDs = []
            stockedGroceryIDs = []
            manualGroceryItems = []
            pantryStaples = []
            aisleOrder = GroceryAisle.allCases
            customMeals = []
            favoriteMealIDs = []
            dayContexts = [:]
            feedbackEvents = []
            householdSize = 4
            household = Household()
            archivedWeeks = []
            nextWeekPlan = nil
            dinnerReminderEnabled = false
            dinnerReminderHour = 16
            prepLeadReminderEnabled = false
            groceryReminderEnabled = false
            groceryReminderWeekday = .saturday
            groceryReminderHour = 10
        }
        isRestoring = false
        inviteNotice = nil
        pendingCaptures = RecipeInbox.all()
        rollOverIfNeeded()
        refreshConflicts()
        // Unconditional: permission may have been granted in Settings.app since the last
        // launch, in which case nothing has changed here but nothing is scheduled either.
        refreshBackgroundSurfaces(force: true)
    }

    // MARK: - Week rollover

    /// Moves the calendar on. A finished week is archived, next week's plan is promoted if one
    /// was prepared, and otherwise the current plan is re-anchored so it stops claiming to be
    /// a week that has already passed.
    /// Picks up anything the share extension left behind. Called when the app becomes
    /// active, because that is the only moment the extension's work becomes visible.
    func refreshPendingCaptures() {
        let waiting = RecipeInbox.all()
        if waiting.map(\.id) != pendingCaptures.map(\.id) { pendingCaptures = waiting }
    }

    func discardCapture(_ capture: CapturedRecipe) {
        RecipeInbox.remove(capture.id)
        pendingCaptures.removeAll { $0.id == capture.id }
    }

    func rollOverIfNeeded(now: Date = .now, calendar: Calendar = .current) {
        let currentWeekStart = WeekAnchor.startOfWeek(containing: now, calendar: calendar)
        guard plan.startDate < currentWeekStart else { return }

        if !plan.meals.isEmpty {
            archivedWeeks = Array((archivedWeeks + [ArchivedWeek(plan: plan)])
                .sorted { $0.startDate > $1.startDate }
                .prefix(AppStore.archiveLimit))
        }

        if let prepared = nextWeekPlan, prepared.startDate == currentWeekStart {
            plan = prepared
            nextWeekPlan = nil
        } else {
            nextWeekPlan = nil
            plan = plan.anchored(to: currentWeekStart)
            if hasCompletedOnboarding { shuffleAll() }
        }
        // A week that has already turned cannot be undone back into.
        undoCheckpoint = nil
    }

    // MARK: - Next week

    /// Builds a plan for the week after this one, without disturbing the current week.
    func planNextWeek() {
        let start = WeekAnchor.startOfNextWeek(after: plan.startDate)
        let result = generator.generate(
            preferredMeals: preferredMeals,
            allMeals: meals,
            rules: rules,
            contexts: resolvedContexts,
            taste: taste,
            matchContext: matchContext
        )
        nextWeekPlan = result.plan.anchored(to: start)
    }

    func discardNextWeek() {
        nextWeekPlan = nil
    }

    // MARK: - Reminders

    /// Turns the daily reminder on, asking for permission the first time.
    ///
    /// Returns whether it ended up on, so a caller that offered the toggle can say something
    /// useful when the system prompt was declined.
    @discardableResult
    func setDinnerReminder(enabled: Bool) async -> Bool {
        guard enabled else {
            dinnerReminderEnabled = false
            // Forced, so pending notifications are withdrawn now rather than after the
            // save debounce. Turning a reminder off should feel immediate.
            refreshBackgroundSurfaces(force: true)
            return false
        }
        let authorized = await reminderService.isAuthorized()
        if !authorized {
            guard await reminderService.requestAuthorization() else {
                dinnerReminderEnabled = false
                return false
            }
        }
        dinnerReminderEnabled = true
        refreshBackgroundSurfaces(force: true)
        return true
    }

    func setDinnerReminderHour(_ hour: Int) {
        dinnerReminderHour = max(0, min(hour, 23))
    }

    func setGroceryReminderHour(_ hour: Int) {
        groceryReminderHour = max(0, min(hour, 23))
    }

    /// The same permission gate as the dinner reminder, for the two secondary toggles.
    @discardableResult
    func setGroceryReminder(enabled: Bool) async -> Bool {
        guard enabled else {
            groceryReminderEnabled = false
            refreshBackgroundSurfaces(force: true)
            return false
        }
        let authorized = await reminderService.isAuthorized()
        if !authorized {
            guard await reminderService.requestAuthorization() else {
                groceryReminderEnabled = false
                return false
            }
        }
        groceryReminderEnabled = true
        refreshBackgroundSurfaces(force: true)
        return true
    }

    /// Acts on a button tapped on a dinner reminder, without the household opening the app.
    func handleReminderAction(_ action: DinnerReminderAction) {
        switch action {
        case .cooked(let mealID, let day):
            guard let meal = meal(id: mealID) else { return }
            markCooked(meal, on: day)
        case .somethingElse(let mealID, let day):
            guard let meal = meal(id: mealID) else { return }
            markSkipped(meal, on: day)
        }
    }

    /// Everything the notification schedule is derived from.
    private var reminderSchedule: ReminderSchedule {
        ReminderSchedule(
            plan: plan,
            nextWeekPlan: nextWeekPlan,
            meals: meals,
            dinnerEnabled: dinnerReminderEnabled,
            dinnerHour: dinnerReminderHour,
            prepLeadEnabled: prepLeadReminderEnabled,
            groceryEnabled: groceryReminderEnabled,
            groceryWeekday: groceryReminderWeekday,
            groceryHour: groceryReminderHour
        )
    }

    private var backgroundSignature: Int {
        var hasher = Hasher()
        hasher.combine(plan)
        hasher.combine(nextWeekPlan)
        hasher.combine(customMeals)
        hasher.combine(dinnerReminderEnabled)
        hasher.combine(dinnerReminderHour)
        hasher.combine(prepLeadReminderEnabled)
        hasher.combine(groceryReminderEnabled)
        hasher.combine(groceryReminderWeekday)
        hasher.combine(groceryReminderHour)
        return hasher.finalize()
    }

    /// Brings the widget and the notification schedule back in line with the state that was
    /// just written.
    ///
    /// Driven from the single write funnel rather than from each mutating method. Every
    /// place that forgot to call the old `refreshReminders()` was a day announcing the meal
    /// it replaced -- swapping two days was one of them -- and the widget had no such call
    /// anywhere at all, so it showed a stale dinner until its timeline happened to expire.
    private func refreshBackgroundSurfaces(force: Bool = false) {
        let signature = backgroundSignature
        guard force || signature != lastBackgroundSignature else { return }
        lastBackgroundSignature = signature

        widgetRefresher.reload()

        let schedule = reminderSchedule
        let service = reminderService
        Task { await service.reschedule(schedule) }
    }

    var preferredMeals: [Meal] {
        let snoozed = activeSnoozedMealIDs
        let accepted = meals.filter {
            preferences[$0.id] != .disliked && !snoozed.contains($0.id)
        }
        return accepted.isEmpty ? meals : accepted
    }

    /// Everything the plan calls for, plus anything typed in, minus the staples the
    /// household always has and anything set aside as already in.
    var groceryItems: [GroceryItem] {
        GroceryListBuilder.build(plan: plan, meals: meals, manualItems: manualGroceryItems)
            .filter { !stockedGroceryIDs.contains($0.id) && !isStaple($0) }
    }

    /// Matches on the name alone: a staple is "we always have olive oil", not "we always have
    /// exactly one bottle of it".
    func isStaple(_ item: GroceryItem) -> Bool {
        pantryStaples.contains(AppStore.stapleKey(item.name))
    }

    nonisolated static func stapleKey(_ name: String) -> String {
        name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func setStaple(_ item: GroceryItem, isStaple: Bool) {
        let key = AppStore.stapleKey(item.name)
        if isStaple {
            pantryStaples.insert(key)
            checkedGroceryIDs.remove(item.id)
            stockedGroceryIDs.remove(item.id)
        } else {
            pantryStaples.remove(key)
        }
    }

    func removeStaples(_ keys: Set<String>) {
        guard !keys.isEmpty else { return }
        pantryStaples.subtract(keys)
    }

    /// Staples in the order they read, for a screen that lists them.
    var pantryStapleNames: [String] { pantryStaples.sorted() }

    /// Items set aside as already owned. Surfaced so they can be put back.
    var stockedItems: [GroceryItem] {
        GroceryListBuilder.build(plan: plan, meals: meals, manualItems: manualGroceryItems)
            .filter { stockedGroceryIDs.contains($0.id) }
    }

    /// Keeps a stored order usable when the aisle set changes: unknown entries drop out,
    /// and any aisle added since is appended rather than silently disappearing.
    nonisolated static func completeAisleOrder(_ stored: [GroceryAisle]) -> [GroceryAisle] {
        let known = stored.filter(GroceryAisle.allCases.contains)
        return known + GroceryAisle.allCases.filter { !known.contains($0) }
    }

    func moveAisles(from offsets: IndexSet, to destination: Int) {
        var order = aisleOrder
        order.move(fromOffsets: offsets, toOffset: destination)
        aisleOrder = order
    }

    func resetAisleOrder() {
        aisleOrder = GroceryAisle.allCases
    }

    func addGroceryItem(name: String, quantity: Double?, unit: String, aisle: GroceryAisle) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        manualGroceryItems.append(ManualGroceryItem(
            name: cleanName,
            quantity: quantity,
            unit: unit.trimmingCharacters(in: .whitespacesAndNewlines),
            aisle: aisle
        ))
    }

    func removeManualGroceryItems(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        manualGroceryItems.removeAll { ids.contains($0.id) }
    }

    func manualItem(matching item: GroceryItem) -> ManualGroceryItem? {
        manualGroceryItems.first { $0.groceryID == item.id }
    }

    /// Sets an item aside as already owned, or puts it back on the list.
    func setStocked(_ item: GroceryItem, stocked: Bool) {
        if stocked {
            stockedGroceryIDs.insert(item.id)
            checkedGroceryIDs.remove(item.id)
        } else {
            stockedGroceryIDs.remove(item.id)
        }
    }

    /// Required rules the plan could not satisfy. These are what the warning banner counts.
    var blockingConflicts: [PlanConflict] { conflicts.filter { $0.severity == .blocking } }

    /// Observations about how the week was built. Nothing is wrong; shown quietly.
    var planNotes: [PlanConflict] { conflicts.filter { $0.severity == .informational } }

    /// Everything the generator should know about this household's taste.
    private var taste: TasteProfile {
        TasteProfile(
            favoriteMealIDs: favoriteMealIDs,
            likedMealIDs: Set(preferences.filter { $0.value == .liked }.keys),
            dislikedMealIDs: Set(preferences.filter { $0.value == .disliked }.keys),
            learnedScores: learnedMealScores,
            recentlyCookedMealIDs: recentlyCookedMealIDs,
            weeksSinceLastPlanned: weeksSinceLastPlanned
        )
    }

    var activeSnoozedMealIDs: Set<UUID> {
        let cutoff = Calendar.current.date(byAdding: .day, value: -28, to: .now) ?? .distantPast
        return Set(feedbackEvents.filter { $0.kind == .snoozed && $0.timestamp >= cutoff }.map(\.mealID))
    }

    var learnedMealScores: [UUID: Int] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -120, to: .now) ?? .distantPast
        return Dictionary(grouping: feedbackEvents.filter { $0.timestamp >= cutoff }, by: \.mealID)
            .mapValues { events in
                let rawScore = events.reduce(0) { score, event in
                    switch event.kind {
                    case .cooked: return score + 3
                    case .skipped: return score - 2
                    case .snoozed: return score - 6
                    }
                }
                return min(max(rawScore, -10), 10)
            }
    }

    /// When each meal was last actually cooked.
    ///
    /// The rotation view's whole content: "what have we not had in a while" is the question
    /// a variety-driven planner should be able to answer, and history could only show a flat
    /// list of events.
    var lastCookedByMeal: [UUID: Date] {
        var latest: [UUID: Date] = [:]
        for event in feedbackEvents where event.kind == .cooked {
            if let existing = latest[event.mealID], existing >= event.timestamp { continue }
            latest[event.mealID] = event.timestamp
        }
        return latest
    }

    var recentlyCookedMealIDs: Set<UUID> {
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .distantPast
        return Set(feedbackEvents.filter { $0.kind == .cooked && $0.timestamp >= cutoff }.map(\.mealID))
    }

    func meal(id: UUID) -> Meal? {
        meals.first(where: { $0.id == id })
    }

    /// A meal already in the library under this name.
    ///
    /// Importing the same page twice used to produce two meals with no hint that it had
    /// happened, and the second one then competed with the first for every day of the week.
    func mealNamed(_ name: String) -> Meal? {
        let target = AppStore.stapleKey(name)
        guard !target.isEmpty else { return nil }
        return meals.first { AppStore.stapleKey($0.name) == target }
    }

    func context(for day: Weekday) -> DayPlanContext {
        dayContexts[day] ?? DayPlanContext(diners: householdSize)
    }

    /// Records a taste opinion against a specific member.
    ///
    /// Preferences are stored per person because that is the one thing about them that cannot
    /// be reconstructed later -- a flat map cannot say afterwards whose dislike it was. The
    /// swipe UI still speaks for the household owner; the storage shape is ready for the day
    /// it asks who is swiping.
    func setPreference(_ preference: MealPreference, for meal: Meal, member: UUID? = nil) {
        let memberID = member ?? primaryMemberID
        memberPreferences[memberID, default: [:]][meal.id] = preference
    }

    var primaryMemberID: UUID {
        household.members.first(where: { $0.role == .owner })?.id
            ?? household.members.first?.id
            ?? household.id
    }

    /// One opinion per meal for the household as a whole.
    ///
    /// A dislike from anyone wins: someone at the table will not eat it.
    var preferences: [UUID: MealPreference] {
        var merged: [UUID: MealPreference] = [:]
        for opinions in memberPreferences.values {
            for (mealID, preference) in opinions {
                if merged[mealID] == .disliked { continue }
                if preference == .disliked || merged[mealID] == nil { merged[mealID] = preference }
            }
        }
        return merged
    }

    /// Marks onboarding done without discarding a week the user has already been shown.
    ///
    /// The last step now previews a real plan, so re-shuffling here would replace the very
    /// week they just approved.
    func completeOnboarding() {
        hasCompletedOnboarding = true
        if plan.meals.isEmpty { shuffleAll() }
        // There is nothing sensible to undo back into before the first week existed.
        undoCheckpoint = nil
    }

    // MARK: - Undo

    var canUndo: Bool { undoCheckpoint != nil }

    /// What undoing would put back, for a button that says so rather than just "Undo".
    var undoLabel: String? { undoCheckpoint?.label }

    /// Remembers the plan before a change that replaces dinners.
    ///
    /// Feedback events come along because snoozing and skipping write one before re-rolling
    /// the day; restoring the plan without them would leave the meal quietly suppressed for
    /// four weeks with no visible cause.
    private func rememberForUndo(_ label: String) {
        undoCheckpoint = PlanCheckpoint(
            plan: plan,
            contexts: dayContexts,
            feedbackEvents: feedbackEvents,
            label: label
        )
    }

    func undoLastChange() {
        guard let restore = undoCheckpoint else { return }
        undoCheckpoint = nil
        dayContexts = restore.contexts
        feedbackEvents = restore.feedbackEvents
        plan = restore.plan
        refreshConflicts()
        reconcileGroceryChecks()
    }

    // MARK: - Choosing a dinner

    /// Puts a specific meal on a specific day.
    ///
    /// The one thing the app could not express: rules, intents and locks all describe what
    /// the generator should pick, and none of them says "Thursday is lasagne". The day is
    /// locked afterwards because a dinner chosen by hand should survive the next shuffle.
    func setMeal(_ meal: Meal, on day: Weekday) {
        rememberForUndo(L10n.string("Dinner on %@", day.name.lowercased()))

        var context = context(for: day)
        // Choosing a dinner for a day nobody was eating at home means eating at home again.
        if context.mode != .cook {
            context.mode = .cook
            context.leftoverSourceDay = nil
            dayContexts[day] = context
        }

        var item = plan[day] ?? PlannedMeal(day: day, mealID: nil, isLocked: false)
        item.mealID = meal.id
        item.kind = .meal
        item.servings = context.cookedServings
        item.isLocked = true
        plan[day] = item

        refreshConflicts()
        reconcileGroceryChecks()
    }

    /// Re-rolls every unlocked day. This is the explicit "shuffle the week" action.
    func shuffleAll() {
        rememberForUndo(L10n.string("Shuffle week"))
        let result = generator.generate(
            preferredMeals: preferredMeals,
            allMeals: meals,
            rules: rules,
            contexts: resolvedContexts,
            taste: taste,
            existingPlan: WeeklyPlan(meals: plan.meals.filter(\.isLocked)),
            matchContext: matchContext
        )
        apply(result)
    }

    /// Re-rolls only `days`, leaving every other day exactly as it stands.
    ///
    /// Editing one day used to run `shuffleAll()`, so adjusting Wednesday's diner count
    /// replaced the whole week. Scoping regeneration to the days an edit can actually
    /// invalidate keeps the rest of the user's week intact.
    ///
    /// - Parameter respectingLocks: `false` when the user acted on those days directly
    ///   (a per-day reshuffle, a day-plan edit), so their own lock should not block the
    ///   action. `true` for indirect changes like a rule edit, where locks must survive.
    func regenerate(
        days: Set<Weekday>,
        respectingLocks: Bool = true,
        intents: [Weekday: MealSwapIntent] = [:],
        avoiding: [Weekday: UUID] = [:]
    ) {
        guard !days.isEmpty else { return }
        let userLocks = Dictionary(plan.meals.map { ($0.day, $0.isLocked) }, uniquingKeysWith: { $1 })
        // Pin everything outside the requested set for this pass, then restore real locks.
        let pinned = WeeklyPlan(meals: plan.meals.map { item in
            var copy = item
            let isTarget = days.contains(item.day)
            copy.isLocked = respectingLocks ? (item.isLocked || !isTarget) : !isTarget
            return copy
        })
        let result = generator.generate(
            preferredMeals: preferredMeals,
            allMeals: meals,
            rules: rules,
            contexts: resolvedContexts,
            taste: taste,
            existingPlan: pinned,
            avoidingMealOnDay: avoiding,
            swapIntents: intents,
            matchContext: matchContext
        )
        var updated = result.plan.anchored(to: plan.startDate)
        for index in updated.meals.indices {
            updated.meals[index].isLocked = userLocks[updated.meals[index].day] ?? false
        }
        plan = updated
        conflicts = result.conflicts
        reconcileGroceryChecks()
    }

    func shuffle(day: Weekday, intent: MealSwapIntent = .different) {
        rememberForUndo(L10n.string("Dinner on %@", day.name.lowercased()))
        let currentID = plan[day]?.mealID
        regenerate(
            days: [day],
            respectingLocks: false,
            intents: [day: intent],
            avoiding: currentID.map { [day: $0] } ?? [:]
        )
    }

    func toggleLock(day: Weekday) {
        guard var item = plan[day] else { return }
        item.isLocked.toggle()
        plan[day] = item
    }

    func updateContext(_ context: DayPlanContext, for day: Weekday) {
        rememberForUndo(L10n.string("Plan for %@", day.name.lowercased()))
        dayContexts[day] = context
        // Days eating this day's leftovers depend on what it cooks, so they re-roll too.
        var affected: Set<Weekday> = [day]
        for item in plan.meals {
            if case .leftovers(let source) = item.kind, source == day { affected.insert(item.day) }
        }
        for (other, otherContext) in dayContexts
        where otherContext.mode == .leftovers && otherContext.leftoverSourceDay == day {
            affected.insert(other)
        }
        regenerate(days: affected, respectingLocks: false)
    }

    func swapMeals(between firstDay: Weekday, and secondDay: Weekday) {
        guard var first = plan[firstDay], var second = plan[secondDay] else { return }
        rememberForUndo(L10n.string("Swap of two days"))
        let firstPayload = (first.mealID, first.kind)
        first.mealID = second.mealID
        first.kind = second.kind
        first.servings = context(for: firstDay).cookedServings
        first.isLocked = false
        second.mealID = firstPayload.0
        second.kind = firstPayload.1
        second.servings = context(for: secondDay).cookedServings
        second.isLocked = false
        plan[firstDay] = first
        plan[secondDay] = second
        refreshConflicts()
        reconcileGroceryChecks()
    }

    func toggleRule(_ rule: PlanningRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        setRule(rule, enabled: !rules[index].isEnabled)
    }

    /// Takes the value rather than flipping the current one, so a duplicate send from a
    /// SwiftUI toggle cannot leave the switch and the model disagreeing.
    func setRule(_ rule: PlanningRule, enabled: Bool) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }),
              rules[index].isEnabled != enabled else { return }
        rules[index].isEnabled = enabled
        regenerate(days: rules[index].constraint.affectedDays)
    }

    func setRuleStrength(_ strength: RuleStrength, ruleID: UUID) {
        guard let index = rules.firstIndex(where: { $0.id == ruleID }) else { return }
        rules[index].strength = strength
        regenerate(days: rules[index].constraint.affectedDays)
    }

    /// What happened when a rule was offered.
    enum RuleAdditionOutcome: Equatable {
        case added
        /// An enabled rule already says exactly this.
        case duplicate(existingTitle: String)
        /// An enabled rule says the opposite, so one of them can never hold.
        case contradiction(existingTitle: String)
    }

    /// Adds a rule unless the rule list already answers it.
    ///
    /// `addRule` used to append unconditionally, so a household could hold "fish on Tuesday"
    /// twice and learn about a flat contradiction only from a conflict banner after the week
    /// was built. Both are cheap to answer at the moment of asking.
    @discardableResult
    func addRule(_ rule: PlanningRule) -> RuleAdditionOutcome {
        if let existing = rules.first(where: {
            $0.isEnabled && $0.constraint.saysTheSameAs(rule.constraint)
        }) {
            return .duplicate(existingTitle: existing.summary(meals: meals, context: matchContext))
        }
        if let existing = rules.first(where: {
            $0.isEnabled && $0.constraint.contradicts(rule.constraint)
        }) {
            return .contradiction(existingTitle: existing.summary(meals: meals, context: matchContext))
        }
        rules.append(rule)
        regenerate(days: rule.constraint.affectedDays)
        return .added
    }

    func deleteRules(at offsets: IndexSet) {
        let affected = offsets
            .filter { rules.indices.contains($0) }
            .reduce(into: Set<Weekday>()) { $0.formUnion(rules[$1].constraint.affectedDays) }
        for index in offsets.sorted(by: >) where rules.indices.contains(index) { rules.remove(at: index) }
        regenerate(days: affected)
    }

    func toggleFavorite(_ meal: Meal) {
        if favoriteMealIDs.contains(meal.id) { favoriteMealIDs.remove(meal.id) }
        else { favoriteMealIDs.insert(meal.id) }
    }

    func snooze(_ meal: Meal, on day: Weekday) {
        rememberForUndo(L10n.string("Pausing %@", meal.name))
        appendFeedback(MealFeedbackEvent(mealID: meal.id, kind: .snoozed, weekday: day))
        regenerate(days: [day], respectingLocks: false, intents: [day: .different], avoiding: [day: meal.id])
    }

    func markCooked(_ meal: Meal, on day: Weekday) {
        appendFeedback(MealFeedbackEvent(mealID: meal.id, kind: .cooked, weekday: day))
    }

    func markSkipped(_ meal: Meal, on day: Weekday) {
        rememberForUndo(L10n.string("Replacing %@", meal.name))
        appendFeedback(MealFeedbackEvent(mealID: meal.id, kind: .skipped, weekday: day))
        regenerate(days: [day], respectingLocks: false, intents: [day: .different], avoiding: [day: meal.id])
    }

    private func appendFeedback(_ event: MealFeedbackEvent) {
        feedbackEvents = Self.prunedFeedback(feedbackEvents + [event])
    }

    /// Caps the history that is rewritten on every change. Scoring only looks back 120 days,
    /// but the log was kept forever, so the blob re-encoded on each tap grew for the life of
    /// the install. The retained window still comfortably outlives anything the UI shows.
    private static func prunedFeedback(_ events: [MealFeedbackEvent]) -> [MealFeedbackEvent] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -feedbackRetentionDays, to: .now)
            ?? .distantPast
        let recent = events.filter { $0.timestamp >= cutoff }
        guard recent.count > feedbackEventLimit else { return recent }
        return Array(recent.sorted { $0.timestamp > $1.timestamp }.prefix(feedbackEventLimit))
    }

    func clearHistory() {
        feedbackEvents = []
    }

    func saveMeal(_ meal: Meal) {
        let stamped = meal.touched()
        if let index = customMeals.firstIndex(where: { $0.id == meal.id }) {
            customMeals[index] = stamped
        } else {
            customMeals.append(stamped)
        }
    }

    func deleteCustomMeals(at offsets: IndexSet, from visibleMeals: [Meal]) {
        let ids = Set(offsets.compactMap { visibleMeals.indices.contains($0) ? visibleMeals[$0].id : nil })
        removeMeals(ids)
    }

    func deleteMeal(_ meal: Meal) {
        guard customMeals.contains(where: { $0.id == meal.id }) else { return }
        removeMeals([meal.id])
    }

    /// Marks meals deleted and re-plans only the days that used them.
    ///
    /// Deletion is a tombstone rather than a removal: once two devices compare libraries, a
    /// missing row is indistinguishable from one that was never there, which is how deleted
    /// meals reappear.
    private func removeMeals(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let now = Date.now
        for index in customMeals.indices where ids.contains(customMeals[index].id) {
            customMeals[index].deletedAt = now
            customMeals[index].updatedAt = now
            customMeals[index].updatedBy = DeviceIdentity.current
        }
        favoriteMealIDs.subtract(ids)
        let affected = Set(plan.meals.filter { $0.mealID.map(ids.contains) ?? false }.map(\.day))
        plan.meals.removeAll { $0.mealID.map(ids.contains) ?? false }
        regenerate(days: affected)
    }

    func renameHousehold(_ name: String) {
        household.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? L10n.string("My family") : name
    }

    func addHouseholdMember(named name: String, role: HouseholdRole = .adult) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        household.members.append(HouseholdMember(displayName: cleanName, role: role))
    }

    func removeHouseholdMembers(at offsets: IndexSet) {
        let removable = offsets
            .filter { household.members.indices.contains($0) }
            .filter { household.members[$0].role != .owner }
        for index in removable.sorted(by: >) { household.members.remove(at: index) }
    }

    /// How many people typically eat here. The single source of truth for servings.
    ///
    /// The member roster no longer writes this. It records who is in the family, which is a
    /// different question -- adding one child to the list used to silently reset dinner from
    /// six servings to two.
    func setHouseholdSize(_ size: Int) {
        let clamped = max(1, min(size, 20))
        guard clamped != householdSize else { return }
        householdSize = clamped
        rescalePlanServings()
    }

    /// Brings the current plan's servings, and so the grocery quantities, back in line with
    /// the household size. Days carrying an explicit per-day override keep it.
    private func rescalePlanServings() {
        guard !plan.meals.isEmpty else { return }
        var updated = plan
        for index in updated.meals.indices {
            let dayContext = context(for: updated.meals[index].day)
            switch updated.meals[index].kind {
            case .meal: updated.meals[index].servings = dayContext.cookedServings
            case .leftovers, .takeaway: updated.meals[index].servings = dayContext.diners
            case .away: updated.meals[index].servings = 0
            }
        }
        plan = updated
        reconcileGroceryChecks()
    }

    func handleIncomingURL(_ url: URL) {
        guard url.scheme == "mealshuffler", url.host == "join" else { return }
        let code = url.pathComponents.last?.uppercased() ?? ""
        guard !code.isEmpty else { return }
        inviteNotice = L10n.string(
            "Invite code %@ was received. It is ready to sync when an external household adapter is connected.",
            code
        )
    }

    func toggleGroceryItem(_ item: GroceryItem) {
        if checkedGroceryIDs.contains(item.id) { checkedGroceryIDs.remove(item.id) }
        else { checkedGroceryIDs.insert(item.id) }
    }

    func resetForPreview() {
        undoCheckpoint = nil
        hasCompletedOnboarding = false
        memberPreferences = [:]
        plan = .empty
        dayContexts = [:]
        checkedGroceryIDs = []
    }

    func explanation(for day: Weekday) -> String? {
        guard let item = plan[day] else { return nil }
        switch item.kind {
        case .away: return L10n.string("Nobody is home for dinner.")
        case .takeaway: return L10n.string("This day is set aside for takeaway.")
        case .leftovers(let source):
            return L10n.string("Leftovers from %@ reduce both work and food waste.", source.name.lowercased())
        case .meal: break
        }
        guard let mealID = item.mealID, let meal = meal(id: mealID) else { return nil }
        let matching = rules.filter { rule in
            guard rule.isEnabled else { return false }
            switch rule.constraint {
            case .requiredOn(let scope, let matcher):
                return scope.covers(day) && matcher.matches(meal, context: matchContext)
            case .maximumPrepTime(let scope, let minutes):
                return scope.covers(day) && meal.prepMinutes <= minutes
            case .requiredEvery(_, let matcher):
                return matcher.matches(meal, context: matchContext)
            default: return false
            }
        }
        if let rule = matching.first {
            return L10n.string(
                "Chosen because the rule “%@” applies on this day.",
                rule.summary(meals: meals, context: matchContext)
            )
        }
        if context(for: day).maximumPrepMinutes != nil {
            return L10n.string("Fits the time limit you set for %@.", day.name.lowercased())
        }
        return favoriteMealIDs.contains(meal.id)
            ? L10n.string("One of the family's favorites.")
            : L10n.string("Adds variety to the rest of the week.")
    }

    /// Everything a rule needs that does not live on the meal.
    ///
    /// Per-member dislikes have been stored since preferences became per-person; nothing read
    /// them until `.dislikedBy` gave a rule a way to ask.
    var matchContext: MealMatcher.MatchContext {
        var dislikes: [UUID: Set<UUID>] = [:]
        for (memberID, opinions) in memberPreferences {
            dislikes[memberID] = Set(opinions.filter { $0.value == .disliked }.map(\.key))
        }
        let names = Dictionary(
            household.members.map { ($0.id, $0.displayName) },
            uniquingKeysWith: { first, _ in first }
        )
        return MealMatcher.MatchContext(dislikes: dislikes, memberNames: names)
    }

    /// Whole weeks since each meal was last on a plan, read from the archive.
    ///
    /// What `noRepeatWithin` and `requiredEvery` measure against. The archive holds 26 weeks,
    /// which is further back than any sensible rule reaches.
    var weeksSinceLastPlanned: [UUID: Int] {
        let calendar = Calendar.current
        let thisWeek = WeekAnchor.startOfWeek(containing: .now, calendar: calendar)
        var result: [UUID: Int] = [:]
        for archived in archivedWeeks {
            let weeks = calendar
                .dateComponents([.weekOfYear], from: archived.startDate, to: thisWeek).weekOfYear ?? 0
            guard weeks > 0 else { continue }
            for item in archived.plan.meals where item.kind == .meal {
                guard let id = item.mealID else { continue }
                if let existing = result[id], existing <= weeks { continue }
                result[id] = weeks
            }
        }
        return result
    }

    /// Every custom label in use across the library, for the rule builder to offer.
    var customTagsInUse: [String] {
        Array(Set(meals.flatMap(\.customTags))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// The per-day plan, with any dinner-mode rule applied over the top.
    ///
    /// A rule is the household's standing statement -- "we eat out on Fridays" -- so it wins
    /// over the day's stored defaults. "Plan this day" still owns how many are eating, the
    /// extra servings and the time limit.
    private var resolvedContexts: [Weekday: DayPlanContext] {
        var contexts = Dictionary(uniqueKeysWithValues: Weekday.allCases.map { ($0, context(for: $0)) })
        for rule in rules where rule.isEnabled {
            guard case .dinnerMode(let scope, let mode) = rule.constraint else { continue }
            for day in scope.days() {
                contexts[day]?.mode = mode
                if mode != .leftovers { contexts[day]?.leftoverSourceDay = nil }
            }
        }
        return contexts
    }

    /// The dinner-mode rule governing a day, if one does. Views show it so a household can
    /// see why "Plan this day" will not stick.
    func dinnerModeRule(for day: Weekday) -> PlanningRule? {
        rules.first { rule in
            guard rule.isEnabled, case .dinnerMode(let scope, _) = rule.constraint else { return false }
            return scope.covers(day)
        }
    }

    private func refreshConflicts() {
        guard !plan.meals.isEmpty else { return }
        let result = generator.generate(
            preferredMeals: preferredMeals,
            allMeals: meals,
            rules: rules,
            contexts: resolvedContexts,
            taste: taste,
            existingPlan: WeeklyPlan(meals: plan.meals.map { item in var copy = item; copy.isLocked = true; return copy }),
            matchContext: matchContext
        )
        conflicts = result.conflicts
    }

    private func apply(_ result: GenerationResult) {
        // The generator solves rules; it does not own the calendar. Keep the week's anchor.
        plan = result.plan.anchored(to: plan.startDate)
        conflicts = result.conflicts
        reconcileGroceryChecks()
    }

    /// Keeps ticks for items that are still on the list and drops the rest. Wiping the whole
    /// set on every plan change discarded a shopper's progress mid-aisle for edits — a day
    /// swap, a single-day reshuffle — that often leave the list almost unchanged.
    private func reconcileGroceryChecks() {
        guard !checkedGroceryIDs.isEmpty else { return }
        // Built from the unfiltered list: an item set aside as already owned is still a
        // real item, and its tick should not be discarded for being hidden.
        let liveIDs = Set(
            GroceryListBuilder.build(plan: plan, meals: meals, manualItems: manualGroceryItems)
                .map(\.id)
        )
        let reconciled = checkedGroceryIDs.intersection(liveIDs)
        if reconciled != checkedGroceryIDs { checkedGroceryIDs = reconciled }
    }

    /// Coalesces writes. Every published property triggers a save, and a save encodes the
    /// whole state, so a single shuffle used to write the entire blob several times over.
    private func save() {
        guard !isRestoring else { return }
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.writeState()
        }
    }

    /// Writes any debounced change straight away. Call before the app can be suspended,
    /// otherwise a change made in the last fraction of a second is lost.
    func flushPendingWrites() {
        pendingSave?.cancel()
        pendingSave = nil
        writeState()
    }

    private func writeState() {
        let snapshot = AppStateSnapshot(
            hasCompletedOnboarding: hasCompletedOnboarding,
            memberPreferences: memberPreferences,
            rules: rules,
            plan: plan,
            checkedGroceryIDs: checkedGroceryIDs,
            stockedGroceryIDs: stockedGroceryIDs,
            manualGroceryItems: manualGroceryItems,
            pantryStaples: pantryStaples,
            aisleOrder: aisleOrder,
            customMeals: customMeals,
            favoriteMealIDs: favoriteMealIDs,
            dayContexts: dayContexts,
            feedbackEvents: feedbackEvents,
            householdSize: householdSize,
            household: household,
            archivedWeeks: archivedWeeks,
            nextWeekPlan: nextWeekPlan,
            dinnerReminderEnabled: dinnerReminderEnabled,
            dinnerReminderHour: dinnerReminderHour,
            prepLeadReminderEnabled: prepLeadReminderEnabled,
            groceryReminderEnabled: groceryReminderEnabled,
            groceryReminderWeekday: groceryReminderWeekday,
            groceryReminderHour: groceryReminderHour
        )
        repository.save(snapshot)
        // After the write, never before: the widget reads the saved blob in another process.
        refreshBackgroundSurfaces()
    }
}
