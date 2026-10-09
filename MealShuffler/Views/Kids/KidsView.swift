import LocalAuthentication
import SwiftUI

/// The week for a child: what's for dinner tonight, how to help, a vote on dishes and one wish
/// for next week.
///
/// Children ask "what's for dinner?" more than anyone, and they are the ones who say no at the
/// table. Giving them a say -- a thumbs up or down, one wish a week -- turns that into
/// something the planner can use, and it is a reason for a family to open the app together.
/// Nothing here can change the plan, the rules or the library: leaving needs the phone's own
/// passcode or Face ID, so the phone can be handed over.
struct KidsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let member: HouseholdMember

    @State private var candidates: [Meal] = []
    @State private var choosingWish = false
    @State private var exitFailed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Space.xl) {
                header
                tonight
                helpCard
                weekStrip
                votes
                wishCard
            }
            .padding(AppTheme.Space.screen)
            .padding(.bottom, AppTheme.Space.xxl)
        }
        .appBackground()
        .onAppear {
            // Fixed for the visit, so a vote does not swap the card under a child's finger.
            if candidates.isEmpty { candidates = store.voteCandidates(for: member) }
        }
        .sheet(isPresented: $choosingWish) {
            WishPicker(member: member).environment(store)
        }
        .alert("Ask a grown-up", isPresented: $exitFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Leaving the kids view needs the phone's code.")
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L10n.string("Hi, %@! 👋", member.displayName))
                .font(AppTheme.Typography.display)
                .foregroundStyle(AppTheme.ink)
            Spacer()
            Button(action: leave) {
                Image(systemName: "lock.fill")
            }
            .buttonStyle(.icon)
            .accessibilityLabel("Leave the kids view")
        }
    }

    @ViewBuilder private var tonight: some View {
        let today = todayItem
        VStack(spacing: AppTheme.Space.m) {
            Text("Tonight").eyebrowStyle()
            if let today, today.item.kind == .meal, let meal = today.meal {
                MealArtwork(meal: meal)
                    .frame(width: 168, height: 168)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.heroRadius, style: .continuous))
                    .accessibilityHidden(true)
                Text(meal.name)
                    .font(AppTheme.Typography.display)
                    .foregroundStyle(AppTheme.ink)
                    .multilineTextAlignment(.center)
                if let cook = store.cook(for: today.day) {
                    Text(L10n.string("%@ cooks", cook.displayName))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.muted)
                }
            } else if let today {
                Text(kindEmoji(today.item.kind)).font(.system(size: 96))
                Text(kindTitle(today.item, meal: today.meal))
                    .font(AppTheme.Typography.title)
                    .foregroundStyle(AppTheme.ink)
            } else {
                Text("🤔").font(.system(size: 96))
                Text("Nothing planned tonight yet")
                    .font(AppTheme.Typography.title)
                    .foregroundStyle(AppTheme.ink)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(AppTheme.Space.xl)
        .mealCard()
    }

    @ViewBuilder private var helpCard: some View {
        if let today = todayItem, today.item.kind == .meal, today.meal != nil, !store.isCompleted(on: today.day) {
            let task = KidsHelpTask.task(for: today.meal, day: today.day)
            HStack(spacing: AppTheme.Space.l) {
                Text(task.emoji).font(.system(size: 44))
                VStack(alignment: .leading, spacing: AppTheme.Space.xs) {
                    Text("You can help").eyebrowStyle()
                    Text(task.title)
                        .font(AppTheme.Typography.section)
                        .foregroundStyle(AppTheme.ink)
                }
                Spacer(minLength: 0)
            }
            .padding(AppTheme.Space.l)
            .background(AppTheme.accentSoft)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        }
    }

    private var weekStrip: some View {
        VStack(alignment: .leading, spacing: AppTheme.Space.s) {
            Text("This week").eyebrowStyle()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Space.s) {
                    ForEach(Weekday.ordered(), id: \.self) { day in
                        dayTile(day)
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    private func dayTile(_ day: Weekday) -> some View {
        let item = store.plan[day]
        let meal = item?.freezerBatch?.recipe ?? item?.mealID.flatMap { store.meal(id: $0) }
        let isToday = Calendar.current.isDateInToday(store.plan.date(for: day))
        return VStack(spacing: AppTheme.Space.xs) {
            Text(day.shortName.uppercased())
                .font(.caption.weight(.heavy))
                .foregroundStyle(isToday ? AppTheme.onAccent : AppTheme.muted)
            Group {
                if let item, item.kind == .meal, let meal {
                    MealArtwork(meal: meal)
                } else {
                    Text(item.map { kindEmoji($0.kind) } ?? "·").font(.system(size: 30))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(AppTheme.raised)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
        }
        .padding(AppTheme.Space.s)
        .background(isToday ? AppTheme.accent : AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([day.name, meal?.name ?? item.map { kindTitle($0, meal: meal) } ?? L10n.string("Not planned")].joined(separator: ", "))
    }

    @ViewBuilder private var votes: some View {
        if !candidates.isEmpty {
            VStack(alignment: .leading, spacing: AppTheme.Space.m) {
                Text("Do you like these?").font(AppTheme.Typography.section).foregroundStyle(AppTheme.ink)
                ForEach(candidates) { meal in
                    VoteRow(meal: meal, vote: store.memberPreferences[member.id]?[meal.id]) { preference in
                        Haptics.check()
                        store.setPreference(preference, for: meal, member: member.id)
                    }
                }
            }
        }
    }

    private var wishCard: some View {
        let wish = store.wish(from: member)
        let wished = wish.flatMap { store.meal(id: $0.mealID) }
        return VStack(alignment: .leading, spacing: AppTheme.Space.m) {
            Text("Wish for next week").font(AppTheme.Typography.section).foregroundStyle(AppTheme.ink)
            if let wished {
                HStack(spacing: AppTheme.Space.m) {
                    MealArtwork(meal: wished)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("You wished for").font(.caption).foregroundStyle(AppTheme.muted)
                        Text(wished.name).font(.headline).foregroundStyle(AppTheme.ink)
                    }
                    Spacer(minLength: 0)
                }
            }
            Button { choosingWish = true } label: {
                Label(wished == nil ? L10n.string("Wish for a dinner") : L10n.string("Change my wish"), systemImage: "star")
            }
            .buttonStyle(.primary)
            Text("A grown-up decides which day it goes on.")
                .font(.footnote).foregroundStyle(AppTheme.muted)
        }
        .padding(AppTheme.Space.l)
        .mealCard()
    }

    // MARK: - Helpers

    private var todayItem: (day: Weekday, item: PlannedMeal, meal: Meal?)? {
        guard let day = Weekday.ordered().first(where: { Calendar.current.isDateInToday(store.plan.date(for: $0)) }),
              let item = store.plan[day] else { return nil }
        return (day: day, item: item, meal: item.freezerBatch?.recipe ?? item.mealID.flatMap { store.meal(id: $0) })
    }

    private func kindEmoji(_ kind: PlannedMealKind) -> String {
        switch kind {
        case .meal: "🍽️"
        case .leftovers: "♻️"
        case .away: "🏃"
        case .takeaway: "🥡"
        }
    }

    private func kindTitle(_ item: PlannedMeal, meal: Meal?) -> String {
        switch item.kind {
        case .meal: meal?.name ?? L10n.string("Not planned")
        case .leftovers: meal.map { L10n.string("Leftovers: %@", $0.name) } ?? L10n.string("Leftovers")
        case .away: L10n.string("No dinner at home")
        case .takeaway: L10n.string("Takeaway")
        }
    }

    /// The phone's own code or Face ID: nothing new for a parent to remember, and nothing a
    /// child can guess. On a device with no code at all there is nothing to protect.
    private func leave() {
        let context = LAContext()
        var error: NSError?
        guard !UITestSupport.isUITesting,
              context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            dismiss()
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication,
                               localizedReason: L10n.string("Leave the kids view")) { success, _ in
            DispatchQueue.main.async {
                if success { dismiss() } else { exitFailed = true }
            }
        }
    }
}

/// One dish to rate with a thumb.
private struct VoteRow: View {
    let meal: Meal
    let vote: MealPreference?
    let choose: (MealPreference) -> Void

    var body: some View {
        HStack(spacing: AppTheme.Space.m) {
            MealArtwork(meal: meal)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
                .accessibilityHidden(true)
            Text(meal.name)
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
                .lineLimit(2)
            Spacer(minLength: AppTheme.Space.s)
            thumb("👎", preference: .disliked, label: L10n.string("Don't like it"))
            thumb("👍", preference: .liked, label: L10n.string("Like it"))
        }
        .padding(AppTheme.Space.m)
        .mealCard()
    }

    private func thumb(_ emoji: String, preference: MealPreference, label: String) -> some View {
        Button { choose(preference) } label: {
            Text(emoji)
                .font(.system(size: 30))
                .frame(width: 54, height: 54)
                .background(vote == preference ? AppTheme.accentSoft : AppTheme.raised)
                .clipShape(Circle())
                .overlay(Circle().stroke(vote == preference ? AppTheme.accent : .clear, lineWidth: 3))
                .opacity(vote == nil || vote == preference ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(vote == preference ? .isSelected : [])
    }
}

/// Every dish as a big picture to point at.
private struct WishPicker: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let member: HouseholdMember

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: AppTheme.Space.m)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: AppTheme.Space.m) {
                    ForEach(store.meals.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }) { meal in
                        Button {
                            Haptics.success()
                            store.addWish(meal, from: member)
                            dismiss()
                        } label: {
                            VStack(spacing: AppTheme.Space.s) {
                                MealArtwork(meal: meal)
                                    .aspectRatio(1, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
                                Text(meal.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.ink)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(AppTheme.Space.screen)
            }
            .appBackground()
            .navigationTitle("Wish for a dinner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

/// Something a child can do for tonight's dinner, matched loosely to the dish and varied by
/// day so it is not "set the table" every evening.
enum KidsHelpTask {
    struct Chore: Equatable {
        let emoji: String
        let title: String
    }

    static func task(for meal: Meal?, day: Weekday) -> Chore {
        var options = [
            Chore(emoji: "🍽️", title: L10n.string("Set the table")),
            Chore(emoji: "🥒", title: L10n.string("Wash the vegetables")),
            Chore(emoji: "🥄", title: L10n.string("Stir the pot")),
            Chore(emoji: "💧", title: L10n.string("Fill the water jug"))
        ]
        let text = TextFolding.fold(([meal?.name ?? ""] + (meal?.ingredients.map(\.name) ?? [])).joined(separator: " "))
        if text.contains("taco") || text.contains("tortilla") || text.contains("wrap") {
            options.append(Chore(emoji: "🧀", title: L10n.string("Grate the cheese")))
        }
        if text.contains("pizza") {
            options.append(Chore(emoji: "🍕", title: L10n.string("Put the toppings on")))
        }
        if text.contains("salat") || text.contains("salad") {
            options.append(Chore(emoji: "🥗", title: L10n.string("Toss the salad")))
        }
        // The dish's own task first, otherwise the day picks one.
        if options.count > 4 { return options[options.count - 1] }
        return options[Weekday.position(of: day) % options.count]
    }
}
