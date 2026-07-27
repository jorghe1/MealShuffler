import SwiftUI

struct HouseholdView: View {
    @EnvironmentObject private var store: AppStore
    @State private var householdName = ""
    @State private var newMemberName = ""
    @State private var showingAddMember = false

    var body: some View {
        List {
            Section("Husholdning") {
                TextField("Navn", text: $householdName)
                    .onSubmit { store.renameHousehold(householdName) }
                ForEach(store.household.members) { member in
                    HStack {
                        Image(systemName: member.role == .child ? "figure.child" : "person.fill")
                            .foregroundStyle(AppTheme.accent).frame(width: 28)
                        Text(member.displayName)
                        Spacer()
                        if member.role == .owner { Text("EIER").font(.caption2.bold()).foregroundStyle(AppTheme.muted) }
                    }
                }.onDelete(perform: store.removeHouseholdMembers)
                Button { showingAddMember = true } label: { Label("Legg til medlem", systemImage: "person.badge.plus") }
            }

            Section("Del") {
                ShareLink(item: store.household.inviteURL) {
                    Label("Del invitasjon", systemImage: "link")
                }
                ShareLink(item: PlanTextExporter.weeklyPlan(store.plan, meals: store.meals)) {
                    Label("Del ukens middagsplan", systemImage: "square.and.arrow.up")
                }
                LabeledContent("Invitasjonskode", value: store.household.inviteCode)
            } footer: {
                Text("MVP-en lager en stabil invitasjonsidentitet lokalt. Synkronisering kobles senere til repository/backend uten å endre husholdningsmodellen.")
            }
        }
        .navigationTitle("Familie")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { householdName = store.household.name }
        .onDisappear { store.renameHousehold(householdName) }
        .alert("Nytt familiemedlem", isPresented: $showingAddMember) {
            TextField("Navn", text: $newMemberName)
            Button("Legg til") { store.addHouseholdMember(named: newMemberName); newMemberName = "" }
            Button("Avbryt", role: .cancel) { newMemberName = "" }
        }
    }
}
