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

/// Something the household tapped on a dinner reminder.
enum DinnerReminderAction: Equatable, Sendable {
    case cooked(mealID: UUID, day: Weekday, date: Date? = nil)
    case somethingElse(mealID: UUID, day: Weekday, date: Date? = nil)
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

/// Local notifications for the plan: what is for dinner, when to start it, and when the
/// week is about to run out.
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

    static let categoryIdentifier = "dinner-reminder"
    static let cookedActionIdentifier = "dinner-cooked"
    static let somethingElseActionIdentifier = "dinner-swap"

    private static let dinnerPrefix = "dinner-reminder-"
    private static let prepPrefix = "dinner-prep-"
    private static let planWeekPrefix = "plan-next-week-"
    private static let groceryPrefix = "grocery-reminder-"
    private static let allPrefixes = [dinnerPrefix, prepPrefix, planWeekPrefix, groceryPrefix]

    /// When the "next week is empty" nudge fires on the last day of the week.
    ///
    /// Its own hour rather than one borrowed from another setting: late morning on the last
    /// day is when a household has time to plan, and it keeps the nudge away from that
    /// evening's dinner reminder.
    private static let planNudgeHour = 11

    /// Keys in a request's `userInfo`, so an action can be answered without reopening state.
    private static let dayKey = "day"
    private static let mealKey = "mealID"

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
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

    /// Registers the buttons that appear on a dinner reminder.
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
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [cooked, somethingElse],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
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

        if schedule.dinnerEnabled {
            await scheduleDinners(for: schedule.plan, schedule: schedule, calendar: calendar, now: now)
            if let next = schedule.nextWeekPlan {
                await scheduleDinners(for: next, schedule: schedule, calendar: calendar, now: now)
            } else {
                await schedulePlanNextWeekNudge(schedule: schedule, calendar: calendar, now: now)
            }
        }

        if schedule.groceryEnabled {
            await scheduleGroceryReminder(schedule: schedule, calendar: calendar)
        }
    }

    private func scheduleDinners(
        for plan: WeeklyPlan,
        schedule: ReminderSchedule,
        calendar: Calendar,
        now: Date
    ) async {
        for item in plan.meals {
            guard let body = reminderBody(for: item, meals: schedule.meals) else { continue }
            let dayDate = plan.date(for: item.day, calendar: calendar)
            let stamp = Self.stamp(for: dayDate, calendar: calendar)

            guard let dinnerDate = calendar.date(
                bySettingHour: schedule.dinnerHour, minute: 0, second: 0, of: dayDate
            ) else { continue }

            if dinnerDate > now {
                let content = UNMutableNotificationContent()
                content.title = L10n.string("Dinner today")
                content.body = body
                content.sound = .default
                content.categoryIdentifier = Self.categoryIdentifier
                content.userInfo = Self.userInfo(for: item, date: dayDate)
                await add(
                    identifier: Self.dinnerPrefix + stamp,
                    content: content,
                    fireDate: dinnerDate,
                    calendar: calendar
                )
            }

            guard let targetDate = calendar.date(bySettingHour: schedule.targetDinnerHour, minute: 0, second: 0, of: dayDate),
                  schedule.prepLeadEnabled,
                  let meal = meal(for: item, meals: schedule.meals),
                  item.kind == .meal,
                  meal.prepMinutes > 0,
                  let startDate = calendar.date(
                      byAdding: .minute, value: -meal.prepMinutes, to: targetDate
                  ),
                  startDate > now
            else { continue }

            let content = UNMutableNotificationContent()
            content.title = L10n.string("Time to start cooking")
            content.body = L10n.string(
                "%@ takes about %ld min, so dinner lands at %@.",
                meal.name,
                meal.prepMinutes,
                targetDate.formatted(date: .omitted, time: .shortened)
            )
            content.sound = .default
            content.categoryIdentifier = Self.categoryIdentifier
            content.userInfo = Self.userInfo(for: item, date: dayDate)
            await add(
                identifier: Self.prepPrefix + stamp,
                content: content,
                fireDate: startDate,
                calendar: calendar
            )
        }
    }

    /// A single nudge on the last day of the planned week, when nothing has been prepared
    /// for the week after it.
    ///
    /// Without this the app simply goes quiet: every dated reminder has fired, the week has
    /// not rolled over because that only happens when the app is opened, and nothing is left
    /// to bring the household back.
    private func schedulePlanNextWeekNudge(
        schedule: ReminderSchedule,
        calendar: Calendar,
        now: Date
    ) async {
        let ordered = Weekday.ordered(calendar: calendar)
        guard let lastDay = ordered.last else { return }
        let lastDate = schedule.plan.date(for: lastDay, calendar: calendar)
        guard let fireDate = calendar.date(
            bySettingHour: Self.planNudgeHour, minute: 0, second: 0, of: lastDate
        ), fireDate > now else { return }

        let content = UNMutableNotificationContent()
        content.title = L10n.string("Next week is still empty")
        content.body = L10n.string("Open Meal Shuffler to line up next week's dinners.")
        content.sound = .default
        await add(
            identifier: Self.planWeekPrefix + Self.stamp(for: lastDate, calendar: calendar),
            content: content,
            fireDate: fireDate,
            calendar: calendar
        )
    }

    /// Repeats weekly, unlike the dated dinner reminders. Shopping day is a habit rather
    /// than something that belongs to one particular week, and a repeating trigger keeps
    /// working when the app has not been opened for a while.
    private func scheduleGroceryReminder(schedule: ReminderSchedule, calendar: Calendar) async {
        let content = UNMutableNotificationContent()
        content.title = L10n.string("Shopping day")
        content.body = L10n.string("Your grocery list is ready in Meal Shuffler.")
        content.sound = .default

        var components = DateComponents()
        components.weekday = schedule.groceryWeekday.calendarWeekday
        components.hour = schedule.groceryHour
        components.minute = 0

        let request = UNNotificationRequest(
            identifier: Self.groceryPrefix + schedule.groceryWeekday.rawValue,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        )
        try? await center.add(request)
    }

    private func add(
        identifier: String,
        content: UNNotificationContent,
        fireDate: Date,
        calendar: Calendar
    ) async {
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: calendar.dateComponents(
                [.year, .month, .day, .hour, .minute], from: fireDate
            ),
            repeats: false
        )
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await center.add(request)
    }

    /// Removes every request this app scheduled.
    ///
    /// Enumerates rather than naming identifiers: those are dated now, so there is no fixed
    /// list to remove and a stale week would otherwise linger forever.
    func cancelAll() async {
        let pending = await center.pendingNotificationRequests()
        let ours = pending
            .map(\.identifier)
            .filter { identifier in Self.allPrefixes.contains { identifier.hasPrefix($0) } }
        guard !ours.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: ours)
    }

    // MARK: - Content

    private func meal(for item: PlannedMeal, meals: [Meal]) -> Meal? {
        item.mealID.flatMap { id in meals.first(where: { $0.id == id }) }
    }

    private func reminderBody(for item: PlannedMeal, meals: [Meal]) -> String? {
        switch item.kind {
        case .away:
            return nil
        case .takeaway:
            return L10n.string("Takeaway tonight.")
        case .leftovers:
            guard let meal = meal(for: item, meals: meals) else {
                return L10n.string("Leftovers tonight.")
            }
            return L10n.string("Leftovers: %@", meal.name)
        case .meal:
            guard let meal = meal(for: item, meals: meals) else { return nil }
            return L10n.string("%@ · about %ld min", meal.name, meal.prepMinutes)
        }
    }

    private static func userInfo(for item: PlannedMeal, date: Date) -> [String: Any] {
        var info: [String: Any] = [dayKey: item.day.rawValue, "plannedDate": date.timeIntervalSince1970]
        if let mealID = item.mealID { info[mealKey] = mealID.uuidString }
        return info
    }

    /// Reads back what `userInfo(for:)` wrote. Returns nil for a notification that carries
    /// no meal, such as the plan-next-week nudge.
    static func action(
        forActionIdentifier identifier: String,
        userInfo: [AnyHashable: Any]
    ) -> DinnerReminderAction? {
        guard let rawDay = userInfo[dayKey] as? String,
              let day = Weekday(rawValue: rawDay),
              let rawMeal = userInfo[mealKey] as? String,
              let mealID = UUID(uuidString: rawMeal)
        else { return nil }

        let date = (userInfo["plannedDate"] as? TimeInterval).map(Date.init(timeIntervalSince1970:))
        switch identifier {
        case cookedActionIdentifier: return .cooked(mealID: mealID, day: day, date: date)
        case somethingElseActionIdentifier: return .somethingElse(mealID: mealID, day: day, date: date)
        default: return nil
        }
    }

    /// Stable, sortable, locale-independent day key for an identifier.
    private static func stamp(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
