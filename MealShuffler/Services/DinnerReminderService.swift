import Foundation
import UserNotifications

/// What the household asked to be reminded about.
///
/// Passed as one value rather than a widening parameter list, so the store can hand the
/// service a snapshot it is free to read off the main actor.
struct ReminderSchedule: Sendable, Equatable {
    var plan: WeeklyPlan
    var nextWeekPlan: WeeklyPlan?
    var meals: [Meal]
    var dinnerEnabled: Bool
    var dinnerHour: Int
    var targetDinnerHour: Int = 18
    /// A second, earlier nudge timed off the recipe's own prep time.
    var prepLeadEnabled: Bool
    var groceryEnabled: Bool
    var groceryWeekday: Weekday
    var groceryHour: Int
    /// Who cooks, by yyyy-MM-dd day stamp.
    var cooks: [String: String] = [:]

    static let empty = ReminderSchedule(
        plan: .empty,
        nextWeekPlan: nil,
        meals: [],
        dinnerEnabled: false,
        dinnerHour: 16,
        prepLeadEnabled: false,
        groceryEnabled: false,
        groceryWeekday: .saturday,
        groceryHour: 10
    )
}

/// One day's worth of notification, and which one it is.
///
/// The app grew several kinds of reminder independently, each correct on its own, and nobody
/// counted what a household with all of them switched on actually receives. Still at most one
/// a day -- but a day's other reminders are now said *in* that one rather than dropped: the
/// cap used to silence the shopping day's dinner reminder every week, and the "next week is
/// empty" nudge always lost to that evening's dinner, so it never fired at all.
///
/// `rawValue` is the priority of the one that leads.
enum ReminderKind: Int, Comparable, Sendable {
    /// Least urgent. Said as a line on that day's reminder, or alone when there is none.
    case planNextWeek = 0
    /// The first evening of a week nobody planned, in case the app was not opened and
    /// background refresh did not run.
    case newWeek = 1
    /// Tomorrow's dinner is in the freezer and needs the night in the fridge.
    case thaw = 2
    /// The fixed-hour "Dinner today".
    case dinner = 3
    /// Timed off the recipe's own prep time, so it says something the fixed-hour one cannot.
    case prep = 4
    /// Time-critical, because shops close. Carries tonight's dinner as a line.
    case grocery = 5

    static func < (lhs: ReminderKind, rhs: ReminderKind) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Something the household tapped on a dinner reminder.
enum DinnerReminderAction: Equatable, Sendable {
    case cooked(mealID: UUID, day: Weekday, date: Date? = nil)
    case somethingElse(mealID: UUID, day: Weekday, date: Date? = nil)
}

/// Where opening a reminder takes the household. Before, every notification opened the app
/// wherever it was last left.
enum ReminderDestination: String, Sendable {
    case tonight
    case nextWeek
    case shop
}

/// What the store asks of the notification layer.
///
/// A seam, like `AppStateRepository` and `WidgetRefreshing`: the interesting question is
/// "does changing the plan reschedule", and answering it in a test should not require a real
/// notification centre or an authorisation prompt.
protocol ReminderScheduling: Sendable {
    func reschedule(_ schedule: ReminderSchedule) async
    func requestAuthorization() async -> Bool
    func isAuthorized() async -> Bool
}

/// Records what it was asked to schedule instead of scheduling it.
///
/// Serialised on a queue rather than behind an `NSLock`: `reschedule` is async, and taking a
/// lock across a suspension point is unavailable from an asynchronous context.
final class RecordingReminderScheduler: ReminderScheduling, @unchecked Sendable {
    private let queue = DispatchQueue(label: "no.mealshuffler.recording-reminder-scheduler")
    private var schedules: [ReminderSchedule] = []
    private var isAuthorizedValue: Bool

    init(authorized: Bool = true) {
        isAuthorizedValue = authorized
    }

    /// Whether `isAuthorized` should answer yes, so a test can drive both branches.
    var authorized: Bool {
        get { queue.sync { isAuthorizedValue } }
        set { queue.sync { isAuthorizedValue = newValue } }
    }

    var rescheduleCount: Int { queue.sync { schedules.count } }

    var lastSchedule: ReminderSchedule? { queue.sync { schedules.last } }

    func reschedule(_ schedule: ReminderSchedule) async {
        queue.sync { schedules.append(schedule) }
    }

    func requestAuthorization() async -> Bool { authorized }
    func isAuthorized() async -> Bool { authorized }
}

/// Local notifications for the plan: what is for dinner, when to start it, shopping day, and
/// when the week is about to run out.
///
/// Every request is dated, because a bare `Weekday` cannot say which Tuesday it means. That
/// also means identifiers are dated: the old fixed set of seven could only ever describe one
/// week, so nothing beyond Sunday could be scheduled and the household went quiet until it
/// next opened the app.
struct DinnerReminderService: ReminderScheduling, @unchecked Sendable {
    // Thread-safe in fact but not in the type system, and the reference is only ever
    // read. `@unchecked` states that deliberately rather than leaving a warning that
    // becomes an error under the Swift 6 language mode.
    private let center: UNUserNotificationCenter

    /// A cooking day: the buttons record the dinner or replace it.
    static let categoryIdentifier = "dinner-reminder"
    /// Takeaway, leftovers, shopping day: nothing for the buttons to act on, so none are shown.
    static let infoCategoryIdentifier = "dinner-info"
    /// The empty-next-week nudge, with a button that shuffles it.
    static let planCategoryIdentifier = "plan-next-week"
    static let cookedActionIdentifier = "dinner-cooked"
    static let somethingElseActionIdentifier = "dinner-swap"
    static let planNextWeekActionIdentifier = "plan-next-week-now"

    private static let dinnerPrefix = "dinner-reminder-"
    private static let prepPrefix = "dinner-prep-"
    private static let planWeekPrefix = "plan-next-week-"
    private static let groceryPrefix = "grocery-reminder-"
    private static let newWeekPrefix = "new-week-"
    private static let thawPrefix = "thaw-"
    private static let allPrefixes = [dinnerPrefix, prepPrefix, planWeekPrefix, groceryPrefix, newWeekPrefix, thawPrefix]

    /// When the "next week is empty" nudge fires on the last day of the week, when nothing
    /// else is said that day.
    ///
    /// Its own hour rather than one borrowed from another setting: late morning on the last
    /// day is when a household has time to plan.
    private static let planNudgeHour = 11

    /// How far ahead shopping days are scheduled. They are dated now, like everything else,
    /// so they can carry the evening's dinner.
    private static let groceryHorizonDays = 14

    /// Keys in a request's `userInfo`, so an action can be answered without reopening state.
    private static let dayKey = "day"
    private static let mealKey = "mealID"
    private static let dateKey = "plannedDate"
    private static let destinationKey = "destination"

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func isAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    /// True once the user has answered the system prompt either way. Used to decide whether
    /// asking again can do anything, since a second request on a denied app is a no-op.
    func hasBeenAsked() async -> Bool {
        await center.notificationSettings().authorizationStatus != .notDetermined
    }

    /// Registers the buttons that appear on reminders.
    ///
    /// Must happen before anything is scheduled: a notification naming a category that was
    /// never registered simply shows without its actions.
    func registerCategories() {
        let cooked = UNNotificationAction(
            identifier: Self.cookedActionIdentifier,
            title: L10n.string("We cooked this"),
            options: []
        )
        let somethingElse = UNNotificationAction(
            identifier: Self.somethingElseActionIdentifier,
            title: L10n.string("Something else"),
            options: [.foreground]
        )
        let planNextWeek = UNNotificationAction(
            identifier: Self.planNextWeekActionIdentifier,
            title: L10n.string("Shuffle next week"),
            options: [.foreground]
        )
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.categoryIdentifier, actions: [cooked, somethingElse],
                                   intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: Self.infoCategoryIdentifier, actions: [],
                                   intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: Self.planCategoryIdentifier, actions: [planNextWeek],
                                   intentIdentifiers: [], options: [])
        ])
    }

    // MARK: - Scheduling

    /// Replaces every scheduled reminder with ones matching the plan as it now stands.
    ///
    /// Called after any change the notification text depends on, so a reshuffled Thursday
    /// never announces the meal it replaced.
    func reschedule(_ schedule: ReminderSchedule) async {
        await reschedule(schedule, calendar: .current, now: .now)
    }

    /// Injection points for tests. Kept as a separate method rather than defaulted
    /// parameters, which do not satisfy a protocol requirement.
    func reschedule(
        _ schedule: ReminderSchedule,
        calendar: Calendar,
        now: Date
    ) async {
        await cancelAll()
        guard await isAuthorized() else { return }

        let chosen = Self.oneADay(
            Self.candidates(for: schedule, calendar: calendar, now: now),
            schedule: schedule,
            calendar: calendar
        )
        for candidate in chosen {
            guard let content = Self.content(for: candidate, schedule: schedule, calendar: calendar) else { continue }
            await add(content, candidate: candidate, calendar: calendar)
        }
    }

    /// One notification the schedule would like to send.
    struct Candidate: Equatable, Sendable {
        let stamp: String
        let kind: ReminderKind
        let fireDate: Date
        var item: PlannedMeal?
        var dayDate: Date?
        /// Next week is still empty, said on this day's reminder rather than in a second one.
        var mentionsEmptyNextWeek = false
    }

    /// What one notification says, and where it leads.
    struct Content: Equatable, Sendable {
        let title: String
        let body: String
        let categoryIdentifier: String?
        let destination: ReminderDestination
    }

    /// Everything the schedule wants to send, before the daily cap.
    ///
    /// Pure and static so a test can ask what a household would receive without a
    /// notification centre, an authorisation prompt, or a device.
    static func candidates(
        for schedule: ReminderSchedule,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> [Candidate] {
        var found: [Candidate] = []
        let plans = [schedule.plan, schedule.nextWeekPlan].compactMap { $0 }

        if schedule.dinnerEnabled {
            for plan in plans {
                for item in plan.meals {
                    let dayDate = plan.date(for: item.day, calendar: calendar)
                    let stamp = Self.stamp(for: dayDate, calendar: calendar)

                    if reminderBody(for: item, meals: schedule.meals) != nil,
                       let dinnerDate = calendar.date(
                           bySettingHour: schedule.dinnerHour, minute: 0, second: 0, of: dayDate
                       ), dinnerDate > now {
                        found.append(Candidate(stamp: stamp, kind: .dinner, fireDate: dinnerDate, item: item, dayDate: dayDate))
                    }

                    if schedule.prepLeadEnabled, item.kind == .meal,
                       let meal = meal(for: item, meals: schedule.meals), meal.prepMinutes > 0,
                       let targetDate = calendar.date(
                           bySettingHour: schedule.targetDinnerHour, minute: 0, second: 0, of: dayDate
                       ),
                       let startDate = calendar.date(byAdding: .minute, value: -meal.prepMinutes, to: targetDate),
                       startDate > now {
                        found.append(Candidate(stamp: stamp, kind: .prep, fireDate: startDate, item: item, dayDate: dayDate))
                    }

                    // The evening before a freezer dinner, so it gets the night in the fridge.
                    if item.freezerBatch != nil, item.freezerConsumed != true,
                       let eveningBefore = calendar.date(byAdding: .day, value: -1, to: dayDate),
                       let fireDate = calendar.date(bySettingHour: schedule.dinnerHour, minute: 0, second: 0, of: eveningBefore),
                       fireDate > now {
                        found.append(Candidate(stamp: Self.stamp(for: eveningBefore, calendar: calendar), kind: .thaw,
                                               fireDate: fireDate, item: item, dayDate: dayDate))
                    }
                }
            }

            // Only worth nudging when nothing has been prepared for the week after this one.
            if schedule.nextWeekPlan == nil, let lastDay = Weekday.ordered(calendar: calendar).last {
                let lastDate = schedule.plan.date(for: lastDay, calendar: calendar)
                if let fireDate = calendar.date(bySettingHour: planNudgeHour, minute: 0, second: 0, of: lastDate),
                   fireDate > now {
                    found.append(Candidate(stamp: stamp(for: lastDate, calendar: calendar), kind: .planNextWeek,
                                           fireDate: fireDate, item: nil, dayDate: lastDate))
                }
                let nextStart = WeekAnchor.startOfNextWeek(after: schedule.plan.startDate, calendar: calendar)
                if let fireDate = calendar.date(bySettingHour: schedule.dinnerHour, minute: 0, second: 0, of: nextStart),
                   fireDate > now {
                    found.append(Candidate(stamp: stamp(for: nextStart, calendar: calendar), kind: .newWeek,
                                           fireDate: fireDate, item: nil, dayDate: nextStart))
                }
            }
        }

        if schedule.groceryEnabled {
            let today = calendar.startOfDay(for: now)
            for offset in 0..<groceryHorizonDays {
                guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                      calendar.component(.weekday, from: day) == schedule.groceryWeekday.calendarWeekday,
                      let fireDate = calendar.date(bySettingHour: schedule.groceryHour, minute: 0, second: 0, of: day),
                      fireDate > now else { continue }
                found.append(Candidate(stamp: stamp(for: day, calendar: calendar), kind: .grocery, fireDate: fireDate,
                                       item: item(on: day, in: plans, calendar: calendar), dayDate: day))
            }
        }

        return found
    }

    /// At most one notification a day, saying everything that day needs.
    ///
    /// The highest-priority reminder leads. The plan-next-week nudge becomes a line on it
    /// rather than a second push; a freezer reminder and tonight's dinner are added to the
    /// text by `content(for:)`. Alone, any of them still fires.
    static func oneADay(
        _ candidates: [Candidate],
        schedule: ReminderSchedule,
        calendar: Calendar = .current
    ) -> [Candidate] {
        let byDay = Dictionary(grouping: candidates, by: \.stamp)
        var chosen: [Candidate] = []
        for (_, group) in byDay {
            let mentionsNudge = group.contains { $0.kind == .planNextWeek }
            let concrete = group.filter { $0.kind != .planNextWeek }
            if var lead = concrete.max(by: { $0.kind < $1.kind }) {
                lead.mentionsEmptyNextWeek = mentionsNudge
                chosen.append(lead)
            } else if let nudge = group.first {
                chosen.append(nudge)
            }
        }
        return chosen.sorted { $0.fireDate < $1.fireDate }
    }

    // MARK: - Content

    /// What a chosen reminder says. Nil when there is nothing worth saying (a shopping day in
    /// a week with no dinners to shop for).
    static func content(for candidate: Candidate, schedule: ReminderSchedule, calendar: Calendar = .current) -> Content? {
        let plans = [schedule.plan, schedule.nextWeekPlan].compactMap { $0 }
        let title: String
        var lines: [String] = []
        var category: String?
        var destination = ReminderDestination.tonight

        switch candidate.kind {
        case .dinner:
            guard let item = candidate.item, let body = reminderBody(for: item, meals: schedule.meals) else { return nil }
            title = tonightTitle(for: item, meals: schedule.meals)
            if item.kind == .meal, let cook = schedule.cooks[candidate.stamp] {
                lines.append(body + " · " + L10n.string("%@ cooks", cook))
            } else {
                lines.append(body)
            }
            category = item.kind == .meal ? categoryIdentifier : infoCategoryIdentifier

        case .prep:
            guard let item = candidate.item, let dayDate = candidate.dayDate,
                  let meal = meal(for: item, meals: schedule.meals),
                  let targetDate = calendar.date(bySettingHour: schedule.targetDinnerHour, minute: 0, second: 0, of: dayDate)
            else { return nil }
            title = schedule.cooks[candidate.stamp].map { L10n.string("Time to start cooking, %@", $0) }
                ?? L10n.string("Time to start cooking")
            lines.append(L10n.string(
                "%@ takes about %ld min, so dinner is ready at %@.",
                meal.name, meal.prepMinutes, targetDate.formatted(date: .omitted, time: .shortened)
            ))
            category = categoryIdentifier

        case .grocery:
            guard let dayDate = candidate.dayDate else { return nil }
            let dinners = dinnersToShopFor(from: dayDate, in: plans, calendar: calendar)
            guard dinners > 0 else { return nil }
            title = L10n.string("Shopping day")
            lines.append(dinners == 1
                ? L10n.string("The list for 1 dinner is ready.")
                : L10n.string("The list for %ld dinners is ready.", dinners))
            if let item = candidate.item, item.kind != .away {
                lines.append(L10n.string("Tonight: %@.", tonightName(for: item, meals: schedule.meals)))
            }
            category = infoCategoryIdentifier
            destination = .shop

        case .thaw:
            guard let batch = candidate.item?.freezerBatch else { return nil }
            title = L10n.string("Take %@ out of the freezer", batch.recipe.name)
            lines.append(L10n.string("It is tomorrow's dinner and needs the night in the fridge."))
            category = infoCategoryIdentifier

        case .newWeek:
            title = L10n.string("A new week")
            lines.append(L10n.string("Open Meal Shuffler to see this week's dinners."))
            category = infoCategoryIdentifier

        case .planNextWeek:
            title = L10n.string("Next week is still empty")
            lines.append(L10n.string("Shuffle it now, it takes ten seconds."))
            category = planCategoryIdentifier
            destination = .nextWeek
        }

        // Tomorrow's freezer dinner, on whatever leads today.
        if candidate.kind != .thaw, let dayDate = candidate.dayDate,
           let tomorrow = calendar.date(byAdding: .day, value: 1, to: dayDate),
           let next = item(on: tomorrow, in: plans, calendar: calendar),
           let batch = next.freezerBatch, next.freezerConsumed != true {
            lines.append(L10n.string("Tomorrow: %@ from the freezer. Take it out tonight.", batch.recipe.name))
        }
        if candidate.mentionsEmptyNextWeek {
            lines.append(L10n.string("Next week is still empty. Open the app to shuffle it."))
            if category == infoCategoryIdentifier { category = planCategoryIdentifier }
        }
        return Content(title: title, body: lines.joined(separator: "\n"), categoryIdentifier: category, destination: destination)
    }

    static func meal(for item: PlannedMeal, meals: [Meal]) -> Meal? {
        item.freezerBatch?.recipe ?? item.mealID.flatMap { id in meals.first(where: { $0.id == id }) }
    }

    /// The second line of a dinner reminder; nil for a day nobody eats at home.
    static func reminderBody(for item: PlannedMeal, meals: [Meal]) -> String? {
        switch item.kind {
        case .away:
            return nil
        case .takeaway:
            return L10n.string("No cooking tonight.")
        case .leftovers:
            return L10n.string("Nothing to cook tonight.")
        case .meal:
            guard let meal = meal(for: item, meals: meals) else { return nil }
            return meal.prepMinutes > 0
                ? L10n.string("About %ld minutes", meal.prepMinutes)
                : L10n.string("The recipe is in the app.")
        }
    }

    private static func tonightName(for item: PlannedMeal, meals: [Meal]) -> String {
        switch item.kind {
        case .takeaway: return L10n.string("takeaway")
        case .leftovers:
            guard let meal = meal(for: item, meals: meals) else { return L10n.string("leftovers") }
            return item.freezerBatch == nil ? L10n.string("Leftovers: %@", meal.name) : L10n.string("From the freezer: %@", meal.name)
        case .away: return L10n.string("No dinner at home")
        case .meal: return meal(for: item, meals: meals)?.name ?? L10n.string("Not planned")
        }
    }

    private static func tonightTitle(for item: PlannedMeal, meals: [Meal]) -> String {
        L10n.string("Tonight: %@", tonightName(for: item, meals: meals))
    }

    /// The planned item on a given date, from whichever plan covers it.
    private static func item(on date: Date, in plans: [WeeklyPlan], calendar: Calendar) -> PlannedMeal? {
        for plan in plans {
            for item in plan.meals where calendar.isDate(plan.date(for: item.day, calendar: calendar), inSameDayAs: date) {
                return item
            }
        }
        return nil
    }

    /// Dinners still to cook from the shopping day to the end of its week.
    private static func dinnersToShopFor(from date: Date, in plans: [WeeklyPlan], calendar: Calendar) -> Int {
        let start = calendar.startOfDay(for: date)
        for plan in plans {
            let weekEnd = WeekAnchor.startOfNextWeek(after: plan.startDate, calendar: calendar)
            guard start >= calendar.startOfDay(for: plan.startDate), start < weekEnd else { continue }
            return plan.meals.filter { item in
                item.kind == .meal && item.mealID != nil && plan.date(for: item.day, calendar: calendar) >= start
            }.count
        }
        return 0
    }

    // MARK: - Delivery

    private func add(_ content: Content, candidate: Candidate, calendar: Calendar) async {
        let notification = UNMutableNotificationContent()
        notification.title = content.title
        notification.body = content.body
        notification.sound = .default
        if let category = content.categoryIdentifier { notification.categoryIdentifier = category }
        var info: [String: Any] = [Self.destinationKey: content.destination.rawValue]
        if let item = candidate.item, let dayDate = candidate.dayDate, candidate.kind != .thaw {
            info[Self.dayKey] = item.day.rawValue
            info[Self.dateKey] = dayDate.timeIntervalSince1970
            if let mealID = item.mealID { info[Self.mealKey] = mealID.uuidString }
        }
        notification.userInfo = info

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: candidate.fireDate),
            repeats: false
        )
        let request = UNNotificationRequest(identifier: Self.prefix(for: candidate.kind) + candidate.stamp,
                                            content: notification, trigger: trigger)
        try? await center.add(request)
    }

    private static func prefix(for kind: ReminderKind) -> String {
        switch kind {
        case .dinner: dinnerPrefix
        case .prep: prepPrefix
        case .grocery: groceryPrefix
        case .planNextWeek: planWeekPrefix
        case .newWeek: newWeekPrefix
        case .thaw: thawPrefix
        }
    }

    /// Removes every request this app scheduled, including the weekly repeating shopping
    /// reminder older versions left behind.
    ///
    /// Enumerates rather than naming identifiers: those are dated, so there is no fixed list
    /// to remove and a stale week would otherwise linger forever.
    func cancelAll() async {
        let pending = await center.pendingNotificationRequests()
        let ours = pending
            .map(\.identifier)
            .filter { identifier in Self.allPrefixes.contains { identifier.hasPrefix($0) } }
        guard !ours.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: ours)
    }

    // MARK: - Responses

    /// Reads back what `add` wrote. Returns nil for a notification that carries no meal, such
    /// as the plan-next-week nudge, or for an action that only opens the app.
    static func action(
        forActionIdentifier identifier: String,
        userInfo: [AnyHashable: Any]
    ) -> DinnerReminderAction? {
        guard let rawDay = userInfo[dayKey] as? String,
              let day = Weekday(rawValue: rawDay),
              let rawMeal = userInfo[mealKey] as? String,
              let mealID = UUID(uuidString: rawMeal)
        else { return nil }

        let date = (userInfo[dateKey] as? TimeInterval).map(Date.init(timeIntervalSince1970:))
        switch identifier {
        case cookedActionIdentifier: return .cooked(mealID: mealID, day: day, date: date)
        case somethingElseActionIdentifier: return .somethingElse(mealID: mealID, day: day, date: date)
        default: return nil
        }
    }

    /// Where the app should open after a response; nil for a response handled in the
    /// background ("We cooked this").
    static func destination(
        forActionIdentifier identifier: String,
        userInfo: [AnyHashable: Any]
    ) -> ReminderDestination? {
        switch identifier {
        case cookedActionIdentifier: return nil
        case somethingElseActionIdentifier: return .tonight
        case planNextWeekActionIdentifier: return .nextWeek
        default: return (userInfo[destinationKey] as? String).flatMap(ReminderDestination.init(rawValue:)) ?? .tonight
        }
    }

    /// Stable, sortable, locale-independent day key for an identifier.
    private static func stamp(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
