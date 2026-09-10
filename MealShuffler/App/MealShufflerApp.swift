import SwiftUI

@main
struct MealShufflerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    /// Handles notification actions and iCloud invitations before the first scene appears.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore()
    @StateObject private var communityStore = CommunityStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(communityStore)
                .tint(AppTheme.accent)
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    while !Task.isCancelled {
                        await CloudHouseholdSync.shared.sync(store: store)
                        do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    }
                }
                .task {
                    // Drains anything that arrived while the scene was still building, which
                    // is the normal case when the app is launched *by* a notification action.
                    appDelegate.setActionHandler { [store] action in
                        store.handleReminderAction(action)
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // A plan left open across a week boundary is stale on return.
                store.rollOverIfNeeded()
                store.refreshPendingCaptures()
            } else {
                // Saves are debounced, so a change made moments before backgrounding would
                // otherwise never reach disk.
                store.flushPendingWrites()
            }
        }
    }
}
