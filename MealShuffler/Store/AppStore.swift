import Combine
import Foundation

enum MealFeedbackKind: String, Codable {
    case snoozed, cooked, skipped
}

struct MealFeedbackEvent: Identifiable, Codable, Hashable {
    let id: UUID
    let mealID: UUID
    let kind: MealFeedbackKind
    let timestamp: Date
    let weekday: Weekday?

    init(id: UUID = UUID(), mealID: UUID, kind: MealFeedbackKind, timestamp: Date = .now, weekday: Weekday? = nil) {
        self.id = id
        self.mealID = mealID
        self.kind = kind
        self.timestamp = timestamp
        self.weekday = weekday
    }
}

@MainActor
final class AppStore: ObservableObject {
    @Published var hasCompletedOnboarding: Bool { didSet { save() } }
    @Published var preferences: [UUID: MealPreference] { didSet { save() } }
    @Published var rules: [PlanningRule] { didSet { save() } }
    @Published var plan: WeeklyPlan { didSet { save() } }
    @Published var conflicts: [PlanConflict] = []
    @Published var checkedGroceryIDs: Set<String> { didSet { save() } }
    @Published var customMeals: [Meal] { didSet { save() } }
    @Published var favoriteMealIDs: Set<UUID> { didSet { save() } }
    @Published var dayContexts: [Weekday: DayPlanContext] { didSet { save() } }
    @Published var feedbackEvents: [MealFeedbackEvent] { didSet { save() } }
    @Published var householdSize: Int { didSet { save() } }
    @Published var household: Household { didSet { save() } }
    @Published var inviteNotice: String?

    private let generator: MealPlanGenerator
    private let persistenceKey = "meal-shuffler-state-v1"
    private var isRestoring = true
    private let defaults: UserDefaults
    private var pendingSave: Task<Void, Never>?
    private static let feedbackRetentionDays = 400
    private static let feedbackEventLimit = 2_000

    var meals: [Meal] { SampleMeals.all + customMeals }

    init(defaults: UserDefaults = .standard, random: RandomSource = SystemRandomSource()) {
        self.defaults = defaults
        generator = MealPlanGenerator(random: random)
        if let data = defaults.data(forKey: persistenceKey),
           let state = try? JSONDecoder().decode(PersistedState.self, from: data) {
            hasCompletedOnboarding = state.hasCompletedOnboarding
            preferences = state.preferences
            rules = state.rules
            plan = state.plan
            checkedGroceryIDs = state.checkedGroceryIDs
            customMeals = state.customMeals
            favoriteMealIDs = state.favoriteMealIDs
            dayContexts = state.dayContexts
            feedbackEvents = AppStore.prunedFeedback(state.feedbackEvents)
            householdSize = state.householdSize
            household = state.household
        } else {
            hasCompletedOnboarding = false
            preferences = [:]
            rules = PlanningRule.starterRules(meals: SampleMeals.all)
            plan = .empty
            checkedGroceryIDs = []
            customMeals = []
            favoriteMealIDs = []
            dayContexts = [:]
            feedbackEvents = []
            householdSize = 4
            household = Household()
        }
        isRestoring = false
        inviteNotice = nil
        refreshConflicts()
    }

    var preferredMeals: [Meal] {
        let snoozed = activeSnoozedMealIDs
        let accepted = meals.filter {
            preferences[$0.id] != .disliked && !snoozed.contains($0.id)
        }
        return accepted.isEmpty ? meals : accepted
    }

    var groceryItems: [GroceryItem] {
        GroceryListBuilder.build(plan: plan, meals: meals)
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
            recentlyCookedMealIDs: recentlyCookedMealIDs
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

    var recentlyCookedMealIDs: Set<UUID> {
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .distantPast
        return Set(feedbackEvents.filter { $0.kind == .cooked && $0.timestamp >= cutoff }.map(\.mealID))
    }

    func meal(id: UUID) -> Meal? {
        meals.first(where: { $0.id == id })
    }

    func context(for day: Weekday) -> DayPlanContext {
        dayContexts[day] ?? DayPlanContext(diners: householdSize)
    }

    func setPreference(_ preference: MealPreference, for meal: Meal) {
        preferences[meal.id] = preference
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        shuffleAll()
    }

    /// Re-rolls every unlocked day. This is the explicit "shuffle the week" action.
    func shuffleAll() {
        let result = generator.generate(
            preferredMeals: preferredMeals,
            allMeals: meals,
            rules: rules,
            contexts: resolvedContexts,
            taste: taste,
            existingPlan: WeeklyPlan(meals: plan.meals.filter(\.isLocked))
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
            swapIntents: intents
        )
        var updated = result.plan
        for index in updated.meals.indices {
            updated.meals[index].isLocked = userLocks[updated.meals[index].day] ?? false
        }
        plan = updated
        conflicts = result.conflicts
        reconcileGroceryChecks()
    }

    func shuffle(day: Weekday, intent: MealSwapIntent = .different) {
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
        rules[index].isEnabled.toggle()
        regenerate(days: rules[index].constraint.affectedDays)
    }

    func setRuleStrength(_ strength: RuleStrength, ruleID: UUID) {
        guard let index = rules.firstIndex(where: { $0.id == ruleID }) else { return }
        rules[index].strength = strength
        regenerate(days: rules[index].constraint.affectedDays)
    }

    func addRule(_ rule: PlanningRule) {
        rules.append(rule)
        regenerate(days: rule.constraint.affectedDays)
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
        appendFeedback(MealFeedbackEvent(mealID: meal.id, kind: .snoozed, weekday: day))
        shuffle(day: day, intent: .different)
    }

    func markCooked(_ meal: Meal, on day: Weekday) {
        appendFeedback(MealFeedbackEvent(mealID: meal.id, kind: .cooked, weekday: day))
    }

    func markSkipped(_ meal: Meal, on day: Weekday) {
        appendFeedback(MealFeedbackEvent(mealID: meal.id, kind: .skipped, weekday: day))
        shuffle(day: day, intent: .different)
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
        if let index = customMeals.firstIndex(where: { $0.id == meal.id }) {
            customMeals[index] = meal
        } else {
            customMeals.append(meal)
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

    /// Only the days that actually used a removed meal need a new dinner.
    private func removeMeals(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        customMeals.removeAll { ids.contains($0.id) }
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
        hasCompletedOnboarding = false
        preferences = [:]
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
            case .requiredOn(let ruleDay, let matcher): return ruleDay == day && matcher.matches(meal)
            case .maximumPrepTime(let ruleDay, let minutes): return ruleDay == day && meal.prepMinutes <= minutes
            default: return false
            }
        }
        if let rule = matching.first {
            return L10n.string("Chosen because the rule “%@” applies on this day.", rule.summary(meals: meals))
        }
        if context(for: day).maximumPrepMinutes != nil {
            return L10n.string("Fits the time limit you set for %@.", day.name.lowercased())
        }
        return favoriteMealIDs.contains(meal.id)
            ? L10n.string("One of the family's favorites.")
            : L10n.string("Adds variety to the rest of the week.")
    }

    private var resolvedContexts: [Weekday: DayPlanContext] {
        Dictionary(uniqueKeysWithValues: Weekday.allCases.map { ($0, context(for: $0)) })
    }

    private func refreshConflicts() {
        guard !plan.meals.isEmpty else { return }
        let result = generator.generate(
            preferredMeals: preferredMeals,
            allMeals: meals,
            rules: rules,
            contexts: resolvedContexts,
            taste: taste,
            existingPlan: WeeklyPlan(meals: plan.meals.map { item in var copy = item; copy.isLocked = true; return copy })
        )
        conflicts = result.conflicts
    }

    private func apply(_ result: GenerationResult) {
        plan = result.plan
        conflicts = result.conflicts
        reconcileGroceryChecks()
    }

    /// Keeps ticks for items that are still on the list and drops the rest. Wiping the whole
    /// set on every plan change discarded a shopper's progress mid-aisle for edits — a day
    /// swap, a single-day reshuffle — that often leave the list almost unchanged.
    private func reconcileGroceryChecks() {
        guard !checkedGroceryIDs.isEmpty else { return }
        let liveIDs = Set(groceryItems.map(\.id))
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
        let state = PersistedState(
            hasCompletedOnboarding: hasCompletedOnboarding,
            preferences: preferences,
            rules: rules,
            plan: plan,
            checkedGroceryIDs: checkedGroceryIDs,
            customMeals: customMeals,
            favoriteMealIDs: favoriteMealIDs,
            dayContexts: dayContexts,
            feedbackEvents: feedbackEvents,
            householdSize: householdSize,
            household: household
        )
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: persistenceKey) }
    }
}

private struct PersistedState: Codable {
    let hasCompletedOnboarding: Bool
    let preferences: [UUID: MealPreference]
    let rules: [PlanningRule]
    let plan: WeeklyPlan
    let checkedGroceryIDs: Set<String>
    let customMeals: [Meal]
    let favoriteMealIDs: Set<UUID>
    let dayContexts: [Weekday: DayPlanContext]
    let feedbackEvents: [MealFeedbackEvent]
    let householdSize: Int
    let household: Household

    private enum CodingKeys: String, CodingKey {
        case hasCompletedOnboarding, preferences, rules, plan, checkedGroceryIDs
        case customMeals, favoriteMealIDs, dayContexts, feedbackEvents, householdSize, household
    }

    init(
        hasCompletedOnboarding: Bool,
        preferences: [UUID: MealPreference],
        rules: [PlanningRule],
        plan: WeeklyPlan,
        checkedGroceryIDs: Set<String>,
        customMeals: [Meal],
        favoriteMealIDs: Set<UUID>,
        dayContexts: [Weekday: DayPlanContext],
        feedbackEvents: [MealFeedbackEvent],
        householdSize: Int,
        household: Household
    ) {
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.preferences = preferences
        self.rules = rules
        self.plan = plan
        self.checkedGroceryIDs = checkedGroceryIDs
        self.customMeals = customMeals
        self.favoriteMealIDs = favoriteMealIDs
        self.dayContexts = dayContexts
        self.feedbackEvents = feedbackEvents
        self.householdSize = householdSize
        self.household = household
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        hasCompletedOnboarding = try values.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        preferences = try values.decodeIfPresent([UUID: MealPreference].self, forKey: .preferences) ?? [:]
        rules = try values.decodeIfPresent([PlanningRule].self, forKey: .rules) ?? PlanningRule.starterRules(meals: SampleMeals.all)
        plan = try values.decodeIfPresent(WeeklyPlan.self, forKey: .plan) ?? .empty
        checkedGroceryIDs = try values.decodeIfPresent(Set<String>.self, forKey: .checkedGroceryIDs) ?? []
        customMeals = try values.decodeIfPresent([Meal].self, forKey: .customMeals) ?? []
        favoriteMealIDs = try values.decodeIfPresent(Set<UUID>.self, forKey: .favoriteMealIDs) ?? []
        dayContexts = try values.decodeIfPresent([Weekday: DayPlanContext].self, forKey: .dayContexts) ?? [:]
        feedbackEvents = try values.decodeIfPresent([MealFeedbackEvent].self, forKey: .feedbackEvents) ?? []
        householdSize = try values.decodeIfPresent(Int.self, forKey: .householdSize) ?? 4
        household = try values.decodeIfPresent(Household.self, forKey: .household) ?? Household()
    }
}
