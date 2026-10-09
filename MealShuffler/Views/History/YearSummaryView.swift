import SwiftUI

/// The dinner year: how many dinners, how many different ones, the family's favourites, and
/// the picture of it to send to someone.
///
/// Built only from what was marked cooked on this phone; nothing is counted anywhere else.
/// Worth opening in December, and the kind of thing people show each other.
struct YearSummaryView: View {
    @Environment(AppStore.self) private var store
    @State private var year = Calendar.current.component(.year, from: .now)
    @State private var picture: Image?

    private var summary: YearSummary { store.yearSummary(for: year) }

    var body: some View {
        let summary = self.summary
        ScrollView {
            VStack(spacing: AppTheme.Space.l) {
                if summary.dinners == 0 {
                    ContentUnavailableView(
                        "No dinners recorded in \(String(year))",
                        systemImage: "fork.knife",
                        description: Text("Mark dinners as cooked and the year adds up here.")
                    )
                    .padding(.top, AppTheme.Space.xxl)
                } else {
                    YearPoster(summary: summary, household: store.household.name)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
                        .accessibilityElement(children: .combine)
                    if let picture {
                        ShareLink(item: picture, preview: SharePreview(L10n.string("Our dinner year %@", String(year)), image: picture)) {
                            Label("Share the picture", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.primary)
                    }
                }
            }
            .padding(AppTheme.Space.screen)
        }
        .appBackground()
        .navigationTitle(L10n.string("Dinner year %@", String(year)))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Year", selection: $year) {
                        ForEach(years, id: \.self) { Text(String($0)).tag($0) }
                    }
                } label: {
                    Image(systemName: "calendar")
                }
                .accessibilityLabel("Choose year")
            }
        }
        .task(id: year) { render() }
    }

    /// Years with anything cooked in them, and always this one.
    private var years: [Int] {
        let calendar = Calendar.current
        let cooked = store.feedbackEvents.filter { $0.kind == .cooked }
            .map { calendar.component(.year, from: $0.plannedDate ?? $0.timestamp) }
        return Array(Set(cooked + [calendar.component(.year, from: .now)])).sorted(by: >)
    }

    private func render() {
        let summary = self.summary
        guard summary.dinners > 0 else { picture = nil; return }
        let renderer = ImageRenderer(content: YearPoster(summary: summary, household: store.household.name)
            .environment(\.colorScheme, .light))
        renderer.scale = 3
        picture = renderer.uiImage.map { Image(uiImage: $0) }
    }
}

/// The year as a card. Fixed colours, like the week poster: it leaves the app.
struct YearPoster: View {
    let summary: YearSummary
    let household: String

    private static let paper = Color(red: 0.97, green: 0.95, blue: 0.90)
    private static let ink = Color(red: 0.12, green: 0.16, blue: 0.12)
    private static let green = Color(red: 0.12, green: 0.42, blue: 0.28)
    private static let soft = Color(red: 0.82, green: 0.90, blue: 0.80)
    private static let muted = Color(red: 0.39, green: 0.42, blue: 0.36)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("Dinner year %@", String(summary.year)).uppercased())
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(Self.green)
                Text(L10n.string("%ld dinners at home", summary.dinners))
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(Self.ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                stat(summary.distinctDishes, L10n.string("different dishes"))
                stat(summary.newDishes, L10n.string("new this year"))
            }
            HStack(spacing: 8) {
                stat(summary.fish, L10n.string("fish dinners"), emoji: "🐟")
                stat(summary.vegetarian, L10n.string("vegetarian"), emoji: "🥦")
            }

            if !summary.top.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Our favourites")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Self.green)
                    ForEach(Array(summary.top.enumerated()), id: \.element) { index, dish in
                        HStack {
                            Text(["🥇", "🥈", "🥉"][min(index, 2)])
                            Text(dish.name)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(Self.ink)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(L10n.string("%ld×", dish.count))
                                .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(Self.muted)
                        }
                    }
                }
            }

            if let weekday = summary.busiestWeekday {
                Text(L10n.string("Most cooked on: %@", weekday.name))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Self.ink)
            }

            Text("Shuffled with Meal Shuffler")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Self.muted)
        }
        .padding(24)
        .frame(width: 340, alignment: .leading)
        .background(
            ZStack {
                Self.paper
                Circle().fill(Self.soft.opacity(0.7)).frame(width: 220).offset(x: 140, y: -200)
            }
        )
    }

    private func stat(_ value: Int, _ label: String, emoji: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text([emoji, "\(value)"].compactMap { $0 }.joined(separator: " "))
                .font(.system(size: 26, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(Self.ink)
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Self.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
