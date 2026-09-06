import SwiftUI

@main
struct MealShufflerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = AppStore()
    @StateObject private var communityStore = CommunityStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(communityStore)
                .tint(AppTheme.accent)
        }
        .onChange(of: scenePhase) { _, phase in
            // Saves are debounced, so a change made moments before backgrounding would
            // otherwise never reach disk.
            if phase != .active { store.flushPendingWrites() }
        }
    }
}
