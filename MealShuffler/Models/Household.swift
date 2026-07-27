import Foundation

enum HouseholdRole: String, Codable {
    case owner, adult, child
}
struct HouseholdMember: Identifiable, Codable, Hashable {
    let id: UUID
    var displayName: String
    var role: HouseholdRole

    init(id: UUID = UUID(), displayName: String, role: HouseholdRole = .adult) {
        self.id = id
        self.displayName = displayName
        self.role = role
    }
}

struct Household: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var members: [HouseholdMember]
    let inviteCode: String

    init(
        id: UUID = UUID(),
        name: String = L10n.string("My family"),
        members: [HouseholdMember] = [HouseholdMember(displayName: L10n.string("Me"), role: .owner)],
        inviteCode: String = String(UUID().uuidString.prefix(8)).uppercased()
    ) {
        self.id = id
        self.name = name
        self.members = members
        self.inviteCode = inviteCode
    }

    var inviteURL: URL { URL(string: "mealshuffler://join/\(inviteCode)")! }
}
