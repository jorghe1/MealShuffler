import Foundation

/// Seams for MealShufflerUITests. Inert unless XCTest passes the launch arguments, and compiled
/// out of release builds.
enum UITestSupport {
    static var isUITesting: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-ui-testing")
        #else
        return false
        #endif
    }

    static var skipsOnboarding: Bool {
        isUITesting && ProcessInfo.processInfo.arguments.contains("-ui-testing-skip-onboarding")
    }

    /// Starts empty on every launch and never touches the real state file, the widget or
    /// notification permission (the recording scheduler never prompts).
    @MainActor
    static func makeStore() -> AppStore {
        let store = AppStore(
            repository: InMemoryStateRepository(),
            widgetRefresher: RecordingWidgetRefresher(),
            reminderService: RecordingReminderScheduler(authorized: false)
        )
        if skipsOnboarding { store.completeOnboarding() }
        return store
    }
}

/// Keeps state for the life of the process only.
///
/// Not a cleared defaults suite: `UserDefaultsStateRepository` adopts the pre-App-Group state
/// from `UserDefaults.standard` whenever its suite is empty, which would pull a developer's
/// real week back into the test.
final class InMemoryStateRepository: AppStateRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: AppStateSnapshot?

    func load() -> AppStateSnapshot? {
        lock.lock(); defer { lock.unlock() }
        return snapshot
    }

    func save(_ snapshot: AppStateSnapshot) {
        lock.lock(); defer { lock.unlock() }
        self.snapshot = snapshot
    }
}
