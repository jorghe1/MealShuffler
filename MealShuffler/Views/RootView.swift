import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Group {
            if store.hasCompletedOnboarding {
                MainTabView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                OnboardingFlowView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: store.hasCompletedOnboarding)
        .preferredColorScheme(.light)
        .onOpenURL(perform: store.handleIncomingURL)
        .alert("Familieinvitasjon", isPresented: Binding(
            get: { store.inviteNotice != nil },
            set: { if !$0 { store.inviteNotice = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: { Text(store.inviteNotice ?? "") }
    }
}

private struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack { WeekPlanView() }
                .tabItem { Label("Uken", systemImage: "calendar") }

            NavigationStack { GroceryListView() }
                .tabItem { Label("Handle", systemImage: "cart") }

            NavigationStack { MealLibraryView() }
                .tabItem { Label("Retter", systemImage: "fork.knife") }

            NavigationStack { RulesView() }
                .tabItem { Label("Regler", systemImage: "slider.horizontal.3") }

            NavigationStack { CommunityView() }
                .tabItem { Label("Utforsk", systemImage: "person.3") }
        }
    }
}
