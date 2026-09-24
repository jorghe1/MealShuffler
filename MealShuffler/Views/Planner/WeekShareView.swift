import SwiftUI

/// The week as a picture, and the ways to send it on.
///
/// The picture is what travels: it reads without the app, in a family chat or a story, and it
/// carries the household's own rules next to the days they decided. The links under it send
/// the things another household can actually use -- this week's recipes and the rules that
/// made the week -- packed inside the link itself, so nothing is uploaded anywhere.
struct WeekShareView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var picture: Image?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    preview
                    if let picture {
                        ShareLink(
                            item: picture,
                            preview: SharePreview(store.weekPoster.heading, image: picture)
                        ) {
                            Label("Share the picture", systemImage: "photo.on.rectangle.angled")
                                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.roundedRectangle(radius: AppTheme.controlRadius))
                    }
                    links
                    Text("Recipes and rules travel inside the link itself. Nothing is uploaded.")
                        .font(.caption).foregroundStyle(AppTheme.muted)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
            }
            .appBackground()
            .navigationTitle("Share this week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { render() }
        }
    }

    @ViewBuilder private var preview: some View {
        if let picture {
            picture.resizable().scaledToFit()
                .frame(maxHeight: 440)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
                .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
                .accessibilityLabel(PlanTextExporter.weeklyPlan(store.plan, meals: store.meals))
        } else {
            ProgressView().frame(height: 440)
        }
    }

    private var links: some View {
        VStack(spacing: 0) {
            ShareLink(item: PlanTextExporter.weeklyPlan(store.plan, meals: store.meals)) {
                Label("Share as text", systemImage: "text.alignleft").shareRow()
            }
            let dinners = store.plannedMeals
            if !dinners.isEmpty, let link = RecipeShare.link(meals: dinners, household: store.household.name) {
                Divider().padding(.leading, 52)
                ShareLink(
                    item: link,
                    subject: Text("This week's recipes"),
                    message: Text(RecipeShare.message(meals: dinners, household: store.household.name))
                ) {
                    Label("Send this week's recipes", systemImage: "book.pages").shareRow()
                }
            }
            if !HouseRulesShare.shareableRules(store.rules, meals: store.meals).isEmpty {
                Divider().padding(.leading, 52)
                ShareLink(
                    item: HouseRulesShare.link(rules: store.rules, household: store.household.name, meals: store.meals),
                    subject: Text("Our house rules"),
                    message: Text(HouseRulesShare.message(rules: store.rules, household: store.household.name, meals: store.meals, context: store.matchContext))
                ) {
                    Label("Send our house rules", systemImage: "list.bullet.clipboard").shareRow()
                }
            }
        }
        .mealCard()
    }

    /// Drawn at three times the point size: 1080 × 1920, a full-screen story.
    private func render() {
        let poster = WeekPoster(content: store.weekPoster).environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: poster)
        renderer.scale = 3
        if let image = renderer.uiImage { picture = Image(uiImage: image) }
    }
}

private extension View {
    func shareRow() -> some View {
        self
            .font(.body.weight(.semibold))
            .foregroundStyle(AppTheme.ink)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
    }
}

/// The picture itself: a 9:16 card with the week, the rules that shaped it and the odds.
///
/// Fixed colours rather than theme tokens: it is an image that leaves the app, so it looks the
/// same whichever appearance the phone that made it was in.
struct WeekPoster: View {
    let content: WeekPosterContent

    private static let paper = Color(red: 0.97, green: 0.95, blue: 0.90)
    private static let ink = Color(red: 0.12, green: 0.16, blue: 0.12)
    private static let green = Color(red: 0.12, green: 0.42, blue: 0.28)
    private static let soft = Color(red: 0.82, green: 0.90, blue: 0.80)
    private static let muted = Color(red: 0.39, green: 0.42, blue: 0.36)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "shuffle")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(Self.paper)
                    .frame(width: 24, height: 24)
                    .background(Self.green)
                    .clipShape(Circle())
                Text(content.weekLabel.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(Self.green)
            }
            Text(content.heading)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(Self.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .padding(.top, 8)

            Spacer(minLength: 12)

            VStack(spacing: 6) {
                ForEach(content.days) { day in row(day) }
            }

            Spacer(minLength: 12)
            footer
        }
        .padding(24)
        .frame(width: 360, height: 640)
        .background(background)
    }

    private var background: some View {
        ZStack {
            Self.paper
            Circle().fill(Self.soft.opacity(0.7)).frame(width: 260).offset(x: 150, y: -290)
            Circle().fill(Self.soft.opacity(0.45)).frame(width: 180).offset(x: -170, y: 300)
        }
    }

    private func row(_ day: WeekPosterContent.Day) -> some View {
        HStack(spacing: 10) {
            Text(day.day.shortName.uppercased())
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(Self.green)
                .frame(width: 34, alignment: .leading)
            MealArtwork(emoji: day.emoji, imageURL: nil, tags: day.tags)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(day.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Self.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                if let badge = day.badge {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark").font(.system(size: 8, weight: .black))
                        Text(badge).font(.system(size: 10, weight: .bold, design: .rounded)).lineLimit(1)
                    }
                    .foregroundStyle(Self.green)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Self.soft)
                    .clipShape(Capsule())
                }
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .background(Color.white.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                if content.rulesKept > 0 {
                    Label(L10n.string("%ld rules kept", content.rulesKept), systemImage: "checkmark.seal.fill")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Self.green)
                }
                Text(content.mix.joined(separator: "  "))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Self.ink)
            }
            Text(L10n.string("1 of %@ possible weeks", content.possibleWeeksText))
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(Self.ink)
            Text("Shuffled with Meal Shuffler")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Self.muted)
        }
    }
}
