import SwiftUI
import UIKit

/// Everything that is not planning, in one place.
///
/// Reminders, the family, history and the shop's aisle order all used to live in a section
/// called "Settings" *inside the Rules tab*, which is not a place anyone looks for
/// notification setup. Rules keep their own tab -- they are what the app is about -- and
/// everything around them moved here.
struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingResetConfirmation = false
    @State private var showingPermissionHelp = false

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }

    var body: some View {
        List {
            Section("Household") {
                NavigationLink { HouseholdView() } label: {
                    Label("Family", systemImage: "person.2")
                }
                NavigationLink { MealHistoryView() } label: {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                NavigationLink { AisleOrderView() } label: {
                    Label("Shop order", systemImage: "arrow.up.arrow.down")
                }
                NavigationLink { PantryStaplesView() } label: {
                    Label("Pantry staples", systemImage: "cabinet")
                }
                if FeatureFlags.communityEnabled {
                    NavigationLink { RulesView() } label: {
                        Label("Rules", systemImage: "slider.horizontal.3")
                    }
                }
            }

            reminderSection

            Section {
                Button("Show onboarding again") { showingResetConfirmation = true }
                    .foregroundStyle(AppTheme.warning)
                LabeledContent("Version", value: appVersion)
            } header: {
                Text("About")
            } footer: {
                Text("Everything is stored on this device. Nothing is sent anywhere unless you import a recipe from a link or a photo.")
            }
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Start onboarding again?", isPresented: $showingResetConfirmation) {
            Button("Start over", role: .destructive) { store.resetForPreview() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Rules and custom meals are kept, but taste choices and the weekly plan are reset.")
        }
        .alert("Notifications are off", isPresented: $showingPermissionHelp) {
            Button("Open Settings") { openSystemSettings() }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Meal Shuffler needs permission to send reminders. You can turn it on in iOS Settings.")
        }
    }

    private var reminderSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { store.dinnerReminderEnabled },
                set: { wanted in
                    Task { @MainActor in
                        let granted = await store.setDinnerReminder(enabled: wanted)
                        if wanted && !granted { showingPermissionHelp = true }
                    }
                }
            )) {
                Label("What's for dinner", systemImage: "bell")
            }

            if store.dinnerReminderEnabled {
                Picker(selection: Binding(
                    get: { store.dinnerReminderHour },
                    set: { store.setDinnerReminderHour($0) }
                )) {
                    ForEach(HourOption.all, id: \.self) { hour in
                        Text(HourOption.label(hour)).tag(hour)
                    }
                } label: {
                    Label("Reminder time", systemImage: "clock")
                }

                Toggle(isOn: $store.prepLeadReminderEnabled) {
                    Label("Time to start cooking", systemImage: "timer")
                }
            }

            Toggle(isOn: Binding(
                get: { store.groceryReminderEnabled },
                set: { wanted in
                    Task { @MainActor in
                        let granted = await store.setGroceryReminder(enabled: wanted)
                        if wanted && !granted { showingPermissionHelp = true }
                    }
                }
            )) {
                Label("Shopping day", systemImage: "cart")
            }

            if store.groceryReminderEnabled {
                Picker(selection: $store.groceryReminderWeekday) {
                    ForEach(Weekday.ordered()) { Text($0.name).tag($0) }
                } label: {
                    Label("Shopping day", systemImage: "calendar")
                }
                Picker(selection: Binding(
                    get: { store.groceryReminderHour },
                    set: { store.setGroceryReminderHour($0) }
                )) {
                    ForEach(HourOption.all, id: \.self) { hour in
                        Text(HourOption.label(hour)).tag(hour)
                    }
                } label: {
                    Label("Reminder time", systemImage: "clock")
                }
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("The dinner reminder tells you what tonight's meal is, and follows the plan when you reshuffle a day. When next week is empty you get one nudge to plan it.")
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

/// The hours a household plausibly eats or shops, formatted without a locale surprise.
enum HourOption {
    static let all = Array(5...22)

    static func label(_ hour: Int) -> String {
        let calendar = Calendar.current
        // Anchored to a real day so the 12/24-hour format follows the locale rather than
        // whatever a bare hour component resolves to.
        guard let date = calendar.date(
            byAdding: .hour, value: hour, to: calendar.startOfDay(for: .now)
        ) else {
            return String(format: "%02d:00", hour)
        }
        return date.formatted(date: .omitted, time: .shortened)
    }
}
