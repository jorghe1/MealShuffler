import UIKit
import CloudKit
import UserNotifications

/// Receives notification responses, background refresh and iCloud sharing invitations.
///
/// A delegate has to exist before the first notification is delivered. A reminder that fires
/// while the app is frontmost is dropped by iOS unless `willPresent` says otherwise, and a
/// notification response can launch the app straight into the background with no scene at
/// all -- which is how a lock-screen "We cooked this" arrives.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        DinnerReminderService().registerCategories()
        BackgroundRefresh.register()
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = SharingSceneDelegate.self
        return configuration
    }

    func application(_ application: UIApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        guard FeatureFlags.householdSyncEnabled else { return }
        Task { @MainActor in CloudHouseholdSync.shared.received(metadata) }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Without this the reminder is silently swallowed whenever the app is frontmost.
        [.banner, .list, .sound]
    }

    /// Answered against the shared store directly, and written before returning.
    ///
    /// The handler used to be attached by the scene, so an action that launched the app in the
    /// background waited in a buffer for a scene that never came, and the save that followed
    /// was debounced with nothing keeping the app alive long enough to make it. iOS keeps the
    /// app running until this method returns.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo
        let action = DinnerReminderService.action(forActionIdentifier: identifier, userInfo: userInfo)
        let destination = DinnerReminderService.destination(forActionIdentifier: identifier, userInfo: userInfo)

        await MainActor.run {
            let application = UIApplication.shared
            let backgroundTask = application.beginBackgroundTask(withName: "Reminder response")
            defer { if backgroundTask != .invalid { application.endBackgroundTask(backgroundTask) } }

            let store = AppStoreHost.shared
            store.rollOverIfNeeded()
            if let action { store.handleReminderAction(action) }
            if let destination {
                AppRouter.shared.open(destination)
                if identifier == DinnerReminderService.planNextWeekActionIdentifier, store.nextWeekPlan == nil {
                    store.planNextWeek()
                }
            }
            store.flushPendingWrites()
        }
    }
}

final class SharingSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard FeatureFlags.householdSyncEnabled, let metadata = options.cloudKitShareMetadata else { return }
        Task { @MainActor in CloudHouseholdSync.shared.received(metadata) }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        guard FeatureFlags.householdSyncEnabled else { return }
        Task { @MainActor in CloudHouseholdSync.shared.received(metadata) }
    }
}
