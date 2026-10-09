import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store
    @EnvironmentObject private var router: AppRouter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var cloud = CloudHouseholdSync.shared
    @State private var showingCloud = false
    @State private var showingBackup = false
    /// Only for a draw slow enough to notice. A shuffle usually takes a fraction of a second,
    /// and flashing a blocking spinner over the reels made the fast case feel slow.
    @State private var showingPlanningOverlay = false

    var body: some View {
        Group {
            if store.hasCompletedOnboarding {
                MainTabView()
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
            } else {
                OnboardingFlowView()
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: store.hasCompletedOnboarding)
        .disabled(store.isGenerating)
        .overlay { if showingPlanningOverlay { ProgressView("Planning dinners…").padding(24).background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius: 16)) } }
        .task(id: store.isGenerating) {
            guard store.isGenerating else { showingPlanningOverlay = false; return }
            try? await Task.sleep(for: .milliseconds(600))
            if !Task.isCancelled, store.isGenerating { showingPlanningOverlay = true }
        }
        .safeAreaInset(edge: .top) {
            if FeatureFlags.householdSyncEnabled, cloud.hasInvitation || cloud.pendingRemote != nil {
                Button("Review iCloud changes") { showingCloud = true }.frame(maxWidth: .infinity, minHeight: 44).background(AppTheme.accentSoft)
            }
        }
        .sheet(isPresented: $showingCloud) {
            NavigationStack { CloudSharingView().environment(store).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { showingCloud = false } } } }
        }
        .sheet(isPresented: $showingBackup) { NavigationStack { DeviceBackupView().environment(store).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { showingBackup = false } } } } }
        .onOpenURL { url in
            // The widget's and notifications' own links move the app; anything else is a
            // shared recipe, rule list or week.
            if !router.open(url) { store.handleIncomingURL(url) }
        }
        .sheet(item: Bindable(store).incomingShare) { share in
            IncomingShareView(share: share).environment(store)
        }
        .alert("Meal plan", isPresented: Binding(get: { store.actionNotice != nil }, set: { if !$0 { store.actionNotice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(store.actionNotice ?? "") }
        .alert("Storage needs attention", isPresented: Binding(
            get: { store.persistenceError != nil }, set: { if !$0 { store.persistenceError = nil } }
        )) {
            Button("Try again") { store.flushPendingWrites() }
            Button("Full backups") { showingBackup = true }
            Button("OK", role: .cancel) {}
        } message: { Text(store.persistenceError ?? "") }
        .alert("Family invitation", isPresented: Binding(
            get: { store.inviteNotice != nil },
            set: { if !$0 { store.inviteNotice = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: { Text(store.inviteNotice ?? "") }
    }
}

/// Four tabs, in the order of the weekly loop: plan the week, pick dishes, shop, and the
/// family the rules belong to.
///
/// Settings was a tab of its own and Rules another. Settings is a gear inside Family now --
/// preferences are opened a few times a year -- and rules live with the family, while the Week
/// screen shows the active ones as chips right where they shape the week.
private struct MainTabView: View {
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        TabView(selection: $router.tab) {
            NavigationStack { WeekPlanView() }
                .tabItem { Label("Week", systemImage: "calendar") }
                .tag(AppTab.week)

            NavigationStack { MealLibraryView() }
                .tabItem { Label("Meals", systemImage: "fork.knife") }
                .tag(AppTab.meals)

            NavigationStack { GroceryListView() }
                .tabItem { Label("Shop", systemImage: "cart") }
                .tag(AppTab.shop)

            NavigationStack { FamilyView() }
                .tabItem { Label("Family", systemImage: "person.2") }
                .tag(AppTab.family)
        }
    }
}
