import SwiftUI

struct HouseholdView: View {
    @EnvironmentObject private var store: AppStore
    @State private var householdName = ""
    @State private var newMemberName = ""
    @State private var showingAddMember = false

    var body: some View {
        List {
            Section("Household") {
                TextField("Name", text: $householdName)
                    .onSubmit { store.renameHousehold(householdName) }
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

            Section("Share") {
                ShareLink(item: store.household.inviteURL) {
                    Label("Share invitation", systemImage: "link")
                }
                ShareLink(item: PlanTextExporter.weeklyPlan(store.plan, meals: store.meals)) {
                    Label("Share this week's meal plan", systemImage: "square.and.arrow.up")
                }
                LabeledContent("Invite code", value: store.household.inviteCode)
            } footer: {
                Text("The MVP creates a stable invitation identity locally. Sync can later connect to a repository or backend without changing the household model.")
            }
        }
        .navigationTitle("Family")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { householdName = store.household.name }
        .onDisappear { store.renameHousehold(householdName) }
        .alert("New family member", isPresented: $showingAddMember) {
            TextField("Name", text: $newMemberName)
            Button("Add") { store.addHouseholdMember(named: newMemberName); newMemberName = "" }
            Button("Cancel", role: .cancel) { newMemberName = "" }
        }
    }
}
