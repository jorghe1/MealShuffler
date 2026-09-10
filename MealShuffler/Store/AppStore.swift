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
    @Published var persistenceError: String?
    @Published var actionNotice: String?
    @Published private(set) var isGenerating = false
    private var planningRevision = 0
    @Published var nextWeekConflicts: [PlanConflict] = []
    @Published var nextWeekContexts: [Weekday: DayPlanContext] = [:] { didSet { save() } }
    @Published var householdTools = HouseholdTools() { didSet { save() } }
    private var shoppingAmounts: [String: Double] = [:]
    private var reminderTask: Task<Void, Never>?

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
        let nextWeekPlan: WeeklyPlan?
        let nextWeekContexts: [Weekday: DayPlanContext]
        let freezer: [FreezerBatch]
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
    var deletedRecipes: [Meal] { customMeals.filter(\.isDeleted) }

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
            nextWeekContexts = state.nextWeekContexts
            householdTools = state.tools
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
        let memberIDs = Set(household.members.map(\.id))
        memberPreferences = memberPreferences.filter { memberIDs.contains($0.key) }
        rules.removeAll { rule in if case .dislikedBy(let id)? = rule.constraint.matcher { return !memberIDs.contains(id) }; return false }
        isRestoring = false
        persistenceError = repository.recoveryNotice
        shoppingAmounts = Dictionary(GroceryListBuilder.build(plan: shoppingPlan, meals: meals, manualItems: manualGroceryItems)
            .map { ($0.id, $0.quantity) }, uniquingKeysWith: +)
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
        householdTools.shoppingSessions[shoppingPeriodID] = ShoppingSession(checked: checkedGroceryIDs, stocked: stockedGroceryIDs, manual: manualGroceryItems, amounts: shoppingAmounts)
        let wasDefaultPeriod = householdTools.shoppingStart == nil || shoppingEnd < currentWeekStart
        if wasDefaultPeriod { householdTools.shoppingStart = nil; householdTools.shoppingEnd = nil }

        if !plan.meals.isEmpty {
            archivedWeeks = Array((archivedWeeks + [ArchivedWeek(plan: plan, recipes: meals)])
                .sorted { $0.startDate > $1.startDate }
                .prefix(AppStore.archiveLimit))
        }

        if let prepared = nextWeekPlan, prepared.startDate == currentWeekStart {
            dayContexts = nextWeekContexts
            nextWeekContexts = [:]
            plan = prepared
            nextWeekPlan = nil
        } else {
            nextWeekContexts = [:]
            nextWeekPlan = nil
            dayContexts = [:]
            plan = WeeklyPlan(startDate: currentWeekStart, meals: [])
            if hasCompletedOnboarding { shuffleAll() }
        }
        // A week that has already turned cannot be undone back into.
        undoCheckpoint = nil
        if wasDefaultPeriod {
            let session = householdTools.shoppingSessions[shoppingPeriodID] ?? ShoppingSession()
            checkedGroceryIDs = session.checked; stockedGroceryIDs = session.stocked; manualGroceryItems = session.manual
        }
        refreshConflicts()
    }

    // MARK: - Next week

    /// Builds a plan for the week after this one, without disturbing the current week.
    func planNextWeek() {
        rememberForUndo(L10n.string("Next week"))
        let start = WeekAnchor.startOfNextWeek(after: plan.startDate)
        let result = generator.generate(
            preferredMeals: preferredMeals,
            allMeals: meals,
            rules: rules,
            contexts: contexts(forWeek: start),
            taste: tasteForWeek(start),
            existingPlan: WeeklyPlan(startDate: start, meals: nextWeekPlan?.meals.filter(\.isLocked) ?? []),
            matchContext: matchContextForWeek(start)
        )
        nextWeekPlan = result.plan.anchored(to: start)
        nextWeekConflicts = result.conflicts
    }

    func discardNextWeek() {
        rememberForUndo(L10n.string("Discard next week"))
        nextWeekPlan = nil
        nextWeekContexts = [:]
        nextWeekConflicts = []
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
        case .cooked(let mealID, let day, let date):
            guard let date else { return }
            let plans = [plan] + (nextWeekPlan.map { [$0] } ?? []) + archivedWeeks.map(\.plan)
            guard let datedPlan = plans.first(where: { Calendar.current.isDate($0.date(for: day), inSameDayAs: date) && $0[day]?.mealID == mealID }) else { return }
            let archivedRecipe = archivedWeeks.first { Calendar.current.isDate($0.plan.date(for: day), inSameDayAs: date) }?.recipeSnapshots?.first { $0.id == mealID }
            guard let meal = datedPlan[day]?.freezerBatch?.recipe ?? archivedRecipe ?? meal(id: mealID) else { return }
            recordCooked(meal, on: day, date: date)
        case .somethingElse(let mealID, let day, let date):
            guard let date, Calendar.current.isDate(plan.date(for: day), inSameDayAs: date),
                  Calendar.current.isDateInToday(date), plan[day]?.mealID == mealID,
                  let meal = meal(id: mealID), !isCompleted(on: day) else { return }
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
            targetDinnerHour: householdTools.dinnerHour,
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
        hasher.combine(householdTools.dinnerHour)
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
        let previous = reminderTask
        reminderTask = Task {
            await previous?.value
            await service.reschedule(schedule)
        }
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
        GroceryListBuilder.build(plan: shoppingPlan, meals: meals, manualItems: manualGroceryItems)
            .filter { !stockedGroceryIDs.contains($0.id) && !isStaple($0) }
    }

    var shoppingStart: Date { householdTools.shoppingStart ?? plan.startDate }
    var shoppingEnd: Date { householdTools.shoppingEnd ?? Calendar.current.date(byAdding: .day, value: 6, to: plan.startDate)! }
    var shoppingPeriodID: String { "\(Int(shoppingStart.timeIntervalSince1970))-\(Int(shoppingEnd.timeIntervalSince1970))" }
    var shoppingPlan: WeeklyPlan {
        let plans = [plan] + (nextWeekPlan.map { [$0] } ?? []) + archivedWeeks.map(\.plan)
        let items = plans.flatMap { week in
            week.meals.filter {
                let date = week.date(for: $0.day)
                return date >= shoppingStart && date < Calendar.current.date(byAdding: .day, value: 1, to: shoppingEnd)!
            }
        }
        // A transient aggregation input; this is never saved as a calendar week.
        return WeeklyPlan(startDate: shoppingStart, meals: items)
    }

    func setShoppingPeriod(from start: Date, through end: Date) {
        householdTools.shoppingSessions[shoppingPeriodID] = ShoppingSession(checked: checkedGroceryIDs, stocked: stockedGroceryIDs, manual: manualGroceryItems, amounts: shoppingAmounts)
        householdTools.shoppingStart = Calendar.current.startOfDay(for: start)
        householdTools.shoppingEnd = Calendar.current.startOfDay(for: max(start, end))
        let session = householdTools.shoppingSessions[shoppingPeriodID] ?? ShoppingSession()
        checkedGroceryIDs = session.checked; stockedGroceryIDs = session.stocked; manualGroceryItems = session.manual
        shoppingAmounts = session.amounts ?? Dictionary(GroceryListBuilder.build(plan: shoppingPlan, meals: meals, manualItems: manualGroceryItems).map { ($0.id, $0.quantity) }, uniquingKeysWith: +)
        reconcileGroceryChecks()
    }

    func updateGroceryItem(_ item: ManualGroceryItem) {
        guard let index = manualGroceryItems.firstIndex(where: { $0.id == item.id }) else { return }
        manualGroceryItems[index] = item
        reconcileGroceryChecks()
    }

    func cookingKey(meal: Meal, day: Weekday, date: Date? = nil) -> String {
        "\(Int((date ?? plan.date(for: day)).timeIntervalSince1970))-\(meal.id)-\(meal.updatedAt.timeIntervalSince1970)"
    }

    func addFreezerBatch(_ meal: Meal, portions: Double, label: String) {
        guard portions > 0, portions.isFinite else { return }
        householdTools.freezer.append(FreezerBatch(recipe: meal, portions: portions, label: label))
        refreshConflicts()
    }

    func consumeFreezerBatch(_ id: UUID, portions: Double) {
        guard let index = householdTools.freezer.firstIndex(where: { $0.id == id }), portions > 0,
              householdTools.freezer[index].portions >= portions else { return }
        householdTools.freezer[index].portions -= portions
        householdTools.freezer.removeAll { $0.portions <= 0 }
        refreshConflicts()
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
        GroceryListBuilder.build(plan: shoppingPlan, meals: meals, manualItems: manualGroceryItems)
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
            previousWeekDinner: previousDinner(before: plan.startDate),
            freezerBatches: householdTools.freezer,
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
            let date = event.plannedDate ?? event.timestamp
            if let existing = latest[event.mealID], existing >= date { continue }
            latest[event.mealID] = date
        }
        return latest
    }

    var recentlyCookedMealIDs: Set<UUID> {
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .distantPast
        return Set(feedbackEvents.filter { $0.kind == .cooked && ($0.plannedDate ?? $0.timestamp) >= cutoff }.map(\.mealID))
    }

    func meal(id: UUID) -> Meal? {
        meals.first(where: { $0.id == id }) ?? householdTools.freezer.first(where: { $0.recipe.id == id })?.recipe
            ?? (plan.meals + (nextWeekPlan?.meals ?? [])).compactMap { $0.freezerBatch?.recipe }.first(where: { $0.id == id })
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

    func context(for day: Weekday, nextWeek: Bool = false) -> DayPlanContext {
        let start = nextWeek ? WeekAnchor.startOfNextWeek(after: plan.startDate) : plan.startDate
        return contexts(forWeek: start)[day] ?? DayPlanContext(diners: householdSize)
    }

    func updateNextWeekContext(_ context: DayPlanContext, for day: Weekday) {
        rememberForUndo(L10n.string("Next week"))
        nextWeekContexts[day] = context
        guard let next = nextWeekPlan else { planNextWeek(); return }
        let locks = Dictionary(uniqueKeysWithValues: next.meals.map { ($0.day, $0.isLocked) })
        var pinned = next
        for index in pinned.meals.indices { pinned.meals[index].isLocked = pinned.meals[index].day != day }
        let result = generator.generate(preferredMeals: preferredMeals, allMeals: meals, rules: rules,
            contexts: contexts(forWeek: next.startDate), taste: tasteForWeek(next.startDate), existingPlan: pinned,
            matchContext: matchContextForWeek(next.startDate))
        var updated = result.plan
        for index in updated.meals.indices { updated.meals[index].isLocked = locks[updated.meals[index].day] ?? false }
        nextWeekPlan = updated
        nextWeekConflicts = result.conflicts
    }

    func shuffleNextWeek(day: Weekday, intent: MealSwapIntent) {
        guard let original = nextWeekPlan else { return }
        let old = original[day]?.mealID.flatMap { meal(id: $0) }
        let pinned = WeeklyPlan(startDate: original.startDate, meals: original.meals.map { item in
            var copy = item; copy.isLocked = item.day != day; return copy
        })
        var result = generator.generate(preferredMeals: preferredMeals, allMeals: meals, rules: rules,
            contexts: contexts(forWeek: original.startDate), taste: tasteForWeek(original.startDate), existingPlan: pinned,
            avoidingMealOnDay: old.map { [day: $0.id] } ?? [:], swapIntents: [day: intent], matchContext: matchContextForWeek(original.startDate))
        if let old {
            guard let new = result.plan[day]?.mealID.flatMap({ meal(id: $0) }), new.id != old.id,
                  intent != .quicker || (new.prepMinutes > 0 && new.prepMinutes < old.prepMinutes),
                  intent != .cheaper || new.costPerServing < old.costPerServing,
                  intent != .favorite || favoriteMealIDs.contains(new.id) else {
                actionNotice = L10n.string("No replacement matched that request. Your dinner has been kept."); return
            }
        }
        rememberForUndo(L10n.string("Next week"))
        for index in result.plan.meals.indices { result.plan.meals[index].isLocked = original[result.plan.meals[index].day]?.isLocked ?? false }
        nextWeekPlan = result.plan; nextWeekConflicts = result.conflicts; refreshConflicts(); reconcileGroceryChecks()
    }

    func swapNextWeek(between firstDay: Weekday, and secondDay: Weekday) {
        guard var next = nextWeekPlan, var first = next[firstDay], var second = next[secondDay], first.kind == .meal, second.kind == .meal else {
            actionNotice = L10n.string("Only dinners still to cook can be swapped. Change other arrangements in the day settings."); return
        }
        rememberForUndo(L10n.string("Next week"))
        let firstID = first.mealID; first.mealID = second.mealID; second.mealID = firstID
        next[firstDay] = first; next[secondDay] = second; nextWeekPlan = next
        refreshConflicts(); reconcileGroceryChecks()
    }

    func setNextWeekMeal(_ meal: Meal, on day: Weekday) {
        rememberForUndo(L10n.string("Next week"))
        let start = WeekAnchor.startOfNextWeek(after: plan.startDate)
        var context = self.context(for: day, nextWeek: true)
        context.mode = .cook; context.overridesDinnerMode = true
        context.leftoverSourceDay = nil
        nextWeekContexts[day] = context
        var next = nextWeekPlan ?? WeeklyPlan(startDate: start, meals: [])
        next[day] = PlannedMeal(day: day, mealID: meal.id, isLocked: true, servings: context.cookedServings, portionScale: context.portionScale)
        nextWeekPlan = next
        refreshConflicts()
    }

    func toggleNextWeekLock(day: Weekday) {
        guard var next = nextWeekPlan, var item = next[day] else { return }
        item.isLocked.toggle(); next[day] = item; nextWeekPlan = next
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
        refreshConflicts()
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
        for (memberID, opinions) in memberPreferences where household.members.contains(where: { $0.id == memberID }) {
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
            nextWeekPlan: nextWeekPlan,
            nextWeekContexts: nextWeekContexts,
            freezer: householdTools.freezer,
            label: label
        )
    }

    func undoLastChange() {
        guard let restore = undoCheckpoint else { return }
        undoCheckpoint = nil
        dayContexts = restore.contexts
        feedbackEvents = restore.feedbackEvents
        plan = restore.plan
        nextWeekPlan = restore.nextWeekPlan
        nextWeekContexts = restore.nextWeekContexts
        householdTools.freezer = restore.freezer
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
        guard !isCompleted(on: day) else { actionNotice = L10n.string("Mark this dinner as not cooked before replacing it."); return }
        rememberForUndo(L10n.string("Dinner on %@", day.name.lowercased()))

        var context = context(for: day)
        // Choosing a dinner for a day nobody was eating at home means eating at home again.
        if context.mode != .cook {
            context.mode = .cook
            context.overridesDinnerMode = true
            context.leftoverSourceDay = nil
            dayContexts[day] = context
        }

        var item = plan[day] ?? PlannedMeal(day: day, mealID: nil, isLocked: false)
        item.mealID = meal.id
        item.kind = .meal
        item.freezerBatch = nil; item.freezerConsumed = nil
        item.servings = context.cookedServings
        item.portionScale = context.portionScale
        item.isLocked = true
        plan[day] = item

        refreshConflicts()
        reconcileGroceryChecks()
    }

    func generateInBackground(nextWeek: Bool = false) async {
        guard !isGenerating else { return }
        isGenerating = true
        defer { isGenerating = false }
        let revision = planningRevision
        let start = nextWeek ? WeekAnchor.startOfNextWeek(after: plan.startDate) : plan.startDate
        let original = nextWeek ? (nextWeekPlan ?? WeeklyPlan(startDate: start, meals: [])) : plan
        let pinned = original.meals.filter { item in
            item.isLocked || (!nextWeek && (isCompleted(on: item.day) || (hasCompletedOnboarding && plan.date(for: item.day) < Calendar.current.startOfDay(for: .now))))
        }.map { item in var copy = item; copy.isLocked = true; return copy }
        let preferred = preferredMeals; let library = meals; let constraints = rules
        let contexts = contexts(forWeek: start); let profile = tasteForWeek(start); let match = matchContextForWeek(start)
        let worker = Task.detached(priority: .userInitiated) {
            MealPlanGenerator().generate(preferredMeals: preferred, allMeals: library, rules: constraints,
                contexts: contexts, taste: profile, existingPlan: WeeklyPlan(startDate: start, meals: pinned), matchContext: match)
        }
        let result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
        guard !Task.isCancelled, revision == planningRevision else { return }
        rememberForUndo(nextWeek ? L10n.string("Next week") : L10n.string("Shuffle week"))
        var updated = result
        for index in updated.plan.meals.indices { updated.plan.meals[index].isLocked = original[updated.plan.meals[index].day]?.isLocked ?? false }
        if nextWeek { nextWeekPlan = updated.plan; nextWeekConflicts = updated.conflicts; refreshConflicts() }
        else { apply(updated) }
    }

    /// Re-rolls every unlocked day. This is the explicit "shuffle the week" action.
    func shuffleAll(now: Date = .now) {
        rememberForUndo(L10n.string("Shuffle week"))
        let result = generator.generate(
            preferredMeals: preferredMeals,
            allMeals: meals,
            rules: rules,
            contexts: resolvedContexts,
            taste: taste,
            existingPlan: WeeklyPlan(startDate: plan.startDate, meals: plan.meals.filter {
                $0.isLocked || isCompleted(on: $0.day) || (hasCompletedOnboarding && plan.date(for: $0.day) < Calendar.current.startOfDay(for: now))
            }.map { item in var copy = item; copy.isLocked = true; return copy }),
            matchContext: matchContext
        )
        var updated = result
        for index in updated.plan.meals.indices {
            let day = updated.plan.meals[index].day
            updated.plan.meals[index].isLocked = plan[day]?.isLocked ?? false
        }
        apply(updated)
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
        let pinned = WeeklyPlan(startDate: plan.startDate, meals: plan.meals.map { item in
            var copy = item
            let isTarget = days.contains(item.day)
            copy.isLocked = respectingLocks ? (item.isLocked || !isTarget || isCompleted(on: item.day) || (hasCompletedOnboarding && plan.date(for: item.day) < Calendar.current.startOfDay(for: .now))) : !isTarget
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
        refreshConflicts()
        reconcileGroceryChecks()
    }

    func shuffle(day: Weekday, intent: MealSwapIntent = .different) {
        guard !isCompleted(on: day) else { actionNotice = L10n.string("Mark this dinner as not cooked before replacing it."); return }
        let previous = plan[day]?.mealID.flatMap { meal(id: $0) }
        rememberForUndo(L10n.string("Dinner on %@", day.name.lowercased()))
        let currentID = plan[day]?.mealID
        regenerate(
            days: [day],
            respectingLocks: false,
            intents: [day: intent],
            avoiding: currentID.map { [day: $0] } ?? [:]
        )
        if previous != nil, plan[day]?.mealID == nil { undoLastChange(); actionNotice = L10n.string("No replacement matched that request. Your dinner has been kept."); return }
        if let previous, let replacement = plan[day]?.mealID.flatMap({ meal(id: $0) }) {
            let achieved: Bool
            switch intent {
            case .quicker: achieved = replacement.prepMinutes > 0 && replacement.prepMinutes < previous.prepMinutes
            case .cheaper: achieved = replacement.costPerServing < previous.costPerServing
            case .favorite: achieved = favoriteMealIDs.contains(replacement.id)
            default: achieved = replacement.id != previous.id
            }
            if !achieved { undoLastChange(); actionNotice = L10n.string("No replacement matched that request. Your dinner has been kept.") }
        }
    }

    func toggleLock(day: Weekday) {
        guard var item = plan[day] else { return }
        item.isLocked.toggle()
        plan[day] = item
    }

    func updateContext(_ context: DayPlanContext, for day: Weekday) {
        guard !isCompleted(on: day) else { actionNotice = L10n.string("Mark this dinner as not cooked before replacing it."); return }
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
        guard first.kind == .meal, second.kind == .meal, !isCompleted(on: firstDay), !isCompleted(on: secondDay) else {
            actionNotice = L10n.string("Only dinners still to cook can be swapped. Change other arrangements in the day settings."); return
        }
        rememberForUndo(L10n.string("Swap of two days"))
        let firstPayload = (first.mealID, first.kind)
        first.mealID = second.mealID
        first.kind = second.kind
        first.servings = context(for: firstDay).cookedServings
        first.portionScale = context(for: firstDay).portionScale
        first.isLocked = false
        second.mealID = firstPayload.0
        second.kind = firstPayload.1
        second.servings = context(for: secondDay).cookedServings
        second.portionScale = context(for: secondDay).portionScale
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
        rules[index].strength = rules[index].supportsPreference ? strength : .required
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
    func addRule(_ rule: PlanningRule, replacingID: UUID? = nil) -> RuleAdditionOutcome {
        if let existing = rules.first(where: {
            $0.id != replacingID && $0.isEnabled && $0.hasSameSchedule(as: rule) && $0.constraint.saysTheSameAs(rule.constraint)
        }) {
            return .duplicate(existingTitle: existing.summary(meals: meals, context: matchContext))
        }
        if let existing = rules.first(where: {
            $0.id != replacingID && $0.isEnabled && $0.strength == .required && rule.strength == .required
                && ($0.repeatEveryWeeks ?? 1) == 1 && (rule.repeatEveryWeeks ?? 1) == 1
                && $0.constraint.contradicts(rule.constraint)
        }) {
            return .contradiction(existingTitle: existing.summary(meals: meals, context: matchContext))
        }
        let previous = rules.first { $0.id == replacingID }
        if let index = rules.firstIndex(where: { $0.id == replacingID }) { rules[index] = rule }
        else { rules.append(rule) }
        regenerate(days: rule.constraint.affectedDays.union(previous?.constraint.affectedDays ?? []))
        return .added
    }

    func resetRecipeToOriginal(_ meal: Meal) {
        guard SampleMeals.all.contains(where: { $0.id == meal.id }) else { return }
        customMeals.removeAll { $0.id == meal.id }
        refreshConflicts()
        reconcileGroceryChecks()
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
        guard plan[day]?.mealID == meal.id else { return }
        recordCooked(plan[day]?.freezerBatch?.recipe ?? meal, on: day, date: plan.date(for: day))
    }

    private func recordCooked(_ meal: Meal, on day: Weekday, date: Date) {
        guard !feedbackEvents.contains(where: { $0.kind == .cooked && $0.mealID == meal.id && $0.plannedDate.map { Calendar.current.isDate($0, inSameDayAs: date) } == true }) else { return }
        rememberForUndo(L10n.string("Cooked"))
        if Calendar.current.isDate(date, inSameDayAs: plan.date(for: day)), var item = plan[day], let batch = item.freezerBatch, item.freezerConsumed != true {
            guard householdTools.freezer.first(where: { $0.id == batch.id }).map({ $0.portions >= item.effectiveServings }) == true else {
                actionNotice = L10n.string("Not enough freezer portions for %@.", day.name); return
            }
            item.freezerConsumed = true; plan[day] = item
            consumeFreezerBatch(batch.id, portions: item.effectiveServings)
        }
        appendFeedback(MealFeedbackEvent(mealID: meal.id, kind: .cooked, weekday: day, plannedDate: date, recipeSnapshot: meal))
        actionNotice = L10n.string("Dinner marked as cooked.")
    }

    func isCompleted(on day: Weekday) -> Bool {
        feedbackEvents.contains { $0.kind == .cooked && $0.plannedDate.map { Calendar.current.isDate($0, inSameDayAs: plan.date(for: day)) } == true }
    }

    func clearCompletion(on day: Weekday) {
        rememberForUndo(L10n.string("Cooked"))
        if var item = plan[day], let batch = item.freezerBatch, item.freezerConsumed == true {
            if let index = householdTools.freezer.firstIndex(where: { $0.id == batch.id }) { householdTools.freezer[index].portions += item.effectiveServings }
            else { var restored = batch; restored.portions = item.effectiveServings; householdTools.freezer.append(restored) }
            item.freezerConsumed = false; plan[day] = item
        }
        feedbackEvents.removeAll { $0.kind == .cooked && $0.plannedDate.map { Calendar.current.isDate($0, inSameDayAs: plan.date(for: day)) } == true }
        refreshConflicts()
    }

    var remainingDinnerCount: Int {
        plan.meals.filter { !$0.isLocked && !isCompleted(on: $0.day) && plan.date(for: $0.day) >= Calendar.current.startOfDay(for: .now) && $0.kind == .meal }.count
    }

    func markSkipped(_ meal: Meal, on day: Weekday) {
        guard !isCompleted(on: day) else { return }
        rememberForUndo(L10n.string("Replacing %@", meal.name))
        appendFeedback(MealFeedbackEvent(mealID: meal.id, kind: .skipped, weekday: day, plannedDate: plan.date(for: day), recipeSnapshot: meal))
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

    @discardableResult
    func saveMeal(_ meal: Meal) -> Bool {
        let previous = customMeals
        do {
            if let old = meals.first(where: { $0.id == meal.id }) { try RecipeLibraryStorage.retainRevision(old) }
        } catch { persistenceError = error.localizedDescription; return false }
        let stamped = meal.touched()
        if let index = customMeals.firstIndex(where: { $0.id == meal.id }) {
            customMeals[index] = stamped
        } else {
            customMeals.append(stamped)
        }
        pendingSave?.cancel()
        guard writeState() else { customMeals = previous; pendingSave?.cancel(); return false }
        refreshConflicts()
        reconcileGroceryChecks()
        return true
    }

    @discardableResult
    func mergeRecipes(_ imported: [Meal]) -> Bool {
        let previous = customMeals
        do {
            for meal in imported {
                if let old = meals.first(where: { $0.id == meal.id }) { try RecipeLibraryStorage.retainRevision(old) }
            }
            let ids = Set(imported.map(\.id))
            customMeals = customMeals.filter { !ids.contains($0.id) } + imported.map { $0.touched() }
            pendingSave?.cancel()
            guard writeState() else { customMeals = previous; pendingSave?.cancel(); return false }
            refreshConflicts()
            return true
        } catch { persistenceError = error.localizedDescription; return false }
    }

    func deleteCustomMeals(at offsets: IndexSet, from visibleMeals: [Meal]) {
        let ids = Set(offsets.compactMap { visibleMeals.indices.contains($0) ? visibleMeals[$0].id : nil })
        removeMeals(ids)
    }

    func deleteMeal(_ meal: Meal) {
        if !customMeals.contains(where: { $0.id == meal.id }) { customMeals.append(meal) }
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
        if var next = nextWeekPlan {
            for index in next.meals.indices where next.meals[index].mealID.map(ids.contains) ?? false {
                next.meals[index].mealID = nil
                next.meals[index].isLocked = false
            }
            nextWeekPlan = next
        }
        regenerate(days: affected)
        refreshConflicts()
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
        let ids = Set(removable.map { household.members[$0].id })
        for id in ids { memberPreferences.removeValue(forKey: id) }
        rules.removeAll { rule in
            if case .dislikedBy(let memberID)? = rule.constraint.matcher { return ids.contains(memberID) }
            return false
        }
        for day in Weekday.allCases {
            dayContexts[day]?.attendingMemberIDs?.subtract(ids)
            nextWeekContexts[day]?.attendingMemberIDs?.subtract(ids)
        }
        for index in removable.sorted(by: >) { household.members.remove(at: index) }
        refreshConflicts()
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
        var updated = plan
        for index in updated.meals.indices {
            let dayContext = context(for: updated.meals[index].day)
            updated.meals[index].portionScale = dayContext.portionScale
            switch updated.meals[index].kind {
            case .meal: updated.meals[index].servings = dayContext.cookedServings
            case .leftovers, .takeaway: updated.meals[index].servings = dayContext.diners
            case .away: updated.meals[index].servings = 0
            }
        }
        plan = updated
        if var next = nextWeekPlan {
            for index in next.meals.indices {
                let context = self.context(for: next.meals[index].day, nextWeek: true)
                next.meals[index].portionScale = context.portionScale
                switch next.meals[index].kind {
                case .meal: next.meals[index].servings = context.cookedServings
                case .leftovers, .takeaway: next.meals[index].servings = context.diners
                case .away: next.meals[index].servings = 0
                }
            }
            nextWeekPlan = next
        }
        refreshConflicts()
        reconcileGroceryChecks()
    }

    func handleIncomingURL(_ url: URL) {
        guard url.scheme == "mealshuffler", url.host == "join" else { return }
        let code = url.pathComponents.last?.uppercased() ?? ""
        guard !code.isEmpty else { return }
        inviteNotice = L10n.string(
            "Invitation code %@ is no longer supported. Ask the household owner for an iCloud invitation.",
            code
        )
    }

    func toggleGroceryItem(_ item: GroceryItem) {
        shoppingAmounts[item.id] = item.quantity
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
            guard rule.isActive(inWeek: plan.startDate) else { return false }
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
        return MealMatcher.MatchContext(dislikes: dislikes, memberNames: names,
            attendance: dayContexts.compactMapValues(\.attendingMemberIDs))
    }

    private func matchContextForWeek(_ start: Date) -> MealMatcher.MatchContext {
        var result = matchContext
        result.attendance = contexts(forWeek: start).compactMapValues(\.attendingMemberIDs)
        return result
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
        contexts(forWeek: plan.startDate)
    }

    private func contexts(forWeek start: Date) -> [Weekday: DayPlanContext] {
        let stored = start == plan.startDate ? dayContexts : nextWeekContexts
        var contexts = Dictionary(uniqueKeysWithValues: Weekday.allCases.map { ($0, stored[$0] ?? DayPlanContext(diners: householdSize)) })
        for rule in rules where rule.isActive(inWeek: start) && rule.strength == .required {
            guard case .dinnerMode(let scope, let mode) = rule.constraint else { continue }
            for day in scope.days() where contexts[day]?.overridesDinnerMode != true {
                contexts[day]?.mode = mode
                if mode != .leftovers { contexts[day]?.leftoverSourceDay = nil }
            }
        }
        return contexts
    }

    /// The dinner-mode rule governing a day, if one does. Views show it so a household can
    /// see why "Plan this day" will not stick.
    func dinnerModeRule(for day: Weekday, nextWeek: Bool = false) -> PlanningRule? {
        let start = nextWeek ? WeekAnchor.startOfNextWeek(after: plan.startDate) : plan.startDate
        return rules.first { rule in
            guard rule.isActive(inWeek: start), rule.strength == .required, case .dinnerMode(let scope, _) = rule.constraint else { return false }
            return scope.covers(day)
        }
    }

    private func refreshConflicts() {
        let linked = generator.resolvingLeftovers(in: plan, contexts: resolvedContexts, allMeals: meals, rules: rules, matchContext: matchContext)
        if linked != plan { plan = linked }
        let preferred = Set(preferredMeals.map(\.id))
        let outside = plan.meals.filter { $0.kind == .meal }.compactMap { item -> String? in
            guard let id = item.mealID, !preferred.contains(id) else { return nil }; return meal(id: id)?.name
        }
        let notes = outside.isEmpty ? [] : [PlanConflict(message: L10n.string("To satisfy your rules we also used: %@.", Array(Set(outside)).sorted().joined(separator: ", ")),
            suggestion: L10n.string("Add more meals in these categories to get more choice."), severity: .informational)]
        conflicts = generator.validate(plan: plan, allMeals: meals, rules: rules, contexts: resolvedContexts,
                                       taste: taste, context: matchContext) + notes
        if let next = nextWeekPlan {
            let linkedNext = generator.resolvingLeftovers(in: next, contexts: contexts(forWeek: next.startDate), allMeals: meals, rules: rules, matchContext: matchContextForWeek(next.startDate))
            if linkedNext != next { nextWeekPlan = linkedNext }
            nextWeekConflicts = generator.validate(plan: linkedNext, allMeals: meals, rules: rules, contexts: contexts(forWeek: next.startDate),
                                                   taste: tasteForWeek(next.startDate), context: matchContextForWeek(next.startDate))
        } else { nextWeekConflicts = [] }
    }

    private func previousDinner(before start: Date) -> Meal? {
        guard let date = Calendar.current.date(byAdding: .day, value: -1, to: start) else { return nil }
        let weeks = [ArchivedWeek(plan: plan, recipes: meals)] + archivedWeeks
        for archive in weeks {
            guard let item = archive.plan.meals.first(where: { Calendar.current.isDate(archive.plan.date(for: $0.day), inSameDayAs: date) }), item.kind == .meal,
                  let id = item.mealID else { continue }
            return archive.recipeSnapshots?.first { $0.id == id } ?? meal(id: id)
        }
        return nil
    }

    private func tasteForWeek(_ start: Date) -> TasteProfile {
        var result = taste
        result.previousWeekDinner = previousDinner(before: start)
        let calendar = Calendar.current
        let weeksAhead = calendar.dateComponents([.weekOfYear], from: plan.startDate, to: start).weekOfYear ?? 0
        result.weeksSinceLastPlanned = result.weeksSinceLastPlanned.mapValues { $0 + weeksAhead }
        if weeksAhead > 0 {
            for item in plan.meals where item.freezerConsumed != true {
                if let batch = item.freezerBatch, let index = result.freezerBatches.firstIndex(where: { $0.id == batch.id }) { result.freezerBatches[index].portions -= item.effectiveServings }
            }
            for item in plan.meals where item.kind == .meal {
                if let id = item.mealID { result.weeksSinceLastPlanned[id] = weeksAhead }
            }
        }
        return result
    }

    private func apply(_ result: GenerationResult) {
        // The generator solves rules; it does not own the calendar. Keep the week's anchor.
        plan = result.plan.anchored(to: plan.startDate)
        conflicts = result.conflicts
        refreshConflicts()
        reconcileGroceryChecks()
    }

    /// Keeps ticks for items that are still on the list and drops the rest. Wiping the whole
    /// set on every plan change discarded a shopper's progress mid-aisle for edits — a day
    /// swap, a single-day reshuffle — that often leave the list almost unchanged.
    private func reconcileGroceryChecks() {
        // Built from the unfiltered list: an item set aside as already owned is still a
        // real item, and its tick should not be discarded for being hidden.
        let amounts = Dictionary(GroceryListBuilder.build(plan: shoppingPlan, meals: meals, manualItems: manualGroceryItems)
            .map { ($0.id, $0.quantity) }, uniquingKeysWith: +)
        let liveIDs = Set(amounts.keys.filter { amounts[$0, default: 0] <= shoppingAmounts[$0, default: 0] })
        let reconciled = checkedGroceryIDs.intersection(liveIDs)
        if reconciled != checkedGroceryIDs { checkedGroceryIDs = reconciled }
        let stocked = stockedGroceryIDs.intersection(liveIDs)
        if stocked != stockedGroceryIDs { stockedGroceryIDs = stocked }
        shoppingAmounts = amounts
    }

    /// Coalesces writes. Every published property triggers a save, and a save encodes the
    /// whole state, so a single shuffle used to write the entire blob several times over.
    private func save() {
        guard !isRestoring else { return }
        planningRevision += 1
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

    func makeSnapshot() -> AppStateSnapshot {
        var snapshot = AppStateSnapshot(
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
        snapshot.nextWeekContexts = nextWeekContexts
        snapshot.tools = householdTools
        return snapshot
    }

    func restoreSnapshot(_ state: AppStateSnapshot, sharedOnly: Bool = false) throws {
        try state.validateStructure()
        guard (1...20).contains(state.householdSize), state.customMeals.count <= 2000,
              state.plan.meals.count <= 7, Set(state.plan.meals.map(\.day)).count == state.plan.meals.count,
              state.nextWeekPlan.map({ $0.meals.count <= 7 && Set($0.meals.map(\.day)).count == $0.meals.count }) ?? true else { throw CocoaError(.fileReadCorruptFile) }
        let previous = makeSnapshot()
        let previousAmounts = shoppingAmounts
        let previousUndo = undoCheckpoint
        pendingSave?.cancel()
        isRestoring = true
        defer { isRestoring = false }
        func applyFields(_ state: AppStateSnapshot) {
        hasCompletedOnboarding = state.hasCompletedOnboarding
        memberPreferences = state.memberPreferences; rules = state.rules; plan = state.plan
        checkedGroceryIDs = state.checkedGroceryIDs; stockedGroceryIDs = state.stockedGroceryIDs
        manualGroceryItems = state.manualGroceryItems; pantryStaples = state.pantryStaples
        aisleOrder = Self.completeAisleOrder(state.aisleOrder); customMeals = state.customMeals
        favoriteMealIDs = state.favoriteMealIDs; dayContexts = state.dayContexts
        feedbackEvents = state.feedbackEvents; householdSize = state.householdSize; household = state.household
        archivedWeeks = state.archivedWeeks; nextWeekPlan = state.nextWeekPlan; nextWeekContexts = state.nextWeekContexts
        let localCooking = householdTools.cooking
        householdTools = state.tools
        if sharedOnly { householdTools.cooking = localCooking }
        else {
            dinnerReminderEnabled = state.dinnerReminderEnabled; dinnerReminderHour = state.dinnerReminderHour
            prepLeadReminderEnabled = state.prepLeadReminderEnabled; groceryReminderEnabled = state.groceryReminderEnabled
            groceryReminderWeekday = state.groceryReminderWeekday; groceryReminderHour = state.groceryReminderHour
        }
        }
        applyFields(state)
        undoCheckpoint = nil
        shoppingAmounts = Dictionary(GroceryListBuilder.build(plan: shoppingPlan, meals: meals, manualItems: manualGroceryItems).map { ($0.id, $0.quantity) }, uniquingKeysWith: +)
        refreshConflicts()
        do { try repository.saveOrThrow(makeSnapshot()) }
        catch {
            applyFields(previous)
            shoppingAmounts = previousAmounts
            undoCheckpoint = previousUndo
            refreshConflicts()
            throw error
        }
        refreshPendingCaptures(); refreshBackgroundSurfaces(force: true)
    }

    @discardableResult
    private func writeState() -> Bool {
        let previousChecks = checkedGroceryIDs
        let previousStock = stockedGroceryIDs
        let previousAmounts = shoppingAmounts
        reconcileGroceryChecks()
        let snapshot = makeSnapshot()
        do { try repository.saveOrThrow(snapshot) }
        catch {
            checkedGroceryIDs = previousChecks
            stockedGroceryIDs = previousStock
            shoppingAmounts = previousAmounts
            pendingSave?.cancel()
            persistenceError = error.localizedDescription
            return false
        }
        persistenceError = nil
        // After the write, never before: the widget reads the saved blob in another process.
        refreshBackgroundSurfaces()
        return true
    }
}
