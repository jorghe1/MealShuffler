import SwiftUI

struct HouseholdView: View {
    @EnvironmentObject private var store: AppStore
    @State private var householdName = ""
    @State private var newMemberName = ""
    @State private var showingAddMember = false

    var body: some View {
        List {
            Section {
                Stepper(
                    L10n.string("%ld people at dinner", store.householdSize),
                    value: Binding(
                        get: { store.householdSize },
                        set: { store.setHouseholdSize($0) }
                    ),
                    in: 1...20
                )
            } header: {
                Text("Servings")
            } footer: {
                Text("Used for portions and shopping quantities. Adding people to the list below does not change it.")
            }

            Section("Household") {
                TextField("Name", text: $householdName)
                    .onSubmit { commitName() }
                ForEach(store.household.members) { member in
                    NavigationLink {
                        MemberTasteView(member: member)
                    } label: { HStack {
                        Image(systemName: member.role == .child ? "figure.child" : "person.fill")
                            .foregroundStyle(AppTheme.accent).frame(width: 28)
                        Text(member.displayName)
                        Spacer()
                        if member.role == .owner { Text("OWNER").font(.caption2.bold()).foregroundStyle(AppTheme.muted) }
                    } }
                }.onDelete(perform: store.removeHouseholdMembers)
                Button { showingAddMember = true } label: { Label("Add member", systemImage: "person.badge.plus") }
            }

            Section {
                ShareLink(item: PlanTextExporter.weeklyPlan(store.plan, meals: store.meals)) {
                    Label("Share this week's meal plan", systemImage: "square.and.arrow.up")
                }
                NavigationLink { CloudSharingView() } label: { Label("iCloud sharing", systemImage: "icloud") }

            } header: {
                Text("Share")
            } footer: {
                Text("Share a dated plan as text, or invite household members through iCloud to edit together.")
            }
        }
        .navigationTitle("Family")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { householdName = store.household.name }
        .onDisappear { commitName() }
        .alert("New family member", isPresented: $showingAddMember) {
            TextField("Name", text: $newMemberName)
            Button("Add") { store.addHouseholdMember(named: newMemberName); newMemberName = "" }
            Button("Cancel", role: .cancel) { newMemberName = "" }
        }
    }

    /// Writes the name back only when there is one.
    ///
    /// This ran unconditionally on disappear from a field seeded on appear, so any path that
    /// rebuilt the view before `onAppear` renamed the household to the placeholder.
    private func commitName() {
        let trimmed = householdName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != store.household.name else { return }
        store.renameHousehold(trimmed)
    }
}

private struct MemberTasteView: View {
    @EnvironmentObject private var store: AppStore
    let member: HouseholdMember
    @State private var search = ""

    var body: some View {
        List {
            Section {
                Button("Avoid these dislikes when present") {
                    let outcome = store.addRule(PlanningRule(title: member.displayName,
                        constraint: .excludedOn(day: .everyDay, matcher: .dislikedBy(memberID: member.id))))
                    switch outcome {
                    case .added: store.actionNotice = L10n.string("Rule added.")
                    case .duplicate(let title): store.actionNotice = L10n.string("This rule already exists: %@", title)
                    case .contradiction(let title): store.actionNotice = L10n.string("This conflicts with: %@", title)
                    }
                }
                Text("Set attendance on a day to apply this person's dislikes only when they are eating.")
            }
            ForEach(store.meals.filter { $0.matches(searchText: search) }) { meal in
                Picker(meal.name, selection: Binding(
                    get: { store.memberPreferences[member.id]?[meal.id] ?? .neutral },
                    set: { store.setPreference($0, for: meal, member: member.id) }
                )) {
                    Text("Like").tag(MealPreference.liked)
                    Text("Neutral").tag(MealPreference.neutral)
                    Text("Dislike").tag(MealPreference.disliked)
                }
            }
        }.navigationTitle(member.displayName).searchable(text: $search, prompt: "Search meals")
    }
}
