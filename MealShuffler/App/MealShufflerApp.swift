import SwiftUI

@main
struct MealShufflerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    /// Handles notification responses, background refresh and iCloud invitations before the
    /// first scene appears.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AppStoreHost.shared
    @StateObject private var router = AppRouter.shared
    @StateObject private var communityStore = CommunityStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(router)
                .environmentObject(communityStore)
                .tint(AppTheme.accent)
                .task(id: scenePhase) {
                    // Off for the first release; see FeatureFlags.householdSyncEnabled.
                    guard FeatureFlags.householdSyncEnabled, scenePhase == .active else { return }
                    while !Task.isCancelled {
                        await CloudHouseholdSync.shared.sync(store: store)
                        do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // A plan left open across a week boundary is stale on return.
                store.rollOverIfNeeded()
                store.refreshPendingCaptures()
                // Nothing in the plan may have changed while the app was away, but the
                // notification permission or the language may have: schedule again from it.
                store.refreshRemindersAndWidget()
            case .background:
                // Saves are debounced, so a change made moments before backgrounding would
                // otherwise never reach disk.
                store.flushPendingWrites()
                BackgroundRefresh.schedule(for: store)
            default:
                store.flushPendingWrites()
            }
        }
    }
}
