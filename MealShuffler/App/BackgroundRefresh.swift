import BackgroundTasks
import Foundation

/// Turns the week over while the app is closed.
///
/// Rollover and the reminder schedule both lived only in the app, so a household that did not
/// open it on Monday got no dinner reminders that week and a widget still showing Sunday. iOS
/// decides when a refresh actually runs, so the reminder service also schedules one plain
/// reminder for the first evening of an unplanned week; whichever happens first wins, and a
/// refresh that runs replaces that reminder with the real ones.
enum BackgroundRefresh {
    /// Must match `BGTaskSchedulerPermittedIdentifiers` in Info.plist; registering an
    /// identifier that is not listed there traps at launch.
    static let identifier = "no.mealshuffler.app.refresh"

    /// Called from `didFinishLaunching`, which is the only time registration is allowed.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refresh)
        }
    }

    /// Asks for a refresh shortly after the week turns.
    @MainActor
    static func schedule(for store: AppStore, now: Date = .now) {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        let nextWeek = WeekAnchor.startOfNextWeek(after: store.plan.startDate)
        request.earliestBeginDate = max(nextWeek.addingTimeInterval(10 * 60), now.addingTimeInterval(15 * 60))
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        let work = Task { @MainActor in
            let store = AppStoreHost.shared
            store.rollOverIfNeeded()
            store.drainWidgetActions()
            store.flushPendingWrites()
            await store.refreshRemindersAndWidget()?.value
            schedule(for: store)
            task.setTaskCompleted(success: !Task.isCancelled)
        }
        task.expirationHandler = { work.cancel() }
    }
}
