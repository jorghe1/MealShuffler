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
                    HStack {
                        Image(systemName: member.role == .child ? "figure.child" : "person.fill")
                            .foregroundStyle(AppTheme.accent).frame(width: 28)
                        Text(member.displayName)
                        Spacer()
                        if member.role == .owner { Text("OWNER").font(.caption2.bold()).foregroundStyle(AppTheme.muted) }
                    }
                }.onDelete(perform: store.removeHouseholdMembers)
                Button { showingAddMember = true } label: { Label("Add member", systemImage: "person.badge.plus") }
            }

            Section {
                ShareLink(item: PlanTextExporter.weeklyPlan(store.plan, meals: store.meals)) {
                    Label("Share this week's meal plan", systemImage: "square.and.arrow.up")
                }
                // The invitation link and code are hidden until there is something on the
                // other end of them. Sharing a code whose only behaviour is an alert saying
                // sync is not built costs more trust than leaving it out.
                if FeatureFlags.householdSyncEnabled {
                    ShareLink(item: store.household.inviteURL) {
                        Label("Share invitation", systemImage: "link")
                    }
                    LabeledContent("Invite code", value: store.household.inviteCode)
                }
            } header: {
                Text("Share")
            } footer: {
                Text("The plan shares as plain text, so it works in any app. Everything stays on this device.")
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
