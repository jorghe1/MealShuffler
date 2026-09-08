import UIKit
import UserNotifications

/// Exists for one reason: notifications.
///
/// Two things need a delegate set before the first notification is delivered. A reminder
/// that fires while the app is frontmost is dropped by iOS unless `willPresent` says
/// otherwise -- which meant the 16:00 reminder simply never appeared for anyone who happened
/// to have the app open. And a notification action taps back into the app, which can only be
/// answered by a delegate that already exists at launch.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Set once the store exists. Actions that arrive before then are buffered rather than
    /// dropped: launching *from* a notification action delivers the response before the
    /// scene has built its store.
    private var handler: (@MainActor (DinnerReminderAction) -> Void)?
    private var buffered: [DinnerReminderAction] = []

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        DinnerReminderService().registerCategories()
        return true
    }

    /// Wires the store in and drains anything that arrived before it existed.
    @MainActor
    func setActionHandler(_ handler: @escaping @MainActor (DinnerReminderAction) -> Void) {
        self.handler = handler
        let waiting = buffered
        buffered = []
        for action in waiting { handler(action) }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Without this the reminder is silently swallowed whenever the app is frontmost.
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let action = DinnerReminderService.action(
            forActionIdentifier: response.actionIdentifier,
            userInfo: response.notification.request.content.userInfo
        ) else { return }

        await MainActor.run {
            if let handler {
                handler(action)
            } else {
                buffered.append(action)
            }
        }
    }
}
