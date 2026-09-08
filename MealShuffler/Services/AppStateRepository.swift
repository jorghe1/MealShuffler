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
    /// Things the household always has in, so they never reach the shopping list.
    let pantryStaples: Set<String>
    let aisleOrder: [GroceryAisle]
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
    /// A second, earlier reminder timed off the recipe's own prep time.
    let prepLeadReminderEnabled: Bool
    let groceryReminderEnabled: Bool
    let groceryReminderWeekday: Weekday
    let groceryReminderHour: Int

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, hasCompletedOnboarding, memberPreferences, rules, plan, checkedGroceryIDs
        case stockedGroceryIDs, manualGroceryItems, pantryStaples, aisleOrder
        case customMeals, favoriteMealIDs, dayContexts, feedbackEvents, householdSize, household
        case archivedWeeks, nextWeekPlan, dinnerReminderEnabled, dinnerReminderHour
        case prepLeadReminderEnabled, groceryReminderEnabled, groceryReminderWeekday, groceryReminderHour
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
        pantryStaples: Set<String>,
        aisleOrder: [GroceryAisle],
        customMeals: [Meal],
        favoriteMealIDs: Set<UUID>,
        dayContexts: [Weekday: DayPlanContext],
        feedbackEvents: [MealFeedbackEvent],
        householdSize: Int,
        household: Household,
        archivedWeeks: [ArchivedWeek],
        nextWeekPlan: WeeklyPlan?,
        dinnerReminderEnabled: Bool,
        dinnerReminderHour: Int,
        prepLeadReminderEnabled: Bool,
        groceryReminderEnabled: Bool,
        groceryReminderWeekday: Weekday,
        groceryReminderHour: Int
    ) {
        schemaVersion = AppStateSnapshot.currentVersion
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.memberPreferences = memberPreferences
        self.rules = rules
        self.plan = plan
        self.checkedGroceryIDs = checkedGroceryIDs
        self.stockedGroceryIDs = stockedGroceryIDs
        self.manualGroceryItems = manualGroceryItems
        self.pantryStaples = pantryStaples
        self.aisleOrder = aisleOrder
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
        self.prepLeadReminderEnabled = prepLeadReminderEnabled
        self.groceryReminderEnabled = groceryReminderEnabled
        self.groceryReminderWeekday = groceryReminderWeekday
        self.groceryReminderHour = groceryReminderHour
    }

    // Written explicitly because `preferences` is a decode-only legacy key with no matching
    // property, which would otherwise defeat synthesis of Encodable.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(hasCompletedOnboarding, forKey: .hasCompletedOnboarding)
        try container.encode(memberPreferences, forKey: .memberPreferences)
        try container.encode(rules, forKey: .rules)
        try container.encode(plan, forKey: .plan)
        try container.encode(checkedGroceryIDs, forKey: .checkedGroceryIDs)
        try container.encode(stockedGroceryIDs, forKey: .stockedGroceryIDs)
        try container.encode(manualGroceryItems, forKey: .manualGroceryItems)
        try container.encode(pantryStaples, forKey: .pantryStaples)
        try container.encode(aisleOrder, forKey: .aisleOrder)
        try container.encode(customMeals, forKey: .customMeals)
        try container.encode(favoriteMealIDs, forKey: .favoriteMealIDs)
        try container.encode(dayContexts, forKey: .dayContexts)
        try container.encode(feedbackEvents, forKey: .feedbackEvents)
        try container.encode(householdSize, forKey: .householdSize)
        try container.encode(household, forKey: .household)
        try container.encode(archivedWeeks, forKey: .archivedWeeks)
        try container.encodeIfPresent(nextWeekPlan, forKey: .nextWeekPlan)
        try container.encode(dinnerReminderEnabled, forKey: .dinnerReminderEnabled)
        try container.encode(dinnerReminderHour, forKey: .dinnerReminderHour)
        try container.encode(prepLeadReminderEnabled, forKey: .prepLeadReminderEnabled)
        try container.encode(groceryReminderEnabled, forKey: .groceryReminderEnabled)
        try container.encode(groceryReminderWeekday, forKey: .groceryReminderWeekday)
        try container.encode(groceryReminderHour, forKey: .groceryReminderHour)
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
        pantryStaples = try values.decodeIfPresent(Set<String>.self, forKey: .pantryStaples) ?? []
        aisleOrder = try values
            .decodeIfPresent([GroceryAisle].self, forKey: .aisleOrder) ?? GroceryAisle.allCases
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
        prepLeadReminderEnabled = try values
            .decodeIfPresent(Bool.self, forKey: .prepLeadReminderEnabled) ?? false
        groceryReminderEnabled = try values
            .decodeIfPresent(Bool.self, forKey: .groceryReminderEnabled) ?? false
        groceryReminderWeekday = try values
            .decodeIfPresent(Weekday.self, forKey: .groceryReminderWeekday) ?? .saturday
        groceryReminderHour = try values.decodeIfPresent(Int.self, forKey: .groceryReminderHour) ?? 10

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

/// Where state lives in a shipping build.
///
/// A file, not user defaults: defaults is a property list the system reads into memory whole
/// and rewrites whole, and this blob grows with 26 archived weeks, up to 2,000 feedback
/// events and a meal library that now carries instructions. Both extensions decode all of it
/// just to answer "what is for dinner".
///
/// Falls back to defaults when the App Group container is not available -- an unsigned test
/// run, or a provisioning profile that was not regenerated -- because degrading is better
/// than starting empty.
struct FileStateRepository: AppStateRepository, @unchecked Sendable {
    private let fileURL: URL
    /// Where state used to live. Read once, then cleared, so there is exactly one copy.
    // Thread-safe in fact but not in the type system, and the reference is only ever
    // read. `@unchecked` states that deliberately rather than leaving a warning that
    // becomes an error under the Swift 6 language mode.
    private let legacyDefaults: UserDefaults?

    private static let directoryName = "State"
    private static let fileName = "state.json"

    /// The repository the app and its extensions actually use.
    static func live() -> any AppStateRepository {
        guard let directory = sharedDirectory else { return UserDefaultsStateRepository() }
        return FileStateRepository(directory: directory)
    }

    static var sharedDirectory: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)?
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    init(directory: URL, migratingFrom legacyDefaults: UserDefaults? = AppGroup.defaults) {
        fileURL = directory.appendingPathComponent(Self.fileName)
        self.legacyDefaults = legacyDefaults
    }

    func load() -> AppStateSnapshot? {
        if let data = try? Data(contentsOf: fileURL),
           let snapshot = try? JSONDecoder().decode(AppStateSnapshot.self, from: data) {
            return snapshot
        }
        return adoptStateWrittenBeforeTheFileExisted()
    }

    func save(_ snapshot: AppStateSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        write(data)
    }

    @discardableResult
    private func write(_ data: Data) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            // Readable by the widget once the device has been unlocked once, which is what a
            // timeline refresh on a locked phone needs.
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            return false
        }
    }

    /// Moves an install forward from the user-defaults era, exactly once.
    ///
    /// The old copy is removed only after the file is written and reads back, so a failed
    /// migration leaves the household's plan where it was rather than nowhere.
    private func adoptStateWrittenBeforeTheFileExisted() -> AppStateSnapshot? {
        guard let legacyDefaults,
              let data = legacyDefaults.data(forKey: UserDefaultsStateRepository.storageKey),
              let snapshot = try? JSONDecoder().decode(AppStateSnapshot.self, from: data)
        else { return nil }

        if write(data), (try? Data(contentsOf: fileURL)) != nil {
            legacyDefaults.removeObject(forKey: UserDefaultsStateRepository.storageKey)
        }
        return snapshot
    }
}

/// The user-defaults implementation. Still the fallback when there is no shared container,
/// and what the tests use, since a defaults suite is trivially disposable.
struct UserDefaultsStateRepository: AppStateRepository, @unchecked Sendable {
    /// The key is versioned separately from the payload: `schemaVersion` inside the snapshot
    /// handles ordinary migration, and this only changes for a break too large to migrate.
    static let storageKey = "meal-shuffler-state-v1"
    private let key = UserDefaultsStateRepository.storageKey
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
