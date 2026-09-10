import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var cloud = CloudHouseholdSync.shared
    @State private var showingCloud = false
    @State private var showingBackup = false

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
        .overlay { if store.isGenerating { ProgressView("Planning dinners…").padding(24).background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius: 16)) } }
        .safeAreaInset(edge: .top) {
            if cloud.hasInvitation || cloud.pendingRemote != nil {
                Button("Review iCloud changes") { showingCloud = true }.frame(maxWidth: .infinity, minHeight: 44).background(AppTheme.accentSoft)
            }
        }
        .sheet(isPresented: $showingCloud) {
            NavigationStack { CloudSharingView().environmentObject(store).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { showingCloud = false } } } }
        }
        .sheet(isPresented: $showingBackup) { NavigationStack { DeviceBackupView().environmentObject(store).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { showingBackup = false } } } } }
        .onOpenURL(perform: store.handleIncomingURL)
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

/// Tab labels match the screen titles behind them.
///
/// Settings is a tab of its own now. Notification setup, the family and history all used to
/// be a section inside Rules, which is not a place anyone looks for them. Rules keep their
/// tab: they are the thing the app is about, not a preference.
private struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack { WeekPlanView() }
                .tabItem { Label("Week", systemImage: "calendar") }

            NavigationStack { GroceryListView() }
                .tabItem { Label("Shop", systemImage: "cart") }

            NavigationStack { MealLibraryView() }
                .tabItem { Label("Meals", systemImage: "fork.knife") }

            if FeatureFlags.communityEnabled {
                // Rules move under Settings to make room; five tabs is the limit before iOS
                // collapses the rest into a "More" list nobody opens.
                NavigationStack { CommunityView() }
                    .tabItem { Label("Explore", systemImage: "person.3") }
            } else {
                NavigationStack { RulesView() }
                    .tabItem { Label("Rules", systemImage: "slider.horizontal.3") }
            }

            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
