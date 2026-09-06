import Foundation

/// The on-disk shape of the app.
///
/// `schemaVersion` exists so a change that *reinterprets* a field has somewhere to hook a
/// migration. Added fields are handled by `decodeIfPresent` defaults, but a blob with no
/// version at all cannot be told apart from a current one, which is how a bad migration
/// silently resets everybody.
struct AppStateSnapshot: Codable {
    /// 1: original release. 2: dated weeks, per-member preferences, sync stamps.
    static let currentVersion = 2

    let schemaVersion: Int
    let hasCompletedOnboarding: Bool
    let memberPreferences: [UUID: [UUID: MealPreference]]
    let rules: [PlanningRule]
    let plan: WeeklyPlan
    let checkedGroceryIDs: Set<String>
    let stockedGroceryIDs: Set<String>
    let manualGroceryItems: [ManualGroceryItem]
    let customMeals: [Meal]
    let favoriteMealIDs: Set<UUID>
    let dayContexts: [Weekday: DayPlanContext]
    let feedbackEvents: [MealFeedbackEvent]
    let householdSize: Int
    let household: Household
    let archivedWeeks: [ArchivedWeek]
    let nextWeekPlan: WeeklyPlan?
    let dinnerReminderEnabled: Bool
    let dinnerReminderHour: Int

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, hasCompletedOnboarding, memberPreferences, rules, plan, checkedGroceryIDs
        case stockedGroceryIDs, manualGroceryItems
        case customMeals, favoriteMealIDs, dayContexts, feedbackEvents, householdSize, household
        case archivedWeeks, nextWeekPlan, dinnerReminderEnabled, dinnerReminderHour
        /// v1 key: one flat map for the whole household. Decoded only.
        case preferences
    }

    init(
        hasCompletedOnboarding: Bool,
        memberPreferences: [UUID: [UUID: MealPreference]],
        rules: [PlanningRule],
        plan: WeeklyPlan,
        checkedGroceryIDs: Set<String>,
        stockedGroceryIDs: Set<String>,
        manualGroceryItems: [ManualGroceryItem],
        customMeals: [Meal],
        favoriteMealIDs: Set<UUID>,
        dayContexts: [Weekday: DayPlanContext],
        feedbackEvents: [MealFeedbackEvent],
        householdSize: Int,
        household: Household,
        archivedWeeks: [ArchivedWeek],
        nextWeekPlan: WeeklyPlan?,
        dinnerReminderEnabled: Bool,
        dinnerReminderHour: Int
    ) {
        schemaVersion = AppStateSnapshot.currentVersion
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.memberPreferences = memberPreferences
        self.rules = rules
        self.plan = plan
        self.checkedGroceryIDs = checkedGroceryIDs
        self.stockedGroceryIDs = stockedGroceryIDs
        self.manualGroceryItems = manualGroceryItems
        self.customMeals = customMeals
        self.favoriteMealIDs = favoriteMealIDs
        self.dayContexts = dayContexts
        self.feedbackEvents = feedbackEvents
        self.householdSize = householdSize
        self.household = household
        self.archivedWeeks = archivedWeeks
        self.nextWeekPlan = nextWeekPlan
        self.dinnerReminderEnabled = dinnerReminderEnabled
        self.dinnerReminderHour = dinnerReminderHour
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        schemaVersion = version

        hasCompletedOnboarding = try values.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        rules = try values.decodeIfPresent([PlanningRule].self, forKey: .rules)
            ?? PlanningRule.starterRules(meals: SampleMeals.all)
        plan = try values.decodeIfPresent(WeeklyPlan.self, forKey: .plan) ?? .empty
        checkedGroceryIDs = try values.decodeIfPresent(Set<String>.self, forKey: .checkedGroceryIDs) ?? []
        stockedGroceryIDs = try values.decodeIfPresent(Set<String>.self, forKey: .stockedGroceryIDs) ?? []
        manualGroceryItems = try values
            .decodeIfPresent([ManualGroceryItem].self, forKey: .manualGroceryItems) ?? []
        customMeals = try values.decodeIfPresent([Meal].self, forKey: .customMeals) ?? []
        favoriteMealIDs = try values.decodeIfPresent(Set<UUID>.self, forKey: .favoriteMealIDs) ?? []
        dayContexts = try values.decodeIfPresent([Weekday: DayPlanContext].self, forKey: .dayContexts) ?? [:]
        feedbackEvents = try values.decodeIfPresent([MealFeedbackEvent].self, forKey: .feedbackEvents) ?? []
        householdSize = try values.decodeIfPresent(Int.self, forKey: .householdSize) ?? 4
        let restoredHousehold = try values.decodeIfPresent(Household.self, forKey: .household) ?? Household()
        household = restoredHousehold
        archivedWeeks = try values.decodeIfPresent([ArchivedWeek].self, forKey: .archivedWeeks) ?? []
        nextWeekPlan = try values.decodeIfPresent(WeeklyPlan.self, forKey: .nextWeekPlan)
        dinnerReminderEnabled = try values.decodeIfPresent(Bool.self, forKey: .dinnerReminderEnabled) ?? false
        dinnerReminderHour = try values.decodeIfPresent(Int.self, forKey: .dinnerReminderHour) ?? 16

        if let stored = try values.decodeIfPresent([UUID: [UUID: MealPreference]].self, forKey: .memberPreferences) {
            memberPreferences = stored
        } else {
            // v1 -> v2: taste was recorded for the household as a whole. Attribute it to the
            // owner, who is the only person the swipe UI could have been speaking for.
            let flat = try values.decodeIfPresent([UUID: MealPreference].self, forKey: .preferences) ?? [:]
            let owner = restoredHousehold.members.first(where: { $0.role == .owner })?.id
                ?? restoredHousehold.members.first?.id
                ?? restoredHousehold.id
            memberPreferences = flat.isEmpty ? [:] : [owner: flat]
        }
    }
}

/// Where the app's state lives.
///
/// The one seam sync actually needs. Everything except Community reached UserDefaults
/// directly from the store, so adding a synced backend meant rewriting AppStore rather than
/// writing an implementation of this.
protocol AppStateRepository: Sendable {
    func load() -> AppStateSnapshot?
    func save(_ snapshot: AppStateSnapshot)
}

/// The local, offline implementation. Also the fallback whatever else is added later.
struct UserDefaultsStateRepository: AppStateRepository {
    /// The key is versioned separately from the payload: `schemaVersion` inside the snapshot
    /// handles ordinary migration, and this only changes for a break too large to migrate.
    private let key = "meal-shuffler-state-v1"
    private let defaults: UserDefaults

    /// Defaults to the App Group container so extensions can read the same state.
    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
        adoptStateWrittenBeforeTheAppGroupExisted()
    }

    /// Copies state written to the app's private defaults by an earlier version.
    ///
    /// The original is deliberately left in place: a user who reinstalls an older build should
    /// still find their week, and one stale copy costs a few kilobytes.
    private func adoptStateWrittenBeforeTheAppGroupExisted() {
        let standard = UserDefaults.standard
        guard defaults !== standard, defaults.data(forKey: key) == nil,
              let existing = standard.data(forKey: key) else { return }
        defaults.set(existing, forKey: key)
    }

    func load() -> AppStateSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(AppStateSnapshot.self, from: data)
    }

    func save(_ snapshot: AppStateSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }
}
