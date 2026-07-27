import SwiftUI

@main
struct MealShufflerApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var communityStore = CommunityStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(communityStore)
                .tint(AppTheme.accent)
        }
    }
}
