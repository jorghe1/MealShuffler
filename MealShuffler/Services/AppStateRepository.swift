import Foundation
import os

/// The on-disk shape of the app.
///
/// `schemaVersion` exists so a change that *reinterprets* a field has somewhere to hook a
/// migration. Added fields are handled by `decodeIfPresent` defaults, but a blob with no
/// version at all cannot be told apart from a current one, which is how a bad migration
/// silently resets everybody.
struct AppStateSnapshot: Codable {
    /// 1: original release. 2: dated weeks, per-member preferences, sync stamps.
    static let currentVersion = 4

    let schemaVersion: Int
    let hasCompletedOnboarding: Bool
    let memberPreferences: [UUID: [UUID: MealPreference]]
    let rules: [PlanningRule]
    var plan: WeeklyPlan
    let checkedGroceryIDs: Set<String>
    let stockedGroceryIDs: Set<String>
    let manualGroceryItems: [ManualGroceryItem]
    /// Things the household always has in, so they never reach the shopping list.
    let pantryStaples: Set<String>
    let aisleOrder: [GroceryAisle]
    let customMeals: [Meal]
    let favoriteMealIDs: Set<UUID>
    var dayContexts: [Weekday: DayPlanContext]
    let feedbackEvents: [MealFeedbackEvent]
    var householdSize: Int
    let household: Household
    var archivedWeeks: [ArchivedWeek]
    var nextWeekPlan: WeeklyPlan?
    var dinnerReminderEnabled: Bool
    var dinnerReminderHour: Int
    /// A second, earlier reminder timed off the recipe's own prep time.
    var prepLeadReminderEnabled: Bool
    var groceryReminderEnabled: Bool
    var groceryReminderWeekday: Weekday
    var groceryReminderHour: Int
    var nextWeekContexts: [Weekday: DayPlanContext] = [:]
    var tools = HouseholdTools()

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, hasCompletedOnboarding, memberPreferences, rules, plan, checkedGroceryIDs
        case stockedGroceryIDs, manualGroceryItems, pantryStaples, aisleOrder
        case customMeals, favoriteMealIDs, dayContexts, feedbackEvents, householdSize, household
        case archivedWeeks, nextWeekPlan, dinnerReminderEnabled, dinnerReminderHour
        case prepLeadReminderEnabled, groceryReminderEnabled, groceryReminderWeekday, groceryReminderHour
        case nextWeekContexts, tools
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

    /// Refuses a snapshot whose shape no repair can make sense of: a week with two Mondays,
    /// two recipes or two people sharing an identity, a library past any real size.
    ///
    /// Numbers out of range are not here. They have an obvious nearest legal value, and
    /// `repairOutOfRangeValues()` moves them there; refusing them cost the household
    /// everything for one bad field.
    func validateStructure() throws {
        let weeks = [plan] + (nextWeekPlan.map { [$0] } ?? []) + archivedWeeks.map(\.plan)
        guard customMeals.count <= 2000,
              Set(customMeals.map(\.id)).count == customMeals.count,
              Set(household.members.map(\.id)).count == household.members.count,
              weeks.allSatisfy({ $0.meals.count <= 7 && Set($0.meals.map(\.day)).count == $0.meals.count })
        else { throw CocoaError(.fileReadCorruptFile) }
    }

    /// Brings every out-of-range number back into range, one field at a time.
    ///
    /// Validation used to be all or nothing. One diner count of 21 -- from an older build
    /// with a looser stepper, a hand-edited backup, a sync from a device with different
    /// limits -- failed the file *and* its backup, because both carried the same value. The
    /// household then started empty, with its data parked in an `unreadable-` file that
    /// nothing reads back. Clamping loses one number; refusing lost the plan, the library and
    /// the history.
    ///
    /// Returns a line per repair, for the log.
    @discardableResult
    mutating func repairOutOfRangeValues() -> [String] {
        var repairs: [String] = []
        func clamp(_ value: Int, to range: ClosedRange<Int>, _ field: String) -> Int {
            let clamped = min(max(value, range.lowerBound), range.upperBound)
            if clamped != value { repairs.append("\(field) \(value) -> \(clamped)") }
            return clamped
        }
        // nil means "the default scale", so that is where an unreadable scale goes.
        func scale(_ value: Double?, _ field: String) -> Double? {
            guard let value else { return nil }
            guard value.isFinite else { repairs.append("\(field) \(value) -> default"); return nil }
            let clamped = min(max(value, 0.25), 2)
            if clamped != value { repairs.append("\(field) \(value) -> \(clamped)") }
            return clamped
        }
        func repairedWeek(_ week: WeeklyPlan, _ field: String) -> WeeklyPlan {
            var week = week
            for index in week.meals.indices {
                let day = week.meals[index].day.rawValue
                week.meals[index].servings = clamp(week.meals[index].servings, to: 0...1000, "\(field).\(day).servings")
                week.meals[index].portionScale = scale(week.meals[index].portionScale, "\(field).\(day).portionScale")
            }
            return week
        }
        func repairedContexts(_ contexts: [Weekday: DayPlanContext], _ field: String) -> [Weekday: DayPlanContext] {
            var contexts = contexts
            for (day, context) in contexts {
                var context = context
                context.diners = clamp(context.diners, to: 1...20, "\(field).\(day.rawValue).diners")
                context.extraServings = clamp(context.extraServings, to: 0...12, "\(field).\(day.rawValue).extraServings")
                context.portionScale = scale(context.portionScale, "\(field).\(day.rawValue).portionScale")
                contexts[day] = context
            }
            return contexts
        }

        householdSize = clamp(householdSize, to: 1...20, "householdSize")
        plan = repairedWeek(plan, "plan")
        nextWeekPlan = nextWeekPlan.map { repairedWeek($0, "nextWeekPlan") }
        archivedWeeks = archivedWeeks.map { week -> ArchivedWeek in
            let fixed = repairedWeek(week.plan, "archivedWeeks")
            guard fixed != week.plan else { return week }
            // The initializer re-derives the recipe snapshots from a meal list; keep the
            // ones the week was archived with instead.
            var copy = ArchivedWeek(id: week.id, plan: fixed, archivedAt: week.archivedAt)
            copy.recipeSnapshots = week.recipeSnapshots
            return copy
        }
        dayContexts = repairedContexts(dayContexts, "dayContexts")
        nextWeekContexts = repairedContexts(nextWeekContexts, "nextWeekContexts")
        // A batch with nothing left in it is already gone -- consuming the last portion
        // removes it -- so dropping one is the same outcome, not a loss.
        let freezer = tools.freezer.compactMap { batch -> FreezerBatch? in
            guard batch.portions.isFinite, batch.portions > 0 else {
                repairs.append("freezer portions \(batch.portions) -> removed")
                return nil
            }
            var batch = batch
            if batch.portions > 1000 {
                repairs.append("freezer portions \(batch.portions) -> 1000")
                batch.portions = 1000
            }
            return batch
        }
        if freezer != tools.freezer { tools.freezer = freezer }
        return repairs
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
        try container.encode(nextWeekContexts, forKey: .nextWeekContexts)
        try container.encode(tools, forKey: .tools)
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        schemaVersion = version
        guard version <= Self.currentVersion else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "This backup needs a newer app version."))
        }

        hasCompletedOnboarding = try values.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        rules = try values.decodeIfPresent([LenientRule].self, forKey: .rules)
            .map { $0.compactMap(\.rule) }
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
        nextWeekContexts = try values.decodeIfPresent([Weekday: DayPlanContext].self, forKey: .nextWeekContexts) ?? [:]
        tools = try values.decodeIfPresent(HouseholdTools.self, forKey: .tools) ?? HouseholdTools()

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
        // Repaired here, inside the decoder, so every reader -- the state file, its backups,
        // the widget, a device backup, iCloud -- gets the same repaired household.
        let repairs = repairOutOfRangeValues()
        if !repairs.isEmpty {
            Self.log.notice("Repaired saved state: \(repairs.joined(separator: "; "), privacy: .public)")
        }
        try validateStructure()
    }

    /// Numbers and field names only, never household content, so the repairs can be public.
    static let log = Logger(subsystem: "no.mealshuffler", category: "state")
}

/// Where the app's state lives.
///
/// The one seam sync actually needs. Everything except Community reached UserDefaults
/// directly from the store, so adding a synced backend meant rewriting AppStore rather than
/// writing an implementation of this.
protocol AppStateRepository: Sendable {
    func load() -> AppStateSnapshot?
    func save(_ snapshot: AppStateSnapshot)
    func saveOrThrow(_ snapshot: AppStateSnapshot) throws
    var recoveryNotice: String? { get }
}

extension AppStateRepository {
    func saveOrThrow(_ snapshot: AppStateSnapshot) throws { save(snapshot) }
    var recoveryNotice: String? { nil }
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

    /// The clock that decides which day a daily copy belongs to. Replaceable in tests.
    private let now: @Sendable () -> Date

    init(
        directory: URL,
        migratingFrom legacyDefaults: UserDefaults? = AppGroup.defaults,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        fileURL = directory.appendingPathComponent(Self.fileName)
        self.legacyDefaults = legacyDefaults
        self.now = now
    }

    func load() -> AppStateSnapshot? {
        if let data = try? Data(contentsOf: fileURL),
           let snapshot = try? AppStateSnapshot.decoding(data) {
            return snapshot
        }
        if let data = try? Data(contentsOf: backupURL),
           let snapshot = try? AppStateSnapshot.decoding(data) { return snapshot }
        // Newest first: the most recent day that still reads is the least work lost.
        for url in dailyBackupURLs {
            if let data = try? Data(contentsOf: url),
               let snapshot = try? AppStateSnapshot.decoding(data) { return snapshot }
        }
        return adoptStateWrittenBeforeTheFileExisted()
    }

    private var backupURL: URL { fileURL.appendingPathExtension("backup") }
    private var directory: URL { fileURL.deletingLastPathComponent() }

    // MARK: - Daily copies

    /// How many days of copies are kept.
    static let dailyBackupsKept = 7

    /// `.backup` is the state one save ago, and a save follows every edit within 400 ms. A
    /// mistake that still decodes -- the wrong recipes deleted, a bad version synced in from
    /// another device -- has replaced the only backup with itself before anyone notices. A
    /// copy taken once a day, a week deep, is a version from before the mistake.
    ///
    /// Newest first. The date in the name sorts as text, so no file dates are read.
    var dailyBackupURLs: [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter(Self.isDailyBackupName).sorted(by: >).map { directory.appendingPathComponent($0) }
    }

    /// `state-2026-10-12.json`, in the device's own day. Gregorian whatever the user's
    /// calendar, so the names keep sorting by date.
    static func dailyBackupName(for date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "state-%04ld-%02ld-%02ld.json", day.year ?? 0, day.month ?? 0, day.day ?? 0)
    }

    static func isDailyBackupName(_ name: String) -> Bool {
        guard name.hasPrefix("state-"), name.hasSuffix(".json") else { return false }
        let date = Array(name.dropFirst("state-".count).dropLast(".json".count))
        guard date.count == 10 else { return false }
        return date.indices.allSatisfy { index in
            index == 4 || index == 7 ? date[index] == "-" : ("0"..."9").contains(date[index])
        }
    }

    /// Keeps the day's first readable state, at most once a day.
    ///
    /// What is copied is the state being replaced, not the one being written: that is the
    /// household as the day found it, so a mistake made in today's first edit is not also
    /// today's copy. Best effort -- a full disk should cost a copy, never the save itself.
    private func writeDailyBackupIfNeeded(_ existing: Data) {
        let url = directory.appendingPathComponent(Self.dailyBackupName(for: now()))
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        guard (try? existing.write(to: url, options: .atomic)) != nil else { return }
        for old in dailyBackupURLs.dropFirst(Self.dailyBackupsKept) {
            try? FileManager.default.removeItem(at: old)
        }
    }

    var recoveryNotice: String? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        if let data = try? Data(contentsOf: fileURL), (try? AppStateSnapshot.decoding(data)) != nil {
            return nil
        }
        return L10n.string("The saved data could not be read. A backup was used if available. The original file will be preserved.")
    }

    func save(_ snapshot: AppStateSnapshot) {
        try? saveOrThrow(snapshot)
    }

    func saveOrThrow(_ snapshot: AppStateSnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let existing = try Data(contentsOf: fileURL)
            if let object = try? JSONSerialization.jsonObject(with: existing) as? [String: Any],
               let version = object["schemaVersion"] as? Int, version > AppStateSnapshot.currentVersion {
                throw CocoaError(.fileWriteUnknown)
            }
            if (try? AppStateSnapshot.decoding(existing)) != nil {
                try existing.write(to: backupURL, options: .atomic)
                writeDailyBackupIfNeeded(existing)
            } else {
                try existing.write(to: fileURL.appendingPathExtension("unreadable-\(UUID().uuidString)"), options: .atomic)
            }
        }
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
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
        guard !FileManager.default.fileExists(atPath: fileURL.path), let legacyDefaults,
              let data = legacyDefaults.data(forKey: UserDefaultsStateRepository.storageKey),
              let snapshot = try? AppStateSnapshot.decoding(data)
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
        return try? AppStateSnapshot.decoding(data)
    }

    func save(_ snapshot: AppStateSnapshot) {
        try? saveOrThrow(snapshot)
    }

    func saveOrThrow(_ snapshot: AppStateSnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        defaults.set(data, forKey: key)
    }
}

/// One rule, or nothing where a rule used to be.
///
/// The vocabulary is allowed to lose a constraint -- `maximumCostPerWeek` went when the app
/// stopped claiming to know what a week costs. Without this, one rule written against the old
/// vocabulary throws while decoding, and because that throw travels all the way out of
/// `AppStateSnapshot`, the household loses its plan, its library and its history rather than
/// one rule it can no longer be shown.
private struct LenientRule: Decodable {
    let rule: PlanningRule?

    init(from decoder: Decoder) throws {
        rule = try? PlanningRule(from: decoder)
    }
}
