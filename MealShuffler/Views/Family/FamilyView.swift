import SwiftUI

/// The household: who is in it, the rules it lives by, what each person likes, and when the
/// app may interrupt it.
///
/// These were spread over two tabs and three levels. Rules had a tab of their own; the people
/// were Settings → Family → a member, three taps from telling the app that Emma does not eat
/// fish; reminders sat at the bottom of Settings under backups and import. Settings itself --
/// backups, recipe reading, privacy -- is a gear here now, because it is opened a few times a
/// year.
struct FamilyView: View {
    @Environment(AppStore.self) private var store
    @State private var showingAddMember = false
    @State private var newMemberName = ""
    @State private var renaming = false
    @State private var householdName = ""
    @State private var showingShare = false
    @State private var kidsMember: HouseholdMember?
    @State private var showingBoard = false

    private var enabledRules: [PlanningRule] { store.rules.filter(\.isEnabled) }

    var body: some View {
        List {
            Section {
                householdCard
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            Section {
                Stepper(
                    L10n.string("%ld people at dinner", store.householdSize),
                    value: Binding(get: { store.householdSize }, set: { store.setHouseholdSize($0) }),
                    in: 1...20
                )
            } footer: {
                Text("Used for portions and shopping quantities.")
            }

            Section {
                ForEach(store.rules.prefix(4)) { rule in
                    RuleSummaryRow(rule: rule)
                }
                NavigationLink {
                    RulesView()
                } label: {
                    Label(
                        store.rules.isEmpty ? L10n.string("Write your first rule") : L10n.string("All %ld rules", store.rules.count),
                        systemImage: "list.bullet"
                    )
                    .foregroundStyle(AppTheme.accent)
                }
                .accessibilityIdentifier("family.allRules")
            } header: {
                Text("House rules")
            } footer: {
                if !store.rules.isEmpty {
                    Text(L10n.string("%ld of %ld rules are on.", enabledRules.count, store.rules.count))
                }
            }

            Section("Tastes") {
                ForEach(store.household.members) { member in
                    NavigationLink {
                        MemberTasteView(member: member)
                    } label: {
                        HStack(spacing: AppTheme.Space.m) {
                            MemberAvatar(member: member, index: memberIndex(member), size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(member.displayName).foregroundStyle(AppTheme.ink)
                                Text(tasteSummary(for: member))
                                    .font(.caption).foregroundStyle(AppTheme.muted).lineLimit(1)
                            }
                        }
                    }
                }
                .onDelete(perform: store.removeHouseholdMembers)
                Button { showingAddMember = true } label: {
                    Label("Add member", systemImage: "person.badge.plus")
                }
            }

            wishesSection

            Section {
                if store.household.members.count == 1, let only = store.household.members.first {
                    Button { kidsMember = only } label: {
                        Label("Kids view", systemImage: "face.smiling")
                    }
                } else {
                    Menu {
                        ForEach(store.household.members) { member in
                            Button(member.displayName) { kidsMember = member }
                        }
                    } label: {
                        Label("Kids view", systemImage: "face.smiling")
                    }
                }
                Button { showingBoard = true } label: {
                    Label("Kitchen board", systemImage: "rectangle.split.3x1")
                }
                NavigationLink { YearSummaryView() } label: {
                    Label(L10n.string("Dinner year %@", String(Calendar.current.component(.year, from: .now))),
                          systemImage: "sparkles")
                }
            } header: {
                Text("Together")
            } footer: {
                Text("The kids view lets a child see the week, vote on dishes and wish for one. Leaving it needs the phone's code. The kitchen board keeps the week on screen on an iPad.")
            }

            Section {
                NavigationLink {
                    ReminderSettingsView()
                } label: {
                    LabeledContent {
                        Text(reminderSummary).lineLimit(1)
                    } label: {
                        Label("Reminders", systemImage: "bell")
                    }
                }
                Button { showingShare = true } label: {
                    Label("Share this week", systemImage: "square.and.arrow.up")
                }
                if !HouseRulesShare.shareableRules(store.rules, meals: store.meals).isEmpty {
                    ShareLink(
                        item: HouseRulesShare.link(rules: store.rules, household: store.household.name, meals: store.meals),
                        subject: Text("Our house rules"),
                        message: Text(HouseRulesShare.message(rules: store.rules, household: store.household.name,
                                                              meals: store.meals, context: store.matchContext))
                    ) {
                        Label("Share our house rules", systemImage: "list.bullet.clipboard")
                    }
                }
                if FeatureFlags.householdSyncEnabled {
                    NavigationLink { CloudSharingView() } label: { Label("iCloud sharing", systemImage: "icloud") }
                }
                if FeatureFlags.communityEnabled {
                    NavigationLink { CommunityHost() } label: { Label("Explore", systemImage: "person.3") }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle("Family")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
                    .accessibilityIdentifier("family.settings")
            }
        }
        .sheet(isPresented: $showingShare) { WeekShareView().environment(store) }
        .fullScreenCover(item: $kidsMember) { member in
            KidsView(member: member).environment(store)
        }
        .fullScreenCover(isPresented: $showingBoard) {
            KitchenBoardView().environment(store)
        }
        .alert("New family member", isPresented: $showingAddMember) {
            TextField("Name", text: $newMemberName)
            Button("Add") { store.addHouseholdMember(named: newMemberName); newMemberName = "" }
            Button("Cancel", role: .cancel) { newMemberName = "" }
        }
        .alert("Household name", isPresented: $renaming) {
            TextField("Name", text: $householdName)
            Button("Save") { commitName() }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// What the kids asked for in their view. A grown-up puts it on a day of next week or lets
    /// it go; either way the child sees it was heard the next time a wish is made.
    @ViewBuilder private var wishesSection: some View {
        let wishes = store.pendingWishes.compactMap { wish -> (wish: MealWish, member: HouseholdMember, meal: Meal)? in
            guard let member = store.household.members.first(where: { $0.id == wish.memberID }),
                  let meal = store.meal(id: wish.mealID) else { return nil }
            return (wish: wish, member: member, meal: meal)
        }
        if !wishes.isEmpty {
            Section {
                ForEach(wishes, id: \.wish.id) { entry in
                    HStack(spacing: AppTheme.Space.m) {
                        MealThumbnail(meal: entry.meal, size: AppTheme.rowThumbnail)
                        Text(L10n.string("%@ wishes for %@", entry.member.displayName, entry.meal.name))
                            .foregroundStyle(AppTheme.ink)
                        Spacer(minLength: 0)
                        Menu {
                            Section("Put on next week") {
                                ForEach(Weekday.ordered()) { day in
                                    Button(day.name) {
                                        Haptics.success()
                                        store.resolveWish(entry.wish, plannedOn: day)
                                    }
                                }
                            }
                            Button("Not this time", role: .destructive) {
                                store.resolveWish(entry.wish, plannedOn: nil)
                            }
                        } label: {
                            Image(systemName: "calendar.badge.plus").iconButtonFrame()
                        }
                        .accessibilityLabel("Answer the wish")
                    }
                }
            } header: {
                Text("Wishes")
            }
        }
    }

    private var householdCard: some View {
        HStack(spacing: AppTheme.Space.m) {
            HStack(spacing: -10) {
                ForEach(Array(store.household.members.prefix(5).enumerated()), id: \.element.id) { index, member in
                    MemberAvatar(member: member, index: index, size: 40)
                        .overlay(Circle().stroke(AppTheme.surface, lineWidth: 2))
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(store.household.name)
                    .font(.headline).foregroundStyle(AppTheme.ink)
                Text(store.household.members.count == 1
                     ? L10n.string("1 person")
                     : L10n.string("%ld people", store.household.members.count))
                    .font(.subheadline).foregroundStyle(AppTheme.muted)
            }
            Spacer(minLength: AppTheme.Space.s)
            Button {
                householdName = store.household.name
                renaming = true
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.icon)
            .accessibilityLabel("Rename household")
        }
        .padding(AppTheme.Space.l)
        .mealCard()
    }

    private func memberIndex(_ member: HouseholdMember) -> Int {
        store.household.members.firstIndex { $0.id == member.id } ?? 0
    }

    /// "Liker ikke Laks i ovn, Taco" -- the first few dishes this person swiped left on.
    private func tasteSummary(for member: HouseholdMember) -> String {
        let opinions = store.memberPreferences[member.id] ?? [:]
        let disliked = opinions.filter { $0.value == .disliked }.keys.compactMap { store.meal(id: $0)?.name }.sorted()
        let liked = opinions.filter { $0.value == .liked }.count
        if !disliked.isEmpty {
            let shown = disliked.prefix(2).joined(separator: ", ")
            return disliked.count > 2
                ? L10n.string("Dislikes %@ and %ld more", shown, disliked.count - 2)
                : L10n.string("Dislikes %@", shown)
        }
        return liked > 0 ? L10n.string("Likes %ld dishes", liked) : L10n.string("No tastes saved yet")
    }

    private var reminderSummary: String {
        var parts: [String] = []
        if store.dinnerReminderEnabled { parts.append(HourOption.label(store.dinnerReminderHour)) }
        if store.groceryReminderEnabled { parts.append(store.groceryReminderWeekday.name) }
        return parts.isEmpty ? L10n.string("Off") : parts.joined(separator: " · ")
    }

    private func commitName() {
        let trimmed = householdName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != store.household.name else { return }
        store.renameHousehold(trimmed)
    }
}

/// A rule in a list: the household's own words, what the app understood, and the switch.
struct RuleSummaryRow: View {
    @Environment(AppStore.self) private var store
    let rule: PlanningRule

    var body: some View {
        Toggle(isOn: Binding(
            get: { store.rules.first(where: { $0.id == rule.id })?.isEnabled ?? false },
            set: { store.setRule(rule, enabled: $0) }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: AppTheme.Space.xs) {
                    Text(rule.title).font(.body.weight(.semibold)).foregroundStyle(AppTheme.ink)
                    StrengthTag(strength: rule.strength)
                }
                Text(rule.summary(meals: store.meals, context: store.matchContext))
                    .font(.caption).foregroundStyle(AppTheme.muted)
            }
        }
        .tint(AppTheme.accent)
    }
}

/// "Must" or "If possible", quietly. Two vocabularies used to describe the same thing:
/// "harde/myke regler" in the explanation and "Må følges/Bør følges" on the control.
struct StrengthTag: View {
    let strength: RuleStrength

    var body: some View {
        Text(strength.name)
            .font(.caption2.weight(.bold))
            .textCase(.uppercase)
            .foregroundStyle(strength == .required ? AppTheme.muted : AppTheme.accent)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .overlay(Capsule().stroke(strength == .required ? AppTheme.muted.opacity(0.4) : AppTheme.accent.opacity(0.5)))
            .accessibilityLabel(strength.name)
    }
}

/// A member's initial on a colour of their own.
struct MemberAvatar: View {
    let member: HouseholdMember
    let index: Int
    var size: CGFloat = 32

    private static let colors: [Color] = [
        AppTheme.categoryFish, AppTheme.categoryMeat, AppTheme.categoryChicken,
        AppTheme.categoryOther, AppTheme.categoryVegetarian
    ]

    var body: some View {
        Text(String(member.displayName.prefix(1)).uppercased())
            .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Self.colors[index % Self.colors.count])
            .clipShape(Circle())
            .accessibilityHidden(true)
    }
}

/// One person's tastes, and the rule that keeps their dislikes off the table when they eat.
struct MemberTasteView: View {
    @Environment(AppStore.self) private var store
    let member: HouseholdMember
    @State private var search = ""
    @State private var filter = 0

    private var shownMeals: [Meal] {
        store.meals.filter { meal in
            guard meal.matches(searchText: search) else { return false }
            let preference = store.memberPreferences[member.id]?[meal.id] ?? .neutral
            switch filter {
            case 1: return preference == .liked
            case 2: return preference == .disliked
            default: return true
            }
        }
    }

    var body: some View {
        List {
            Section {
                Button("Avoid these dislikes when present") {
                    let outcome = store.addRule(PlanningRule(title: L10n.string("What %@ dislikes", member.displayName),
                        constraint: .excludedOn(day: .everyDay, matcher: .dislikedBy(memberID: member.id))))
                    switch outcome {
                    case .added: store.actionNotice = L10n.string("Rule added.")
                    case .duplicate(let title): store.actionNotice = L10n.string("This rule already exists: %@", title)
                    case .contradiction(let title): store.actionNotice = L10n.string("This conflicts with: %@", title)
                    case .impossible(let reason): store.actionNotice = reason
                    }
                }
            } footer: {
                Text("Set attendance on a day to apply this person's dislikes only when they are eating.")
            }
            Section {
                Picker("Show", selection: $filter) {
                    Text("All").tag(0)
                    Text("Likes").tag(1)
                    Text("Dislikes").tag(2)
                }
                .pickerStyle(.segmented)
                ForEach(shownMeals) { meal in
                    Picker(selection: Binding(
                        get: { store.memberPreferences[member.id]?[meal.id] ?? .neutral },
                        set: { store.setPreference($0, for: meal, member: member.id) }
                    )) {
                        Text("Like").tag(MealPreference.liked)
                        Text("Neutral").tag(MealPreference.neutral)
                        Text("Dislike").tag(MealPreference.disliked)
                    } label: {
                        HStack(spacing: AppTheme.Space.m) {
                            MealThumbnail(meal: meal, size: 32)
                            Text(meal.name)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle(member.displayName)
        .searchable(text: $search, prompt: "Search meals")
    }
}
