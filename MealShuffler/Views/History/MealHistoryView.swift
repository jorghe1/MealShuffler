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
                    stat(title: "Laget", value: events.filter { $0.kind == .cooked }.count, symbol: "checkmark.seal.fill")
                    stat(title: "Pauset", value: events.filter { $0.kind == .snoozed }.count, symbol: "calendar.badge.minus")
                }.listRowBackground(Color.clear)
                Text("Historikken påvirker shuffle lokalt: retter dere lager får litt høyere relevans, men det som nylig er laget får en midlertidig repetisjonsstraff.")
                    .font(.caption).foregroundStyle(AppTheme.muted).listRowBackground(Color.clear)
            }

            Section("Aktivitet") {
                if events.isEmpty { Text("Ingen aktivitet ennå.").foregroundStyle(.secondary) }
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
                Section { Button("Tøm historikk", role: .destructive) { showingClear = true } }
            }
        }
        .navigationTitle("Historikk")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Tømme historikken?", isPresented: $showingClear) {
            Button("Tøm", role: .destructive) { store.clearHistory() }
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
        switch event.kind { case .cooked: action = "Laget"; case .skipped: action = "Byttet bort"; case .snoozed: action = "Pauset i 28 dager" }
        return event.weekday.map { "\(action) på \($0.name.lowercased())" } ?? action
    }
}
