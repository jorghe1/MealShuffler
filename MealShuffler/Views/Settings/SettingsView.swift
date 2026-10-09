import SwiftUI
import UIKit

/// The preferences a household opens a few times a year, behind the gear in Family.
///
/// This used to be a tab holding everything that was not planning: the freezer, collections
/// and history (which are content, and live in Meals now), the shop's aisle order and pantry
/// staples (which belong to the shopping list, in its ⋯ menu), the family (its own tab), and
/// reminders at the very bottom, under backups.
struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var showingResetConfirmation = false

    private var appVersion: String {
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "Unknown"
        let buildNumber = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "Unknown"
        return "\(version) (\(buildNumber))"
    }

    var body: some View {
        List {
            Section {
                NavigationLink { ReminderSettingsView() } label: { Label("Reminders", systemImage: "bell") }
            }

            PlanningAidsSection()

            Section {
                OnlineExtractionSettingsView()
            } header: {
                Text("Recipe imports")
            }

            Section {
                NavigationLink { DeviceBackupView() } label: { Label("Backup", systemImage: "externaldrive.fill") }
                NavigationLink { LibraryTransferView() } label: { Label("Export recipes", systemImage: "square.and.arrow.up.on.square") }
            } header: {
                Text("Your data")
            } footer: {
                Text("A backup keeps everything, including photos and history. Exporting recipes makes a file another household can import.")
            }

            Section {
                NavigationLink { PrivacyView() } label: { Label("Privacy", systemImage: "hand.raised") }
                Button("Show the introduction again") { showingResetConfirmation = true }
                LabeledContent("Version", value: appVersion)
            } header: {
                Text("About")
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
    }
}

/// When the app may interrupt the household. At most one notification a day.
struct ReminderSettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var showingPermissionHelp = false

    var body: some View {
        List {
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

                    Toggle(isOn: Bindable(store).prepLeadReminderEnabled) {
                        Label("Time to start cooking", systemImage: "timer")
                    }
                    if store.prepLeadReminderEnabled {
                        Picker(selection: Bindable(store).householdTools.dinnerHour) {
                            ForEach(HourOption.all, id: \.self) { Text(HourOption.label($0)).tag($0) }
                        } label: {
                            Label("Dinner time", systemImage: "fork.knife")
                        }
                    }
                }
            } header: {
                Text("Dinner")
            } footer: {
                Text("Tells you what tonight's dinner is, and follows the plan when a day changes. With start-cooking on, it comes when it is time to start instead. The evening before a dinner from the freezer, it says to take it out.")
            }

            Section {
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
                    Picker(selection: Bindable(store).groceryReminderWeekday) {
                        ForEach(Weekday.ordered()) { Text($0.name).tag($0) }
                    } label: {
                        Label("Day", systemImage: "calendar")
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
                Text("Shopping")
            } footer: {
                Text("At most one notification a day. On shopping day it also says what is for dinner, and on the last day of the week it says if next week is still empty.")
            }
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Notifications are off", isPresented: $showingPermissionHelp) {
            Button("Open Settings") { openSystemSettings() }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Meal Shuffler needs permission to send reminders. You can turn it on in iOS Settings.")
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

/// The calendar and the shuffle sound: things this phone does, not the household's state, so
/// they live in this device's defaults rather than the synced plan.
private struct PlanningAidsSection: View {
    @Environment(AppStore.self) private var store
    @AppStorage(CalendarBusyEvenings.enabledKey) private var calendarEnabled = false
    @AppStorage(CalendarBusyEvenings.minutesKey) private var calendarMinutes = CalendarBusyEvenings.defaultMinutes
    @AppStorage(ShuffleSound.enabledKey) private var soundEnabled = false
    @State private var accessDenied = false

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { calendarEnabled }, set: setCalendar)) {
                Label("Quick dinners on busy evenings", systemImage: "calendar.badge.clock")
            }
            if calendarEnabled {
                Stepper(value: $calendarMinutes, in: 10...60, step: 5) {
                    LabeledContent("Time limit", value: L10n.string("%ld min", calendarMinutes))
                }
                .onChange(of: calendarMinutes) { _, _ in calendarChanged() }
            }
            Toggle(isOn: Binding(
                get: { store.householdTools.sharesIngredients ?? false },
                set: { store.householdTools.sharesIngredients = $0 }
            )) {
                Label("Fewer things to buy", systemImage: "cart")
            }
            Toggle(isOn: $soundEnabled) {
                Label("Sound when shuffling", systemImage: "speaker.wave.2")
            }
        } header: {
            Text("Planning")
        } footer: {
            if accessDenied {
                Text("Meal Shuffler has no access to your calendar. Turn it on in the Settings app under Meal Shuffler → Calendars.")
            } else {
                Text("With the calendar on, an evening with something in it around dinner gets a dinner that is ready in time. The calendar is only read on this phone; nothing is changed or sent. Fewer things to buy prefers dinners that share ingredients.")
            }
        }
    }

    private func setCalendar(_ enabled: Bool) {
        guard enabled else {
            calendarEnabled = false
            calendarChanged()
            return
        }
        Task { @MainActor in
            let granted = await CalendarBusyEvenings.requestAccess()
            accessDenied = !granted
            calendarEnabled = granted
            calendarChanged()
        }
    }

    private func calendarChanged() {
        store.calendarChanged()
    }
}
