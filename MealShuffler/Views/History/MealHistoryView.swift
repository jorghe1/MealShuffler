import SwiftUI

struct MealHistoryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingClear = false

    private var events: [MealFeedbackEvent] {
        store.feedbackEvents.sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    stat(title: L10n.string("Cooked"), value: events.filter { $0.kind == .cooked }.count, symbol: "checkmark.seal.fill")
                    stat(title: L10n.string("Paused"), value: events.filter { $0.kind == .snoozed }.count, symbol: "calendar.badge.minus")
                }.listRowBackground(Color.clear)
                Text("History affects shuffle locally: meals you cook become slightly more relevant, while recently cooked meals temporarily receive a repetition penalty.")
                    .font(.caption).foregroundStyle(AppTheme.muted).listRowBackground(Color.clear)
            }

            Section("Activity") {
                if events.isEmpty { Text("No activity yet.").foregroundStyle(.secondary) }
                ForEach(events) { event in
                    if let meal = store.meal(id: event.mealID) {
                        HStack(spacing: 12) {
                            Text(meal.emoji).font(.title2).frame(width: 40, height: 40).background(AppTheme.accentSoft).clipShape(RoundedRectangle(cornerRadius: 11))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(meal.name).font(.headline)
                                Text(eventLabel(event)).font(.caption).foregroundStyle(AppTheme.muted)
                            }
                            Spacer()
                            Text(event.timestamp, format: .dateTime.day().month(.abbreviated)).font(.caption).foregroundStyle(AppTheme.muted)
                        }
                    }
                }
            }
            if !events.isEmpty {
                Section { Button("Clear history", role: .destructive) { showingClear = true } }
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Clear history?", isPresented: $showingClear) {
            Button("Clear", role: .destructive) { store.clearHistory() }
        }
    }

    private func stat(title: String, value: Int, symbol: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol).font(.title2).foregroundStyle(AppTheme.accent)
            Text("\(value)").font(.title2.bold())
            Text(title).font(.caption).foregroundStyle(AppTheme.muted)
        }.frame(maxWidth: .infinity).padding(14).mealCard()
    }

    private func eventLabel(_ event: MealFeedbackEvent) -> String {
        let action: String
        switch event.kind {
        case .cooked: action = L10n.string("Cooked")
        case .skipped: action = L10n.string("Replaced")
        case .snoozed: action = L10n.string("Paused for 28 days")
        }
        return event.weekday.map { L10n.string("%@ on %@", action, $0.name.lowercased()) } ?? action
    }
}
