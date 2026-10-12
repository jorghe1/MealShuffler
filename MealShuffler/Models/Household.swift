import Foundation

enum HouseholdRole: String, Codable {
    case owner, adult, child
}
struct HouseholdMember: Identifiable, Codable, Hashable {
    let id: UUID
    var displayName: String
    var role: HouseholdRole
    /// When this person usually eats at home. Optional so every household saved before it
    /// existed still decodes; nil means at home every day.
    var homePattern: HomePattern?

    init(id: UUID = UUID(), displayName: String, role: HouseholdRole = .adult, homePattern: HomePattern? = nil) {
        self.id = id
        self.displayName = displayName
        self.role = role
        self.homePattern = homePattern
    }

    func isHome(on day: Weekday, inWeekStarting start: Date) -> Bool {
        homePattern?.isHome(on: day, inWeekStarting: start) ?? true
    }
}

/// Who is at the table is mostly predictable: children who live here every other week,
/// training every Tuesday. Entered once, it sets each new week's attendance -- and so the
/// portions and whose dislikes count -- instead of being re-entered day by day, week by week.
struct HomePattern: Codable, Hashable {
    /// Which weeks the person lives here. Week numbers are ISO 8601, as on a Norwegian
    /// calendar, whatever calendar the phone is set to.
    enum Weeks: String, Codable, CaseIterable, Identifiable {
        case every, even, odd
        var id: String { rawValue }
    }

    var weeks: Weeks = .every
    /// Days the person is regularly away for dinner, in the weeks they live here.
    var awayDays: Set<Weekday> = []

    var isAlwaysHome: Bool { weeks == .every && awayDays.isEmpty }

    func isHome(on day: Weekday, inWeekStarting start: Date) -> Bool {
        if awayDays.contains(day) { return false }
        switch weeks {
        case .every: return true
        case .even, .odd:
            // The day's own date, so a week that starts on Sunday in the phone's locale is
            // still judged by the ISO week each dinner falls in.
            let isEven = Self.isoWeekNumber(of: day.date(inWeekStarting: start)) % 2 == 0
            return isEven == (weeks == .even)
        }
    }

    static func isoWeekNumber(of date: Date) -> Int {
        Calendar(identifier: .iso8601).component(.weekOfYear, from: date)
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
