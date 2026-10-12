import SwiftUI

/// The household: who is in it, when they eat at home, what they like, and the rules it lives
/// by -- "who are we, and what do we like?" (see docs/NAVIGATION.md).
///
/// These were spread over two tabs and three levels. Rules had a tab of their own; the people
/// were Settings → Family → a member, three taps from telling the app that Emma does not eat
/// fish. 0.6 then gathered too much here: reminders and sharing the week sat in this list as
/// well as in Settings and on the week. Each now has one place, and Settings -- reminders,
/// backups, recipe reading, privacy -- is the gear, because it is opened a few times a year.
struct FamilyView: View {
    @Environment(AppStore.self) private var store
    @State private var showingAddMember = false
    @State private var newMemberName = ""
    @State private var renaming = false
    @State private var householdName = ""
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

            peopleSection

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

            wishesSection

            Section {
                kidsViewEntry
                // A landscape iPad screen; on a phone it was one more row nobody would use.
                if UIDevice.current.userInterfaceIdiom == .pad {
                    Button { showingBoard = true } label: {
                        Label("Kitchen board", systemImage: "rectangle.split.3x1")
                    }
                }
                NavigationLink { YearSummaryView() } label: {
                    Label(L10n.string("Dinner year %@", String(Calendar.current.component(.year, from: .now))),
                          systemImage: "sparkles")
                }
            } header: {
                Text("Together")
            } footer: {
                Text("The kids view lets a child see the week, vote on dishes and wish for one. Leaving it needs the phone's code.")
            }

            if FeatureFlags.householdSyncEnabled || FeatureFlags.communityEnabled {
                Section {
                    if FeatureFlags.householdSyncEnabled {
                        NavigationLink { CloudSharingView() } label: { Label("iCloud sharing", systemImage: "icloud") }
                    }
                    if FeatureFlags.communityEnabled {
                        NavigationLink { CommunityHost() } label: { Label("Explore", systemImage: "person.3") }
                    }
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

    /// The people, and the one number they add up to: how many usually sit down to dinner.
    ///
    /// The number used to be a bare stepper above the rules with nothing tying it to the member
    /// list. Here it sits with the people it counts, and each person's page says when they are
    /// away -- which is what takes a day below the usual table.
    private var peopleSection: some View {
        Section {
            Stepper(
                L10n.string("Usually %ld at dinner", store.householdSize),
                value: Binding(get: { store.householdSize }, set: { store.setHouseholdSize($0) }),
                in: 1...20
            )
            .accessibilityIdentifier("family.householdSize")
            ForEach(store.household.members) { member in
                NavigationLink {
                    MemberView(member: member)
                } label: {
                    HStack(spacing: AppTheme.Space.m) {
                        MemberAvatar(member: member, index: memberIndex(member), size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.displayName).foregroundStyle(AppTheme.ink)
                            Text(MemberView.summary(of: member, store: store))
                                .font(.caption).foregroundStyle(AppTheme.muted).lineLimit(1)
                        }
                    }
                }
                .accessibilityIdentifier("family.member.\(memberIndex(member))")
            }
            .onDelete(perform: store.removeHouseholdMembers)
            Button { showingAddMember = true } label: {
                Label("Add member", systemImage: "person.badge.plus")
            }
        } header: {
            Text("People")
        } footer: {
            Text("Portions and shopping follow the usual number. Someone away by their home pattern is taken off that day; guests are added on the day itself.")
        }
    }

    /// The kids view is a child's: it offers the children, or everyone if nobody is marked as one.
    @ViewBuilder private var kidsViewEntry: some View {
        let children = store.household.members.filter { $0.role == .child }
        let candidates = children.isEmpty ? store.household.members : children
        if candidates.count == 1, let only = candidates.first {
            Button { kidsMember = only } label: {
                Label("Kids view", systemImage: "face.smiling")
            }
        } else {
            Menu {
                ForEach(candidates) { member in
                    Button(member.displayName) { kidsMember = member }
                }
            } label: {
                Label("Kids view", systemImage: "face.smiling")
            }
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
