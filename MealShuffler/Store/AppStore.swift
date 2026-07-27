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

    private let generator = MealPlanGenerator()
    private let persistenceKey = "meal-shuffler-state-v1"
    private var isRestoring = true
    private let defaults: UserDefaults

    var meals: [Meal] { SampleMeals.all + customMeals }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
            feedbackEvents = state.feedbackEvents
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

    func shuffleAll() {
        let result = generator.generate(
            preferredMeals: preferredMeals,
            allMeals: meals,
            rules: rules,
            contexts: resolvedContexts,
            favoriteMealIDs: favoriteMealIDs,
            learnedScores: learnedMealScores,
            recentlyCookedMealIDs: recentlyCookedMealIDs,
            existingPlan: WeeklyPlan(meals: plan.meals.filter(\.isLocked))
        )
        apply(result)
    }

    func shuffle(day: Weekday, intent: MealSwapIntent = .different) {
        let currentID = plan[day]?.mealID
        let protected = WeeklyPlan(meals: plan.meals.map { item in
            var copy = item
            copy.isLocked = item.day != day
            return copy
        })
        let result = generator.generate(
            preferredMeals: preferredMeals,
            allMeals: meals,
            rules: rules,
            contexts: resolvedContexts,
            favoriteMealIDs: favoriteMealIDs,
            learnedScores: learnedMealScores,
            recentlyCookedMealIDs: recentlyCookedMealIDs,
            existingPlan: protected,
            avoidingMealOnDay: currentID.map { [day: $0] } ?? [:],
            swapIntents: [day: intent]
        )
        var resultPlan = result.plan
        for index in resultPlan.meals.indices {
            resultPlan.meals[index].isLocked = plan[resultPlan.meals[index].day]?.isLocked ?? false
        }
        plan = resultPlan
        conflicts = result.conflicts
        checkedGroceryIDs = []
    }

    func toggleLock(day: Weekday) {
        guard var item = plan[day] else { return }
        item.isLocked.toggle()
        plan[day] = item
    }

    func updateContext(_ context: DayPlanContext, for day: Weekday) {
        dayContexts[day] = context
        if var item = plan[day] { item.isLocked = false; plan[day] = item }
        shuffleAll()
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
        checkedGroceryIDs = []
    }

    func toggleRule(_ rule: PlanningRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index].isEnabled.toggle()
        shuffleAll()
    }

    func setRuleStrength(_ strength: RuleStrength, ruleID: UUID) {
        guard let index = rules.firstIndex(where: { $0.id == ruleID }) else { return }
        rules[index].strength = strength
        shuffleAll()
    }

    func addRule(_ rule: PlanningRule) {
        rules.append(rule)
        shuffleAll()
    }

    func deleteRules(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) { rules.remove(at: index) }
        shuffleAll()
    }

    func toggleFavorite(_ meal: Meal) {
        if favoriteMealIDs.contains(meal.id) { favoriteMealIDs.remove(meal.id) }
        else { favoriteMealIDs.insert(meal.id) }
    }

    func snooze(_ meal: Meal, on day: Weekday) {
        feedbackEvents.append(MealFeedbackEvent(mealID: meal.id, kind: .snoozed, weekday: day))
        shuffle(day: day, intent: .different)
    }

    func markCooked(_ meal: Meal, on day: Weekday) {
        feedbackEvents.append(MealFeedbackEvent(mealID: meal.id, kind: .cooked, weekday: day))
    }

    func markSkipped(_ meal: Meal, on day: Weekday) {
        feedbackEvents.append(MealFeedbackEvent(mealID: meal.id, kind: .skipped, weekday: day))
        shuffle(day: day, intent: .different)
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
        customMeals.removeAll { ids.contains($0.id) }
        plan.meals.removeAll { item in item.mealID.map(ids.contains) ?? false }
        shuffleAll()
    }

    func deleteMeal(_ meal: Meal) {
        guard customMeals.contains(where: { $0.id == meal.id }) else { return }
        customMeals.removeAll { $0.id == meal.id }
        plan.meals.removeAll { $0.mealID == meal.id }
        favoriteMealIDs.remove(meal.id)
        shuffleAll()
    }

    func renameHousehold(_ name: String) {
        household.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Min familie" : name
    }

    func addHouseholdMember(named name: String, role: HouseholdRole = .adult) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        household.members.append(HouseholdMember(displayName: cleanName, role: role))
        householdSize = max(household.members.count, 1)
    }

    func removeHouseholdMembers(at offsets: IndexSet) {
        let removable = offsets.filter { household.members[$0].role != .owner }
        for index in removable.sorted(by: >) { household.members.remove(at: index) }
        householdSize = max(household.members.count, 1)
    }

    func handleIncomingURL(_ url: URL) {
        guard url.scheme == "mealshuffler", url.host == "join" else { return }
        let code = url.pathComponents.last?.uppercased() ?? ""
        guard !code.isEmpty else { return }
        inviteNotice = "Invitasjonskode \(code) er mottatt. Koden er klar for synkronisering når en ekstern household-adapter kobles til."
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
        case .away: return "Ingen er hjemme til middag."
        case .takeaway: return "Denne dagen er satt av til takeaway."
        case .leftovers(let source): return "Rester fra \(source.name.lowercased()) reduserer både arbeid og matsvinn."
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
        if let rule = matching.first { return "Valgt fordi regelen «\(rule.title)» gjelder denne dagen." }
        if context(for: day).maximumPrepMinutes != nil { return "Passer tidsgrensen du satte for \(day.name.lowercased())." }
        return favoriteMealIDs.contains(meal.id) ? "En av familiens favoritter." : "Gir variasjon fra resten av uken."
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
            favoriteMealIDs: favoriteMealIDs,
            learnedScores: learnedMealScores,
            recentlyCookedMealIDs: recentlyCookedMealIDs,
            existingPlan: WeeklyPlan(meals: plan.meals.map { item in var copy = item; copy.isLocked = true; return copy })
        )
        conflicts = result.conflicts
    }

    private func apply(_ result: GenerationResult) {
        plan = result.plan
        conflicts = result.conflicts
        checkedGroceryIDs = []
    }

    private func save() {
        guard !isRestoring else { return }
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
